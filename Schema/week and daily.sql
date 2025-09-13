create or replace function get_user_daily_timesheet_summary(
    p_user_id bigint,
    p_start_date date default null,
    p_end_date date default null,
    p_jobcode_filter text default null
)
returns table (
    work_day text,
    client text,
    task text,
    hours numeric
)
language plpgsql
as $$
begin
    return query
    with ts as (
        select 
            date(nullif(t."start", '')::timestamptz) as day_col,
            j.name as client,
            cfo.name as task,
            extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz))/3600.0 as hours
        from public.timesheets t
        join public.jobcodes j on j.id = t.jobcode_id
        left join public.timesheet_customfield_values tcv 
            on tcv.timesheet_id = t.id
        left join public.custom_field_options cfo 
            on cfo.id = (
                case 
                    when tcv.value ~ '^\d+$' then tcv.value::bigint
                    else null
                end
            )
        where t.user_id = p_user_id
          and nullif(t."start", '') is not null
          and nullif(t."end", '') is not null
          and (p_start_date is null or date(nullif(t."start", '')::timestamptz) >= p_start_date)
          and (p_end_date is null or date(nullif(t."start", '')::timestamptz) <= p_end_date)
          and (p_jobcode_filter is null or j.name ilike '%' || p_jobcode_filter || '%')
    )
    select 
        to_char(ts.day_col, 'DD-MM-YYYY') as work_day,
        ts.client,
        coalesce(ts.task, 'Unspecified') as task,
        sum(ts.hours) as hours
    from ts
    group by ts.day_col, ts.client, ts.task
    order by ts.day_col, ts.client, ts.task;
end;
$$;


create or replace function get_user_weekly_timesheet_summary(
    p_user_id bigint,
    p_start_date date default null,
    p_end_date date default null,
    p_jobcode_filter text default null
)
returns table (
    work_week text,
    client text,
    task text,
    hours numeric
)
language plpgsql
as $$
begin
    return query
    with ts as (
        select 
            date_trunc('week', nullif(t."start", '')::timestamptz)::date as week_col,
            j.name as client,
            cfo.name as task,
            extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz))/3600.0 as hours
        from public.timesheets t
        join public.jobcodes j on j.id = t.jobcode_id
        left join public.timesheet_customfield_values tcv 
            on tcv.timesheet_id = t.id
        left join public.custom_field_options cfo 
            on cfo.id = (
                case 
                    when tcv.value ~ '^\d+$' then tcv.value::bigint
                    else null
                end
            )
        where t.user_id = p_user_id
          and nullif(t."start", '') is not null
          and nullif(t."end", '') is not null
          and (p_start_date is null or date(nullif(t."start", '')::timestamptz) >= p_start_date)
          and (p_end_date is null or date(nullif(t."start", '')::timestamptz) <= p_end_date)
          and (p_jobcode_filter is null or j.name ilike '%' || p_jobcode_filter || '%')
    )
    select 
        to_char(ts.week_col, 'DD-MM-YYYY') as work_week,
        ts.client,
        coalesce(ts.task, 'Unspecified') as task,
        sum(ts.hours) as hours
    from ts
    group by ts.week_col, ts.client, ts.task
    order by ts.week_col, ts.client, ts.task;
end;
$$;
