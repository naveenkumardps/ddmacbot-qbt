-- Client Time Summary Function - Total time spent by all users on each client
CREATE OR REPLACE FUNCTION public.get_client_time_summary(
    p_start_date date default null,
    p_end_date date default null,
    p_client_filter text default null,
    p_project_filter text default null,
    p_limit_count int default 10,
    p_offset_count int default 0
)
returns table (
    client_name text,
    total_hours numeric,
    client_start_date date,
    client_end_date date,
    total_users bigint,
    total_count bigint
) language plpgsql as $$
begin
    return query
    with client_timesheet_data as (
        select
            j.name as client_name_col,
            t.user_id,
            case 
                when t.duration is not null and t.duration > 0 then
                    -- If duration exists and is reasonable (likely in seconds), convert to hours
                    case 
                        when t.duration > 86400 then t.duration / 3600.0  -- If > 1 day, assume seconds
                        when t.duration > 24 then t.duration / 3600.0      -- If > 24 hours, assume seconds  
                        when t.duration > 1 then t.duration                 -- If 1-24, assume already in hours
                        else t.duration * 24                                -- If < 1, assume days
                    end
                else
                    -- Calculate from start/end timestamps
                    extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)) / 3600.0
            end as hours,
            nullif(t.start, '')::date as work_date,
            nullif(t."end", '')::date as end_date
        from public.timesheets t
        join public.jobcodes j on t.jobcode_id = j.id
        left join public.projects p on p.jobcode_id = j.id
        where t.start is not null
          and t."end" is not null
          and (p_start_date is null or nullif(t.start, '')::date >= p_start_date)
          and (p_end_date is null or nullif(t."end", '')::date <= p_end_date)
          and (p_client_filter is null or j.name ilike '%' || p_client_filter || '%')
          and (p_project_filter is null or p.name ilike '%' || p_project_filter || '%')
    ),
    client_summary as (
        select
            client_name_col,
            sum(hours) as total_hours,
            min(work_date) as client_start_date,
            max(end_date) as client_end_date,
            count(distinct user_id) as total_users
        from client_timesheet_data
        group by client_name_col
    ),
    total_count_query as (
        select count(*) as total_clients from client_summary
    )
    select
        cs.client_name_col as client_name,
        round(cs.total_hours, 2) as total_hours,
        cs.client_start_date,
        cs.client_end_date,
        cs.total_users,
        tc.total_clients as total_count
    from client_summary cs
    cross join total_count_query tc
    order by cs.total_hours desc, cs.client_name_col
    limit p_limit_count offset p_offset_count;
end;
$$;

-- Count function for pagination
CREATE OR REPLACE FUNCTION public.get_client_time_summary_count(
    p_start_date date default null,
    p_end_date date default null,
    p_client_filter text default null,
    p_project_filter text default null
)
returns int language plpgsql as $$
declare
    client_count int;
begin
    with client_timesheet_data as (
        select distinct j.name as client_name_col
        from public.timesheets t
        join public.jobcodes j on t.jobcode_id = j.id
        left join public.projects p on p.jobcode_id = j.id
        where t.start is not null
          and t."end" is not null
          and (p_start_date is null or nullif(t.start, '')::date >= p_start_date)
          and (p_end_date is null or nullif(t."end", '')::date <= p_end_date)
          and (p_client_filter is null or j.name ilike '%' || p_client_filter || '%')
          and (p_project_filter is null or p.name ilike '%' || p_project_filter || '%')
    )
    select count(*) into client_count from client_timesheet_data;
    
    return client_count;
end;
$$;

-- Function to get client list for dropdown
CREATE OR REPLACE FUNCTION public.get_client_list()
returns table (
    client_name text
) language sql as $$
    select distinct j.name as client_name
    from public.jobcodes j
    where j.active = true
    order by j.name;
$$;

-- Function to get project list for dropdown
CREATE OR REPLACE FUNCTION public.get_project_list()
returns table (
    project_name text
) language sql as $$
    select distinct p.name as project_name
    from public.projects p
    where p.active = true
    order by p.name;
$$;

