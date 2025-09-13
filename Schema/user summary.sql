create or replace function get_user_summaries_v2(
    p_start_date date default null,
    p_end_date date default null,
    p_user_filter text default null,
    p_client_filter text default null,
    p_sort_field text default 'username',
    p_sort_order text default 'asc',
    p_limit_count int default 50,
    p_offset_count int default 0
)
returns table (
    user_id int,
    username text,
    start_date date,
    end_date date,
    total_hours numeric,
    days_worked int,
    daily_average numeric,
    clients text[],
    task_custom_fields text[]
)
language plpgsql
as $$
begin
    return query
    with user_timesheet_data as (
        select 
            t.user_id,
            coalesce(u.username, trim(u.first_name || ' ' || u.last_name)) as username,
            t.id as timesheet_id,
            t.jobcode_id,
            j.name as jobcode_name,
            nullif(t."start", '')::timestamptz as start_ts,
            nullif(t."end", '')::timestamptz as end_ts,
            extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz))/3600.0 as hours,
            date(nullif(t."start", '')::timestamptz) as work_date,
            tcf.customfield_id,
            cf.name as custom_field_name,
            tcf.value as custom_field_value,
            cfo.name as custom_field_option_name
        from public.timesheets t
        join public.users u on u.id = t.user_id
        join public.jobcodes j on j.id = t.jobcode_id
        left join public.timesheet_customfield_values tcf on tcf.timesheet_id = t.id
        left join public.custom_fields cf on cf.id = tcf.customfield_id
        left join public.custom_field_options cfo 
            on cfo.customfield_id = cf.id 
           and cfo.name = tcf.value
        where 
            (p_start_date is null or date(nullif(t."start", '')::timestamptz) >= p_start_date)
            and (p_end_date is null or date(nullif(t."start", '')::timestamptz) <= p_end_date)
            and (p_user_filter is null or coalesce(u.username, trim(u.first_name || ' ' || u.last_name)) ilike '%' || p_user_filter || '%')
            and (p_client_filter is null or j.name ilike '%' || p_client_filter || '%')
            and nullif(t."start", '') is not null 
            and nullif(t."end", '') is not null
    ),
    user_summary as (
        select 
            utd.user_id,
            utd.username,
            min(utd.work_date) as start_date,
            max(utd.work_date) as end_date,
            round(sum(utd.hours)::numeric, 2) as total_hours,
            count(distinct utd.work_date) as days_worked,
            round(sum(utd.hours)::numeric / nullif(count(distinct utd.work_date), 0), 2) as daily_average,
            array_agg(distinct utd.jobcode_name) filter (where utd.jobcode_name is not null) as clients,
            array_agg(distinct utd.custom_field_option_name) filter (where utd.custom_field_option_name is not null) as task_custom_fields
        from user_timesheet_data utd
        group by utd.user_id, utd.username
    )
    select 
        us.user_id,
        us.username,
        us.start_date,
        us.end_date,
        us.total_hours,
        us.days_worked,
        us.daily_average,
        us.clients,
        us.task_custom_fields
    from user_summary us
    order by
        case when p_sort_field='username' and p_sort_order='asc' then us.username end asc,
        case when p_sort_field='username' and p_sort_order='desc' then us.username end desc,
        case when p_sort_field='total_hours' and p_sort_order='asc' then us.total_hours end asc,
        case when p_sort_field='total_hours' and p_sort_order='desc' then us.total_hours end desc,
        case when p_sort_field='daily_average' and p_sort_order='asc' then us.daily_average end asc,
        case when p_sort_field='daily_average' and p_sort_order='desc' then us.daily_average end desc
    limit p_limit_count offset p_offset_count;
end;
$$;