-- Function to get user-wise data for a specific client
CREATE OR REPLACE FUNCTION public.get_client_user_data(
    p_client_name text,
    p_start_date date default null,
    p_end_date date default null,
    p_project_filter text default null,
    p_user_id_filter bigint default null,
    p_limit_count int default 10,
    p_offset_count int default 0
)
returns table (
    user_id bigint,
    username text,
    total_hours numeric,
    user_start_date date,
    user_end_date date,
    days_worked bigint,
    avg_hours_per_day numeric,
    projects text[],
    total_count bigint
) language plpgsql as $$
begin
    return query
    with user_timesheet_data as (
        select
            t.user_id as user_id_col,
            coalesce(u.username, trim(u.first_name || ' ' || u.last_name)) as username_col,
            j.name as client_name_col,
            p.name as project_name_col,
            case 
                when t.duration is not null and t.duration > 0 then
                    -- If duration exists and is reasonable (likely in seconds), convert to hours
                    case 
                        when t.duration > 86400 then t.duration / 3600.0  -- If > 1 day, assume seconds
                        when t.duration > 24 then t.duration / 3600.0      -- If > 24 hours, assume seconds  
                        when t.duration > 1 then t.duration                 -- If 1-24, assume already in hours
                        else t.duration * 24                                -- If < 1, assume days
                    end
                else
                    -- Calculate from start/end timestamps
                    extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)) / 3600.0
            end as hours,
            nullif(t.start, '')::date as work_date,
            nullif(t."end", '')::date as end_date
        from public.timesheets t
        join public.users u on u.id = t.user_id
        join public.jobcodes j on t.jobcode_id = j.id
        left join public.projects p on p.jobcode_id = j.id
        where t.start is not null
          and t."end" is not null
          and j.name = p_client_name
          and (p_start_date is null or nullif(t.start, '')::date >= p_start_date)
          and (p_end_date is null or nullif(t."end", '')::date <= p_end_date)
          and (p_project_filter is null or p.name ilike '%' || p_project_filter || '%')
          and (p_user_id_filter is null or t.user_id = p_user_id_filter)
    ),
    user_summary as (
        select
            user_id_col,
            username_col,
            sum(hours) as total_hours,
            min(work_date) as user_start_date,
            max(end_date) as user_end_date,
            count(distinct work_date) as days_worked,
            array_agg(distinct project_name_col) filter (where project_name_col is not null) as projects
        from user_timesheet_data
        group by user_id_col, username_col
    ),
    total_count_query as (
        select count(*) as total_users from user_summary
    )
    select
        us.user_id_col as user_id,
        us.username_col as username,
        round(us.total_hours, 2) as total_hours,
        us.user_start_date,
        us.user_end_date,
        us.days_worked,
        round(us.total_hours / nullif(us.days_worked, 0), 2) as avg_hours_per_day,
        us.projects,
        tc.total_users as total_count
    from user_summary us
    cross join total_count_query tc
    order by us.total_hours desc, us.username_col
    limit p_limit_count offset p_offset_count;
end;
$$;

-- Count function for client user data pagination
CREATE OR REPLACE FUNCTION public.get_client_user_data_count(
    p_client_name text,
    p_start_date date default null,
    p_end_date date default null,
    p_project_filter text default null,
    p_user_id_filter bigint default null
)
returns int language plpgsql as $$
declare
    user_count int;
begin
    with user_timesheet_data as (
        select distinct t.user_id as user_id_col
        from public.timesheets t
        join public.jobcodes j on t.jobcode_id = j.id
        left join public.projects p on p.jobcode_id = j.id
        where t.start is not null
          and t."end" is not null
          and j.name = p_client_name
          and (p_start_date is null or nullif(t.start, '')::date >= p_start_date)
          and (p_end_date is null or nullif(t."end", '')::date <= p_end_date)
          and (p_project_filter is null or p.name ilike '%' || p_project_filter || '%')
          and (p_user_id_filter is null or t.user_id = p_user_id_filter)
    )
    select count(*) into user_count from user_timesheet_data;
    
    return user_count;
end;
$$;
