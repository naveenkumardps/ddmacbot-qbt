

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."calculate_working_days"("p_start_date" "date", "p_end_date" "date") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    day_count INTEGER := 0;
    current_day DATE := p_start_date;
BEGIN
    WHILE current_day <= p_end_date LOOP
        -- Check if it's not a weekend (Saturday = 6, Sunday = 0)
        IF EXTRACT(DOW FROM current_day) NOT IN (0, 6) THEN
            day_count := day_count + 1;
        END IF;
        current_day := current_day + INTERVAL '1 day';
    END LOOP;
    
    RETURN day_count;
END;
$$;


ALTER FUNCTION "public"."calculate_working_days"("p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_accubid_task_summary"("p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0, "p_job_name" "text" DEFAULT NULL::"text", "p_user_id" integer DEFAULT NULL::integer, "p_jobcode_id" integer DEFAULT NULL::integer) RETURNS TABLE("duration_hours" numeric, "task_name" "text", "time_estimate" numeric, "job_name" "text")
    LANGUAGE "plpgsql"
    AS $$begin
    return query
    select 
        (sum(t.duration) / 3600.0)::numeric as duration_hours, -- seconds → hours
        ab."Task_name" as task_name,
        ab.time_estimate::numeric,  -- FIXED: cast to numeric
        ab.job_name
    from accubid_breakdowns ab
    left join timesheet_customfield_values tcv 
        on tcv.value = ab."Task_name"
    left join timesheets t 
        on t.id = tcv.timesheet_id
    where   (p_job_name is null or ab.job_name = p_job_name)
      and (p_user_id is null or t.user_id = p_user_id)
      and (p_jobcode_id is null or t.jobcode_id = p_jobcode_id)
      
    group by ab.job_name, ab.time_estimate, ab."Task_name"
    order by duration_hours desc
    limit p_limit offset p_offset;
end;$$;


ALTER FUNCTION "public"."get_accubid_task_summary"("p_limit" integer, "p_offset" integer, "p_job_name" "text", "p_user_id" integer, "p_jobcode_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_all_employees_summary"("p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "full_name" "text", "work_start_date" "date", "work_end_date" "date", "total_work_hours" numeric, "actual_work_days" bigint, "average_daily_hours" numeric, "client_list" "text"[], "task_list" "text"[], "custom_field_values" "text"[])
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM get_employee_summary_data(NULL, p_start_date, p_end_date);
END;
$$;


ALTER FUNCTION "public"."get_all_employees_summary"("p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_comparison"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("metric_name" "text", "client_value" numeric, "ddmac_average" numeric, "client_rank" bigint, "total_clients" bigint, "percentile" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH client_metrics AS (
        SELECT 
            j.id as client_id,
            j.name as client_name,
            COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
            COUNT(DISTINCT t.user_id) as users_assigned,
            COUNT(t.id) as total_sessions,
            COUNT(DISTINCT t.date) as working_days,
            CASE 
                WHEN COUNT(t.id) > 0 THEN 
                    COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
                ELSE 0
            END as avg_session_length,
            CASE 
                WHEN COUNT(DISTINCT t.date) > 0 THEN 
                    COALESCE(SUM(t.duration) / 3600.0, 0) / (COUNT(DISTINCT t.date) / 7.0)
                ELSE 0
            END as hours_per_week
        FROM jobcodes j
        LEFT JOIN timesheets t ON j.id = t.jobcode_id
        WHERE j.active = true
            AND (t.date IS NULL OR (t.date >= start_date_param AND t.date <= end_date_param))
        GROUP BY j.id, j.name
    ),
    ranked_metrics AS (
        SELECT 
            client_id,
            client_name,
            total_hours,
            users_assigned,
            total_sessions,
            working_days,
            avg_session_length,
            hours_per_week,
            RANK() OVER (ORDER BY total_hours DESC) as total_hours_rank,
            RANK() OVER (ORDER BY users_assigned DESC) as users_rank,
            RANK() OVER (ORDER BY avg_session_length DESC) as session_length_rank,
            RANK() OVER (ORDER BY working_days DESC) as working_days_rank,
            RANK() OVER (ORDER BY hours_per_week DESC) as hours_per_week_rank,
            COUNT(*) OVER() as total_clients
        FROM client_metrics
    )
    SELECT 
        'Total Hours'::TEXT as metric_name,
        cm.total_hours as client_value,
        AVG(cm.total_hours) OVER() as ddmac_average,
        rm.total_hours_rank as client_rank,
        rm.total_clients,
        (rm.total_clients - rm.total_hours_rank + 1)::NUMERIC / rm.total_clients * 100 as percentile
    FROM client_metrics cm
    JOIN ranked_metrics rm ON cm.client_id = rm.client_id
    WHERE cm.client_id = client_id_param
    
    UNION ALL
    
    SELECT 
        'Users Assigned'::TEXT as metric_name,
        cm.users_assigned as client_value,
        AVG(cm.users_assigned) OVER() as ddmac_average,
        rm.users_rank as client_rank,
        rm.total_clients,
        (rm.total_clients - rm.users_rank + 1)::NUMERIC / rm.total_clients * 100 as percentile
    FROM client_metrics cm
    JOIN ranked_metrics rm ON cm.client_id = rm.client_id
    WHERE cm.client_id = client_id_param
    
    UNION ALL
    
    SELECT 
        'Avg Session Length'::TEXT as metric_name,
        cm.avg_session_length as client_value,
        AVG(cm.avg_session_length) OVER() as ddmac_average,
        rm.session_length_rank as client_rank,
        rm.total_clients,
        (rm.total_clients - rm.session_length_rank + 1)::NUMERIC / rm.total_clients * 100 as percentile
    FROM client_metrics cm
    JOIN ranked_metrics rm ON cm.client_id = rm.client_id
    WHERE cm.client_id = client_id_param
    
    UNION ALL
    
    SELECT 
        'Working Days'::TEXT as metric_name,
        cm.working_days as client_value,
        AVG(cm.working_days) OVER() as ddmac_average,
        rm.working_days_rank as client_rank,
        rm.total_clients,
        (rm.total_clients - rm.working_days_rank + 1)::NUMERIC / rm.total_clients * 100 as percentile
    FROM client_metrics cm
    JOIN ranked_metrics rm ON cm.client_id = rm.client_id
    WHERE cm.client_id = client_id_param
    
    UNION ALL
    
    SELECT 
        'Hours per Week'::TEXT as metric_name,
        cm.hours_per_week as client_value,
        AVG(cm.hours_per_week) OVER() as ddmac_average,
        rm.hours_per_week_rank as client_rank,
        rm.total_clients,
        (rm.total_clients - rm.hours_per_week_rank + 1)::NUMERIC / rm.total_clients * 100 as percentile
    FROM client_metrics cm
    JOIN ranked_metrics rm ON cm.client_id = rm.client_id
    WHERE cm.client_id = client_id_param;
END;
$$;


ALTER FUNCTION "public"."get_client_comparison"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_list"() RETURNS TABLE("client_name" "text")
    LANGUAGE "sql"
    AS $$
    select distinct j.name as client_name
    from public.jobcodes j
    where j.active = true
    order by j.name;
$$;


ALTER FUNCTION "public"."get_client_list"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_overview_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("total_hours" numeric, "users_assigned" bigint, "total_sessions" bigint, "avg_hours_per_day" numeric, "working_days" bigint, "first_date_worked" "date", "last_date_worked" "date")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.user_id) as users_assigned,
        COUNT(t.id) as total_sessions,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date)
            ELSE 0
        END as avg_hours_per_day,
        COUNT(DISTINCT t.date) as working_days,
        MIN(t.date) as first_date_worked,
        MAX(t.date) as last_date_worked
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE j.id = client_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param;
END;
$$;


ALTER FUNCTION "public"."get_client_overview_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_time_summary"("p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_client_filter" "text" DEFAULT NULL::"text", "p_project_filter" "text" DEFAULT NULL::"text", "p_limit_count" integer DEFAULT 10, "p_offset_count" integer DEFAULT 0) RETURNS TABLE("client_name" "text", "total_hours" numeric, "client_start_date" "date", "client_end_date" "date", "total_users" bigint, "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    with client_timesheet_data as (
        select
            j.name as client_name_col,
            t.user_id,
            coalesce(
                t.duration,
                extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)) / 3600.0
            ) as hours,
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


ALTER FUNCTION "public"."get_client_time_summary"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_time_summary_count"("p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_client_filter" "text" DEFAULT NULL::"text", "p_project_filter" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
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


ALTER FUNCTION "public"."get_client_time_summary_count"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_user_allocation"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("user_name" "text", "total_hours" numeric, "percentage" numeric, "sessions" bigint, "avg_session_hours" numeric, "first_date" "date", "last_date" "date")
    LANGUAGE "plpgsql"
    AS $$BEGIN
    RETURN QUERY
    WITH client_total_hours AS (
        SELECT COALESCE(SUM(t.duration) / 3600.0, 0) as total_client_hours
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        WHERE j.id = client_id_param
            AND t.date >= start_date_param
            AND t.date <= end_date_param
    )
    SELECT 
        COALESCE(u.username, CONCAT(u.first_name, ' ', u.last_name)) as user_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        CASE 
            WHEN cth.total_client_hours > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / cth.total_client_hours * 100)
            ELSE 0
        END as percentage,
        COUNT(t.id) as sessions,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_hours,
        MIN(t.date) as first_date,
        MAX(t.date) as last_date
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    JOIN users u ON t.user_id = u.id
    CROSS JOIN client_total_hours cth
    WHERE j.id = client_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param
    GROUP BY u.id, u.username, u.first_name, u.last_name, cth.total_client_hours
    ORDER BY total_hours DESC;
END;$$;


ALTER FUNCTION "public"."get_client_user_allocation"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_project_filter" "text" DEFAULT NULL::"text", "p_limit_count" integer DEFAULT 10, "p_offset_count" integer DEFAULT 0) RETURNS TABLE("user_id" bigint, "username" "text", "total_hours" numeric, "user_start_date" "date", "user_end_date" "date", "days_worked" bigint, "avg_hours_per_day" numeric, "projects" "text"[], "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    with user_timesheet_data as (
        select
            t.user_id as user_id_col,
            coalesce(u.username, trim(u.first_name || ' ' || u.last_name)) as username_col,
            j.name as client_name_col,
            p.name as project_name_col,
            coalesce(
                t.duration,
                extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)) / 3600.0
            ) as hours,
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


ALTER FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_project_filter" "text" DEFAULT NULL::"text", "p_user_id_filter" bigint DEFAULT NULL::bigint, "p_limit_count" integer DEFAULT 10, "p_offset_count" integer DEFAULT 0) RETURNS TABLE("user_id" bigint, "username" "text", "total_hours" numeric, "user_start_date" "date", "user_end_date" "date", "days_worked" bigint, "avg_hours_per_day" numeric, "projects" "text"[], "total_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    with user_timesheet_data as (
        select
            t.user_id as user_id_col,
            coalesce(u.username, trim(u.first_name || ' ' || u.last_name)) as username_col,
            j.name as client_name_col,
            p.name as project_name_col,
            coalesce(
                t.duration,
                extract(epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)) / 3600.0
            ) as hours,
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


ALTER FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint, "p_limit_count" integer, "p_offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_project_filter" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
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
    )
    select count(*) into user_count from user_timesheet_data;
    
    return user_count;
end;
$$;


ALTER FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_project_filter" "text" DEFAULT NULL::"text", "p_user_id_filter" bigint DEFAULT NULL::bigint) RETURNS integer
    LANGUAGE "plpgsql"
    AS $$
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


ALTER FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_client_weekly_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("week_start" "date", "week_end" "date", "total_hours" numeric, "users_active" bigint, "sessions" bigint, "avg_session_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        DATE_TRUNC('week', t.date)::DATE as week_start,
        (DATE_TRUNC('week', t.date) + INTERVAL '6 days')::DATE as week_end,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.user_id) as users_active,
        COUNT(t.id) as sessions,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_hours
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE j.id = client_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param
    GROUP BY DATE_TRUNC('week', t.date)
    ORDER BY week_start DESC;
END;
$$;


ALTER FUNCTION "public"."get_client_weekly_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_comprehensive_employee_analytics"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "full_name" "text", "work_start_date" "date", "work_end_date" "date", "total_work_hours" numeric, "actual_work_days" bigint, "average_daily_hours" numeric, "client_list" "text"[], "task_list" "text"[], "utilization_percentage" numeric, "productivity_score" numeric, "performance_rating" "text", "total_entries" bigint, "billable_hours" numeric, "overtime_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH employee_work_data AS (
        SELECT 
            u.id as employee_id,
            u.username as employee_name,
            COALESCE(u.display_name, CONCAT(u.first_name, ' ', u.last_name)) as full_name,
            
            -- Calculate total hours and work days
            ROUND(COALESCE(SUM(t.duration) / 3600.0, 0), 2) as total_work_hours,
            COUNT(DISTINCT t.date) as actual_work_days,
            CASE 
                WHEN COUNT(DISTINCT t.date) > 0 THEN 
                    ROUND(COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date), 2)
                ELSE 0
            END as average_daily_hours,
            
            -- Count total entries
            COUNT(t.id) as total_entries,
            
            -- Calculate billable hours (assuming all are billable for now)
            ROUND(COALESCE(SUM(t.duration) / 3600.0, 0), 2) as billable_hours,
            
            -- Calculate overtime hours (hours over 8 per day)
            CASE 
                WHEN COUNT(DISTINCT t.date) > 0 THEN 
                    GREATEST(0, (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date)) - 8) * COUNT(DISTINCT t.date)
                ELSE 0
            END as overtime_hours,
            
            -- Date range
            MIN(t.date) as work_start_date,
            MAX(t.date) as work_end_date
            
        FROM users u
        LEFT JOIN timesheets t ON u.id = t.user_id 
            AND (start_date_param IS NULL OR t.date >= start_date_param)
            AND (end_date_param IS NULL OR t.date <= end_date_param)
        WHERE u.active = true
        GROUP BY u.id, u.username, u.display_name, u.first_name, u.last_name
    ),
    
    employee_clients AS (
        SELECT 
            t.user_id,
            ARRAY_AGG(DISTINCT j.name ORDER BY j.name) as clients
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        WHERE (start_date_param IS NULL OR t.date >= start_date_param)
            AND (end_date_param IS NULL OR t.date <= end_date_param)
        GROUP BY t.user_id
    ),
    
    employee_tasks AS (
        SELECT 
            t.user_id,
            ARRAY_AGG(DISTINCT COALESCE(p.name, j.name) ORDER BY COALESCE(p.name, j.name)) as tasks
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        WHERE (start_date_param IS NULL OR t.date >= start_date_param)
            AND (end_date_param IS NULL OR t.date <= end_date_param)
        GROUP BY t.user_id
    )
    
    SELECT 
        ewd.employee_id,
        ewd.employee_name,
        ewd.full_name,
        ewd.work_start_date,
        ewd.work_end_date,
        ewd.total_work_hours,
        ewd.actual_work_days,
        ewd.average_daily_hours,
        COALESCE(ec.clients, ARRAY[]::TEXT[]) as client_list,
        COALESCE(et.tasks, ARRAY[]::TEXT[]) as task_list,
        
        -- Calculate utilization percentage (daily hours / 8 * 100)
        CASE 
            WHEN ewd.average_daily_hours > 0 THEN 
                LEAST(100.0, (ewd.average_daily_hours / 8.0) * 100)
            ELSE 0
        END as utilization_percentage,
        
        -- Calculate productivity score (efficiency + consistency)
        CASE 
            WHEN ewd.average_daily_hours > 0 THEN 
                LEAST(100.0, (ewd.average_daily_hours / 8.0) * 100)
            ELSE 0
        END as productivity_score,
        
        -- Performance rating based on daily hours
        CASE 
            WHEN ewd.average_daily_hours >= 8.0 THEN 'Excellent'
            WHEN ewd.average_daily_hours >= 6.0 THEN 'Good'
            WHEN ewd.average_daily_hours >= 4.0 THEN 'Average'
            ELSE 'Needs Improvement'
        END as performance_rating,
        
        ewd.total_entries,
        ewd.billable_hours,
        ewd.overtime_hours
        
    FROM employee_work_data ewd
    LEFT JOIN employee_clients ec ON ewd.employee_id = ec.user_id
    LEFT JOIN employee_tasks et ON ewd.employee_id = et.user_id
    WHERE ewd.total_work_hours > 0  -- Only include employees with work hours
    ORDER BY ewd.total_work_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_comprehensive_employee_analytics"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_dashboard_summary"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("total_employees" bigint, "active_employees" bigint, "total_projects" bigint, "active_projects" bigint, "total_hours" numeric, "billable_hours" numeric, "total_revenue" numeric, "avg_utilization" numeric, "project_health_score" numeric, "total_tasks" bigint, "avg_task_duration" numeric, "cost_efficiency" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(DISTINCT u.id) as total_employees,
        COUNT(DISTINCT CASE WHEN u.active = true THEN u.id END) as active_employees,
        COUNT(DISTINCT j.id) as total_projects,
        COUNT(DISTINCT CASE WHEN j.active = true THEN j.id END) as active_projects,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0) as billable_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END), 0) as total_revenue,
        CASE 
            WHEN COUNT(DISTINCT u.id) > 0 THEN
                LEAST(COALESCE(SUM(t.duration) / 3600.0, 0) / (COUNT(DISTINCT u.id) * 40.0), 1.0)
            ELSE 0
        END as avg_utilization,
        -- Project health score based on jobcode activity and billable status
        CASE 
            WHEN COUNT(DISTINCT j.id) > 0 THEN
                (COUNT(DISTINCT CASE WHEN j.active = true AND j.billable = true THEN j.id END) * 1.0 +
                 COUNT(DISTINCT CASE WHEN j.active = true AND j.billable = false THEN j.id END) * 0.7 +
                 COUNT(DISTINCT CASE WHEN j.active = false THEN j.id END) * 0.3) / 
                COUNT(DISTINCT j.id) * 10
            ELSE 0
        END as project_health_score,
        COUNT(DISTINCT j.id) as total_tasks,
        CASE 
            WHEN COUNT(t.id) > 0 THEN
                AVG(t.duration) / 3600.0
            ELSE 0
        END as avg_task_duration,
        CASE 
            WHEN SUM(t.duration / 3600.0 * 50) > 0 THEN
                SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END) / 
                SUM(t.duration / 3600.0 * 50) * 100
            ELSE 0
        END as cost_efficiency
    FROM users u
    LEFT JOIN timesheets t ON u.id = t.user_id
    LEFT JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param);
END;
$$;


ALTER FUNCTION "public"."get_dashboard_summary"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_analytics"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "first_name" "text", "last_name" "text", "display_name" "text", "email" "text", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "avg_daily_hours" numeric, "utilization_rate" numeric, "productivity_score" numeric, "active_projects" bigint, "last_active" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id as employee_id,
        u.first_name,
        u.last_name,
        u.display_name,
        u.email,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0) as billable_hours,
        COUNT(t.id) as total_entries,
        COALESCE(AVG(t.duration) / 3600.0, 0) as avg_daily_hours,
        CASE 
            WHEN u.salaried = true THEN 
                LEAST(COALESCE(SUM(t.duration) / 3600.0, 0) / 40.0, 1.0)
            ELSE 
                LEAST(COALESCE(SUM(t.duration) / 3600.0, 0) / 40.0, 1.0)
        END as utilization_rate,
        -- Productivity score based on hours and project diversity
        CASE 
            WHEN COUNT(DISTINCT t.jobcode_id) > 0 THEN 
                LEAST(COALESCE(SUM(t.duration) / 3600.0, 0) / 40.0 * (COUNT(DISTINCT t.jobcode_id) / 2.0), 10.0)
            ELSE 0
        END as productivity_score,
        COUNT(DISTINCT t.jobcode_id) as active_projects,
        u.last_active
    FROM users u
    LEFT JOIN timesheets t ON u.id = t.user_id
    LEFT JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE u.active = true
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY u.id, u.first_name, u.last_name, u.display_name, u.email, u.salaried, u.last_active
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_employee_analytics"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_client_distribution"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("client_name" "text", "total_hours" numeric, "billable_hours" numeric, "days_worked" bigint, "average_hours_per_day" numeric, "percentage_of_total" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_user_hours NUMERIC;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    -- Get total hours for percentage calculation
    SELECT COALESCE(SUM(t.duration) / 3600.0, 0) INTO v_total_user_hours
    FROM timesheets t
    WHERE t.user_id = p_user_id
        AND t.date >= v_start_date 
        AND t.date <= v_end_date;
    
    RETURN QUERY
    SELECT 
        j.name as client_name,
        COALESCE(SUM(t.duration) / 3600.0, 0)::NUMERIC as total_hours,
        COALESCE(SUM(CASE WHEN j.billable THEN t.duration ELSE 0 END) / 3600.0, 0)::NUMERIC as billable_hours,
        COUNT(DISTINCT t.date)::BIGINT as days_worked,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date))::NUMERIC
            ELSE 0::NUMERIC
        END as average_hours_per_day,
        CASE 
            WHEN v_total_user_hours > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / v_total_user_hours * 100)::NUMERIC
            ELSE 0::NUMERIC
        END as percentage_of_total
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE t.user_id = p_user_id
        AND t.date >= v_start_date 
        AND t.date <= v_end_date
    GROUP BY j.name, j.billable
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_employee_client_distribution"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_complete_analytics"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_period_type" "text" DEFAULT 'daily'::"text") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "full_name" "text", "work_start_date" "date", "work_end_date" "date", "total_work_hours" numeric, "actual_work_days" bigint, "average_daily_hours" numeric, "client_list" "text"[], "task_list" "text"[], "custom_field_values" "text"[], "breakdown_date" "date", "breakdown_client" "text", "breakdown_task" "text", "breakdown_hours" numeric, "breakdown_job_code" "text", "breakdown_custom_fields" "text"[])
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    RETURN QUERY
    WITH employee_summary AS (
        SELECT 
            u.id as employee_id,
            u.username as employee_name,
            COALESCE(u.display_name, CONCAT(u.first_name, ' ', u.last_name)) as full_name,
            v_start_date as work_start_date,
            v_end_date as work_end_date,
            COALESCE(SUM(t.duration) / 3600.0, 0)::NUMERIC as total_work_hours,
            COUNT(DISTINCT t.date)::BIGINT as actual_work_days,
            CASE 
                WHEN COUNT(DISTINCT t.date) > 0 THEN 
                    (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date))::NUMERIC
                ELSE 0::NUMERIC
            END as average_daily_hours,
            ARRAY_AGG(DISTINCT j.name ORDER BY j.name) as client_list,
            ARRAY_AGG(DISTINCT COALESCE(p.name, j.name) ORDER BY COALESCE(p.name, j.name)) as task_list,
            ARRAY_AGG(DISTINCT cfv.value ORDER BY cfv.value) FILTER (WHERE cfv.value IS NOT NULL) as custom_field_values
        FROM users u
        LEFT JOIN timesheets t ON u.id = t.user_id 
            AND t.date >= v_start_date 
            AND t.date <= v_end_date
        LEFT JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        LEFT JOIN timesheet_customfield_values cfv ON t.id = cfv.timesheet_id
        WHERE u.id = p_user_id
        GROUP BY u.id, u.username, u.display_name, u.first_name, u.last_name
    ),
    breakdown_data AS (
        SELECT 
            CASE 
                WHEN p_period_type = 'weekly' THEN DATE_TRUNC('week', t.date)::DATE
                ELSE t.date
            END as breakdown_date,
            j.name as breakdown_client,
            COALESCE(p.name, j.name) as breakdown_task,
            SUM(t.duration) / 3600.0 as breakdown_hours,
            j.short_code as breakdown_job_code,
            ARRAY_AGG(DISTINCT cfv.value ORDER BY cfv.value) FILTER (WHERE cfv.value IS NOT NULL) as breakdown_custom_fields
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        LEFT JOIN timesheet_customfield_values cfv ON t.id = cfv.timesheet_id
        WHERE t.user_id = p_user_id
            AND t.date >= v_start_date 
            AND t.date <= v_end_date
        GROUP BY 
            CASE 
                WHEN p_period_type = 'weekly' THEN DATE_TRUNC('week', t.date)::DATE
                ELSE t.date
            END,
            j.name, p.name, j.short_code
    )
    SELECT 
        es.employee_id,
        es.employee_name,
        es.full_name,
        es.work_start_date,
        es.work_end_date,
        es.total_work_hours,
        es.actual_work_days,
        es.average_daily_hours,
        es.client_list,
        es.task_list,
        es.custom_field_values,
        bd.breakdown_date,
        bd.breakdown_client,
        bd.breakdown_task,
        bd.breakdown_hours,
        bd.breakdown_job_code,
        bd.breakdown_custom_fields
    FROM employee_summary es
    CROSS JOIN breakdown_data bd
    ORDER BY bd.breakdown_date DESC, bd.breakdown_client, bd.breakdown_task;
END;
$$;


ALTER FUNCTION "public"."get_employee_complete_analytics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_period_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_daily_work_data"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("work_date" "date", "client_name" "text", "task_name" "text", "hours_worked" numeric, "job_code" "text", "custom_field_items" "text"[])
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    RETURN QUERY
    WITH daily_work_data AS (
        SELECT 
            t.date as work_date,
            j.name as client_name,
            COALESCE(p.name, j.name) as task_name,
            t.duration / 3600.0 as hours_worked,
            j.short_code as job_code,
            t.id as timesheet_id
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        WHERE t.user_id = p_user_id
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
    ),
    daily_custom_fields AS (
        SELECT 
            t.date as work_date,
            j.name as client_name,
            COALESCE(p.name, j.name) as task_name,
            ARRAY_AGG(DISTINCT cfv.value ORDER BY cfv.value) as custom_field_items
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        JOIN timesheet_customfield_values cfv ON t.id = cfv.timesheet_id
        JOIN custom_fields cf ON cfv.customfield_id = cf.id
        WHERE t.user_id = p_user_id
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
            AND cfv.value IS NOT NULL
        GROUP BY t.date, j.name, p.name
    )
    SELECT 
        dwd.work_date,
        dwd.client_name,
        dwd.task_name,
        dwd.hours_worked,
        dwd.job_code,
        COALESCE(dcf.custom_field_items, ARRAY[]::TEXT[]) as custom_field_items
    FROM daily_work_data dwd
    LEFT JOIN daily_custom_fields dcf ON dwd.work_date = dcf.work_date 
        AND dwd.client_name = dcf.client_name 
        AND dwd.task_name = dcf.task_name
    ORDER BY dwd.work_date DESC, dwd.client_name, dwd.task_name;
END;
$$;


ALTER FUNCTION "public"."get_employee_daily_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_detailed_data"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("work_date" "date", "client_name" "text", "task_name" "text", "hours_worked" numeric, "job_code" "text", "billable" boolean)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date as work_date,
        COALESCE(j.name, 'Unknown') as client_name,
        COALESCE(p.name, j.name, 'Unknown') as task_name,
        ROUND((t.duration / 3600.0), 2) as hours_worked,
        COALESCE(j.short_code, '') as job_code,
        COALESCE(j.billable, true) as billable
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    ORDER BY t.date DESC;
END;
$$;


ALTER FUNCTION "public"."get_employee_detailed_data"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_detailed_performance"("employee_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("date" "date", "total_hours" numeric, "billable_hours" numeric, "project_name" "text", "jobcode_name" "text", "notes" "text", "location" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date,
        t.duration / 3600.0 as total_hours,
        CASE WHEN j.billable = true THEN t.duration / 3600.0 ELSE 0 END as billable_hours,
        p.name as project_name,
        j.name as jobcode_name,
        t.notes,
        t.location
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE t.user_id = employee_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    ORDER BY t.date DESC, t.start;
END;
$$;


ALTER FUNCTION "public"."get_employee_detailed_performance"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_kpis_comprehensive"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("total_employees" bigint, "avg_daily_hours_per_employee" numeric, "avg_utilization" numeric, "team_productivity" numeric, "overtime_percentage" numeric, "total_hours_all_employees" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total_employees BIGINT;
    v_avg_daily_hours NUMERIC;
    v_avg_utilization NUMERIC;
    v_team_productivity NUMERIC;
    v_overtime_pct NUMERIC;
    v_total_hours NUMERIC;
    v_daily_averages NUMERIC[];
    v_utilizations NUMERIC[];
    v_efficiency_scores NUMERIC[];
    v_variance NUMERIC;
    v_consistency_score NUMERIC;
    v_overtime_hours NUMERIC;
BEGIN
    -- Get basic counts and totals
    SELECT 
        COUNT(*),
        COALESCE(AVG(average_daily_hours), 0),
        COALESCE(SUM(total_work_hours), 0),
        COALESCE(SUM(overtime_hours), 0)
    INTO 
        v_total_employees,
        v_avg_daily_hours,
        v_total_hours,
        v_overtime_hours
    FROM get_comprehensive_employee_analytics(start_date_param, end_date_param);
    
    -- Calculate utilization (average of individual utilizations)
    SELECT ARRAY_AGG(utilization_percentage)
    INTO v_utilizations
    FROM get_comprehensive_employee_analytics(start_date_param, end_date_param)
    WHERE utilization_percentage > 0;
    
    IF v_utilizations IS NOT NULL AND array_length(v_utilizations, 1) > 0 THEN
        v_avg_utilization := (SELECT AVG(util) FROM unnest(v_utilizations) AS util);
    ELSE
        v_avg_utilization := 0;
    END IF;
    
    -- Calculate team productivity (efficiency + consistency)
    SELECT ARRAY_AGG(average_daily_hours)
    INTO v_daily_averages
    FROM get_comprehensive_employee_analytics(start_date_param, end_date_param)
    WHERE average_daily_hours > 0;
    
    IF v_daily_averages IS NOT NULL AND array_length(v_daily_averages, 1) > 0 THEN
        -- Efficiency scores
        SELECT ARRAY_AGG(LEAST(100.0, (avg_hours / 8.0) * 100))
        INTO v_efficiency_scores
        FROM unnest(v_daily_averages) AS avg_hours;
        
        -- Calculate variance for consistency
        IF array_length(v_daily_averages, 1) > 1 THEN
            v_variance := (
                SELECT AVG((avg_hours - (SELECT AVG(avg_hours) FROM unnest(v_daily_averages) AS avg_hours))^2)
                FROM unnest(v_daily_averages) AS avg_hours
            );
            v_consistency_score := GREATEST(0, 100 - (v_variance * 10));
        ELSE
            v_consistency_score := 100;
        END IF;
        
        -- Weighted productivity score
        v_team_productivity := (
            (SELECT AVG(score) FROM unnest(v_efficiency_scores) AS score) * 0.7 + 
            v_consistency_score * 0.3
        );
        v_team_productivity := LEAST(v_team_productivity, 100.0);
    ELSE
        v_team_productivity := 0;
    END IF;
    
    -- Calculate overtime percentage
    v_overtime_pct := CASE 
        WHEN v_total_hours > 0 THEN (v_overtime_hours / v_total_hours) * 100
        ELSE 0
    END;
    
    RETURN QUERY SELECT 
        v_total_employees,
        ROUND(v_avg_daily_hours, 2),
        ROUND(v_avg_utilization, 2),
        ROUND(v_team_productivity, 2),
        ROUND(v_overtime_pct, 2),
        ROUND(v_total_hours, 2);
END;
$$;


ALTER FUNCTION "public"."get_employee_kpis_comprehensive"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_performance_rating"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_daily_average NUMERIC;
    v_performance_rating TEXT;
BEGIN
    SELECT 
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date))
            ELSE 0
        END
    INTO v_daily_average
    FROM timesheets t
    WHERE t.user_id = p_user_id
        AND (t.date >= p_start_date OR p_start_date IS NULL)
        AND (t.date <= p_end_date OR p_end_date IS NULL);
    
    IF v_daily_average >= 8.0 THEN
        v_performance_rating := 'Excellent';
    ELSIF v_daily_average >= 6.0 THEN
        v_performance_rating := 'Good';
    ELSIF v_daily_average >= 4.0 THEN
        v_performance_rating := 'Average';
    ELSE
        v_performance_rating := 'Needs Improvement';
    END IF;
    
    RETURN v_performance_rating;
END;
$$;


ALTER FUNCTION "public"."get_employee_performance_rating"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_productivity_metrics"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "total_hours" numeric, "days_worked" bigint, "daily_average" numeric, "productivity_score" numeric, "utilization_percentage" numeric, "overtime_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
    v_total_hours NUMERIC;
    v_days_worked BIGINT;
    v_daily_average NUMERIC;
    v_productivity_score NUMERIC;
    v_utilization_percentage NUMERIC;
    v_overtime_hours NUMERIC;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    -- Get basic metrics
    SELECT 
        COALESCE(SUM(t.duration) / 3600.0, 0),
        COUNT(DISTINCT t.date),
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date))
            ELSE 0
        END
    INTO v_total_hours, v_days_worked, v_daily_average
    FROM timesheets t
    WHERE t.user_id = p_user_id
        AND t.date >= v_start_date 
        AND t.date <= v_end_date;
    
    -- Calculate productivity score (0-100)
    v_productivity_score := LEAST(100, (v_daily_average / 8.0) * 100);
    
    -- Calculate utilization percentage
    v_utilization_percentage := (v_daily_average / 8.0) * 100;
    
    -- Calculate overtime hours
    v_overtime_hours := GREATEST(0, v_daily_average - 8.0) * v_days_worked;
    
    RETURN QUERY
    SELECT 
        u.id as employee_id,
        u.username as employee_name,
        v_total_hours,
        v_days_worked,
        v_daily_average,
        v_productivity_score,
        v_utilization_percentage,
        v_overtime_hours
    FROM users u
    WHERE u.id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."get_employee_productivity_metrics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_summary_data"("p_user_id" bigint DEFAULT NULL::bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "full_name" "text", "work_start_date" "date", "work_end_date" "date", "total_work_hours" numeric, "actual_work_days" bigint, "average_daily_hours" numeric, "client_list" "text"[], "task_list" "text"[], "custom_field_values" "text"[])
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date 
        FROM timesheets t 
        WHERE t.user_id = COALESCE(p_user_id, t.user_id);
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date 
        FROM timesheets t 
        WHERE t.user_id = COALESCE(p_user_id, t.user_id);
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    RETURN QUERY
    WITH employee_summary AS (
        SELECT 
            u.id as employee_id,
            u.username as employee_name,
            COALESCE(u.display_name, CONCAT(u.first_name, ' ', u.last_name)) as full_name,
            v_start_date as work_start_date,
            v_end_date as work_end_date,
            COALESCE(SUM(t.duration) / 3600.0, 0)::NUMERIC as total_work_hours,
            COUNT(DISTINCT t.date)::BIGINT as actual_work_days,
            CASE 
                WHEN COUNT(DISTINCT t.date) > 0 THEN 
                    (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date))::NUMERIC
                ELSE 0::NUMERIC
            END as average_daily_hours
        FROM users u
        LEFT JOIN timesheets t ON u.id = t.user_id 
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
        WHERE u.id = COALESCE(p_user_id, u.id)
        GROUP BY u.id, u.username, u.display_name, u.first_name, u.last_name
    ),
    employee_clients AS (
        SELECT 
            t.user_id,
            ARRAY_AGG(DISTINCT j.name ORDER BY j.name) as clients
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        WHERE t.user_id = COALESCE(p_user_id, t.user_id)
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
        GROUP BY t.user_id
    ),
    employee_tasks AS (
        SELECT 
            t.user_id,
            ARRAY_AGG(DISTINCT COALESCE(p.name, j.name) ORDER BY COALESCE(p.name, j.name)) as tasks
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        WHERE t.user_id = COALESCE(p_user_id, t.user_id)
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
        GROUP BY t.user_id
    ),
    employee_custom_fields AS (
        SELECT 
            t.user_id,
            ARRAY_AGG(DISTINCT cfv.value ORDER BY cfv.value) as custom_fields
        FROM timesheets t
        JOIN timesheet_customfield_values cfv ON t.id = cfv.timesheet_id
        JOIN custom_fields cf ON cfv.customfield_id = cf.id
        WHERE t.user_id = COALESCE(p_user_id, t.user_id)
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
            AND cfv.value IS NOT NULL
        GROUP BY t.user_id
    )
    SELECT 
        es.employee_id,
        es.employee_name,
        es.full_name,
        es.work_start_date,
        es.work_end_date,
        es.total_work_hours,
        es.actual_work_days,
        es.average_daily_hours,
        COALESCE(ec.clients, ARRAY[]::TEXT[]) as client_list,
        COALESCE(et.tasks, ARRAY[]::TEXT[]) as task_list,
        COALESCE(ecf.custom_fields, ARRAY[]::TEXT[]) as custom_field_values
    FROM employee_summary es
    LEFT JOIN employee_clients ec ON es.employee_id = ec.user_id
    LEFT JOIN employee_tasks et ON es.employee_id = et.user_id
    LEFT JOIN employee_custom_fields ecf ON es.employee_id = ecf.user_id
    ORDER BY es.total_work_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_employee_summary_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_time_tracking"("employee_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("date" "date", "start_time" "text", "end_time" "text", "duration_hours" numeric, "jobcode_name" "text", "project_name" "text", "billable" boolean, "notes" "text", "location" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date,
        t.start,
        t.end,
        t.duration / 3600.0 as duration_hours,
        j.name as jobcode_name,
        p.name as project_name,
        j.billable,
        t.notes,
        t.location
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE t.user_id = employee_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    ORDER BY t.date DESC, t.start;
END;
$$;


ALTER FUNCTION "public"."get_employee_time_tracking"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_employee_weekly_work_data"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("work_week" "date", "client_name" "text", "task_name" "text", "hours_worked" numeric, "job_code" "text", "custom_field_items" "text"[])
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    -- Set default date range if not provided
    IF p_start_date IS NULL THEN
        SELECT MIN(t.date) INTO v_start_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_start_date := p_start_date;
    END IF;
    
    IF p_end_date IS NULL THEN
        SELECT MAX(t.date) INTO v_end_date FROM timesheets t WHERE t.user_id = p_user_id;
    ELSE
        v_end_date := p_end_date;
    END IF;
    
    RETURN QUERY
    WITH weekly_work_data AS (
        SELECT 
            DATE_TRUNC('week', t.date)::DATE as work_week,
            j.name as client_name,
            COALESCE(p.name, j.name) as task_name,
            SUM(t.duration) / 3600.0 as hours_worked,
            j.short_code as job_code
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        WHERE t.user_id = p_user_id
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
        GROUP BY DATE_TRUNC('week', t.date), j.name, p.name, j.short_code
    ),
    weekly_custom_fields AS (
        SELECT 
            DATE_TRUNC('week', t.date)::DATE as work_week,
            j.name as client_name,
            COALESCE(p.name, j.name) as task_name,
            ARRAY_AGG(DISTINCT cfv.value ORDER BY cfv.value) as custom_field_items
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        JOIN timesheet_customfield_values cfv ON t.id = cfv.timesheet_id
        JOIN custom_fields cf ON cfv.customfield_id = cf.id
        WHERE t.user_id = p_user_id
            AND (t.date >= v_start_date OR v_start_date IS NULL)
            AND (t.date <= v_end_date OR v_end_date IS NULL)
            AND cfv.value IS NOT NULL
        GROUP BY DATE_TRUNC('week', t.date), j.name, p.name
    )
    SELECT 
        wwd.work_week,
        wwd.client_name,
        wwd.task_name,
        wwd.hours_worked,
        wwd.job_code,
        COALESCE(wcf.custom_field_items, ARRAY[]::TEXT[]) as custom_field_items
    FROM weekly_work_data wwd
    LEFT JOIN weekly_custom_fields wcf ON wwd.work_week = wcf.work_week 
        AND wwd.client_name = wcf.client_name 
        AND wwd.task_name = wcf.task_name
    ORDER BY wwd.work_week DESC, wwd.client_name, wwd.task_name;
END;
$$;


ALTER FUNCTION "public"."get_employee_weekly_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_financial_metrics"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("total_revenue" numeric, "total_cost" numeric, "profit_margin" numeric, "avg_hourly_rate" numeric, "total_billable_hours" numeric, "total_non_billable_hours" numeric, "cost_per_employee" numeric, "revenue_per_project" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END), 0) as total_revenue,
        COALESCE(SUM(t.duration / 3600.0 * 50), 0) as total_cost,
        CASE 
            WHEN SUM(t.duration / 3600.0 * 50) > 0 THEN
                (SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END) - 
                 SUM(t.duration / 3600.0 * 50)) / 
                SUM(t.duration / 3600.0 * 50) * 100
            ELSE 0
        END as profit_margin,
        CASE 
            WHEN SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 ELSE 0 END) > 0 THEN
                SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END) / 
                SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 ELSE 0 END)
            ELSE 0
        END as avg_hourly_rate,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 ELSE 0 END), 0) as total_billable_hours,
        COALESCE(SUM(CASE WHEN j.billable = false THEN t.duration / 3600.0 ELSE 0 END), 0) as total_non_billable_hours,
        CASE 
            WHEN COUNT(DISTINCT t.user_id) > 0 THEN
                SUM(t.duration / 3600.0 * 50) / COUNT(DISTINCT t.user_id)
            ELSE 0
        END as cost_per_employee,
        CASE 
            WHEN COUNT(DISTINCT j.id) > 0 THEN
                SUM(CASE WHEN j.billable = true THEN t.duration / 3600.0 * 50 ELSE 0 END) / COUNT(DISTINCT j.id)
            ELSE 0
        END as revenue_per_project
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param);
END;
$$;


ALTER FUNCTION "public"."get_financial_metrics"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_client_distribution"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("client_name" "text", "total_hours" numeric, "billable_hours" numeric, "days_worked" bigint, "average_hours_per_day" numeric, "percentage_of_total" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total_hours NUMERIC;
BEGIN
    -- Get total hours for this employee
    SELECT COALESCE(SUM(t.duration) / 3600.0, 0) INTO v_total_hours
    FROM timesheets t
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param);
    
    RETURN QUERY
    SELECT 
        j.name as client_name,
        ROUND(COALESCE(SUM(t.duration) / 3600.0, 0), 2) as total_hours,
        ROUND(COALESCE(SUM(CASE WHEN j.billable THEN t.duration ELSE 0 END) / 3600.0, 0), 2) as billable_hours,
        COUNT(DISTINCT t.date) as days_worked,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                ROUND(COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date), 2)
            ELSE 0
        END as average_hours_per_day,
        CASE 
            WHEN v_total_hours > 0 THEN 
                ROUND((COALESCE(SUM(t.duration) / 3600.0, 0) / v_total_hours * 100), 2)
            ELSE 0
        END as percentage_of_total
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY j.name, j.billable
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_individual_client_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_daily_work_summary"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("work_date" "date", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "unique_clients" bigint, "unique_tasks" bigint, "avg_hours_per_entry" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date as work_date,
        ROUND(COALESCE(SUM(t.duration) / 3600.0, 0), 2) as total_hours,
        ROUND(COALESCE(SUM(CASE WHEN j.billable THEN t.duration ELSE 0 END) / 3600.0, 0), 2) as billable_hours,
        COUNT(t.id) as total_entries,
        COUNT(DISTINCT j.id) as unique_clients,
        COUNT(DISTINCT COALESCE(p.id, j.id)) as unique_tasks,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                ROUND(COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id), 2)
            ELSE 0
        END as avg_hours_per_entry
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY t.date
    ORDER BY t.date DESC;
END;
$$;


ALTER FUNCTION "public"."get_individual_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_employee_summary"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "full_name" "text", "work_start_date" "date", "work_end_date" "date", "total_work_hours" numeric, "actual_work_days" bigint, "average_daily_hours" numeric, "client_list" "text"[], "task_list" "text"[], "utilization_percentage" numeric, "productivity_score" numeric, "performance_rating" "text", "total_entries" bigint, "billable_hours" numeric, "overtime_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM get_comprehensive_employee_analytics(start_date_param, end_date_param)
    WHERE employee_id = user_id_param;
END;
$$;


ALTER FUNCTION "public"."get_individual_employee_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_productivity_metrics"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "total_hours" numeric, "days_worked" bigint, "daily_average" numeric, "productivity_score" numeric, "utilization_percentage" numeric, "overtime_hours" numeric, "performance_rating" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        emp.employee_id,
        emp.employee_name,
        emp.total_work_hours as total_hours,
        emp.actual_work_days as days_worked,
        emp.average_daily_hours as daily_average,
        emp.productivity_score,
        emp.utilization_percentage,
        emp.overtime_hours,
        emp.performance_rating
    FROM get_comprehensive_employee_analytics(start_date_param, end_date_param) emp
    WHERE emp.employee_id = user_id_param;
END;
$$;


ALTER FUNCTION "public"."get_individual_productivity_metrics"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_task_distribution"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("task_name" "text", "total_hours" numeric, "billable_hours" numeric, "days_worked" bigint, "average_hours_per_day" numeric, "percentage_of_total" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_total_hours NUMERIC;
BEGIN
    -- Get total hours for this employee
    SELECT COALESCE(SUM(t.duration) / 3600.0, 0) INTO v_total_hours
    FROM timesheets t
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param);
    
    RETURN QUERY
    SELECT 
        COALESCE(p.name, j.name, 'General Work') as task_name,
        ROUND(COALESCE(SUM(t.duration) / 3600.0, 0), 2) as total_hours,
        ROUND(COALESCE(SUM(CASE WHEN j.billable THEN t.duration ELSE 0 END) / 3600.0, 0), 2) as billable_hours,
        COUNT(DISTINCT t.date) as days_worked,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                ROUND(COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date), 2)
            ELSE 0
        END as average_hours_per_day,
        CASE 
            WHEN v_total_hours > 0 THEN 
                ROUND((COALESCE(SUM(t.duration) / 3600.0, 0) / v_total_hours * 100), 2)
            ELSE 0
        END as percentage_of_total
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE t.user_id = user_id_param
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY p.name, j.name, j.billable
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_individual_task_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_individual_weekly_work_summary"("user_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("work_week" "date", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "unique_clients" bigint, "unique_tasks" bigint, "days_worked" bigint, "avg_hours_per_day" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH daily_data AS (
        SELECT 
            t.date,
            t.duration,
            j.billable,
            j.id as jobcode_id,
            p.id as project_id
        FROM timesheets t
        JOIN jobcodes j ON t.jobcode_id = j.id
        LEFT JOIN projects p ON j.id = p.jobcode_id
        WHERE t.user_id = user_id_param
            AND (start_date_param IS NULL OR t.date >= start_date_param)
            AND (end_date_param IS NULL OR t.date <= end_date_param)
    ),
    weekly_data AS (
        SELECT 
            (date - INTERVAL '1 day' * EXTRACT(DOW FROM date))::DATE as work_week,
            SUM(duration) as total_duration,
            SUM(CASE WHEN billable THEN duration ELSE 0 END) as billable_duration,
            COUNT(*) as total_entries,
            COUNT(DISTINCT jobcode_id) as unique_clients,
            COUNT(DISTINCT COALESCE(project_id, jobcode_id)) as unique_tasks,
            COUNT(DISTINCT date) as days_worked
        FROM daily_data
        GROUP BY (date - INTERVAL '1 day' * EXTRACT(DOW FROM date))::DATE
    )
    SELECT 
        wd.work_week,
        ROUND(COALESCE(wd.total_duration / 3600.0, 0), 2) as total_hours,
        ROUND(COALESCE(wd.billable_duration / 3600.0, 0), 2) as billable_hours,
        wd.total_entries,
        wd.unique_clients,
        wd.unique_tasks,
        wd.days_worked,
        CASE 
            WHEN wd.days_worked > 0 THEN 
                ROUND(COALESCE(wd.total_duration / 3600.0, 0) / wd.days_worked, 2)
            ELSE 0
        END as avg_hours_per_day
    FROM weekly_data wd
    ORDER BY wd.work_week DESC;
END;
$$;


ALTER FUNCTION "public"."get_individual_weekly_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_jobcode_daily_summary"("jobcode_id_input" bigint) RETURNS TABLE("jobcode_id" bigint, "jobcode_name" "text", "user_id" bigint, "username" "text", "work_date" "date", "work_hours" numeric, "user_start_date" "date", "user_end_date" "date")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.jobcode_id,
        j.name AS jobcode_name,
        t.user_id,
        u.username,
        DATE(NULLIF(t.start, '')::timestamptz) AS work_date,
        ROUND(SUM(t.duration) / 3600.0, 2) AS work_hours,
        MIN(NULLIF(t.start, '')::timestamptz)::date AS user_start_date,
        MAX(NULLIF(t."end", '')::timestamptz)::date AS user_end_date
    FROM timesheets t
    JOIN users u ON u.id = t.user_id
    JOIN jobcodes j ON j.id = t.jobcode_id
    WHERE t.jobcode_id = jobcode_id_input
      AND t.duration IS NOT NULL
    GROUP BY t.jobcode_id, j.name, t.user_id, u.username, work_date
    ORDER BY work_date, username;
END;
$$;


ALTER FUNCTION "public"."get_jobcode_daily_summary"("jobcode_id_input" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_jobcode_summary"() RETURNS TABLE("jobcode_id" bigint, "jobcode_name" "text", "jobcode_start" "date", "jobcode_end" "date", "list_users" "text"[])
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.jobcode_id,
        j.name AS jobcode_name,
        MIN(NULLIF(t.start, '')::timestamptz)::date AS jobcode_start,
        MAX(NULLIF(t."end", '')::timestamptz)::date AS jobcode_end,
        ARRAY_AGG(DISTINCT u.username) AS list_users
    FROM timesheets t
    JOIN users u ON u.id = t.user_id
    JOIN jobcodes j ON j.id = t.jobcode_id
    WHERE t.duration IS NOT NULL
    GROUP BY t.jobcode_id, j.name
    ORDER BY jobcode_start;
END;
$$;


ALTER FUNCTION "public"."get_jobcode_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_analytics"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("project_id" bigint, "project_name" "text", "jobcode_name" "text", "status" "text", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "unique_employees" bigint, "avg_hours_per_employee" numeric, "completion_percentage" numeric, "budget_status" "text", "start_date" "text", "due_date" "text", "completed_date" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        j.id as project_id,
        j.name as project_name,
        j.name as jobcode_name,
        CASE 
            WHEN j.active = true THEN 'in_progress'
            ELSE 'completed'
        END as status,
        COALESCE(SUM(t.duration) / 3600.0, 0)::NUMERIC as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0)::NUMERIC as billable_hours,
        COUNT(t.id) as total_entries,
        COUNT(DISTINCT t.user_id) as unique_employees,
        CASE 
            WHEN COUNT(DISTINCT t.user_id) > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.user_id))::NUMERIC
            ELSE 0::NUMERIC
        END as avg_hours_per_employee,
        CASE 
            WHEN ab.time_estimate > 0 THEN 
                LEAST(
                    (COALESCE(SUM(t.duration) / 3600.0, 0) / ab.time_estimate * 100)::NUMERIC,
                    100::NUMERIC
                )
            ELSE 0::NUMERIC
        END as completion_percentage,
        CASE 
            WHEN ab.cost_estimate > 0 AND COALESCE(SUM(t.duration) / 3600.0, 0) * 50 > ab.cost_estimate THEN 'over_budget'
            WHEN ab.cost_estimate > 0 AND COALESCE(SUM(t.duration) / 3600.0, 0) * 50 < ab.cost_estimate * 0.8 THEN 'under_budget'
            ELSE 'on_budget'
        END as budget_status,
        NULL::TEXT as start_date,
        NULL::TEXT as due_date,
        NULL::TEXT as completed_date
    FROM jobcodes j
    LEFT JOIN timesheets t ON j.id = t.jobcode_id
    LEFT JOIN accubid_breakdowns ab ON j.name = ab.job_name
    WHERE j.active = true
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY j.id, j.name, j.active, ab.time_estimate, ab.cost_estimate
    HAVING COUNT(t.id) > 0
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_project_analytics"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_list"() RETURNS TABLE("project_name" "text")
    LANGUAGE "sql"
    AS $$
    select distinct p.name as project_name
    from public.projects p
    where p.active = true
    order by p.name;
$$;


ALTER FUNCTION "public"."get_project_list"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_summary"() RETURNS TABLE("project_id" bigint, "project_name" "text", "project_start" "date", "project_end" "date", "list_users" "text"[])
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.jobcode_id AS project_id,
        p.name AS project_name,
        MIN(NULLIF(t.start, '')::timestamptz)::date AS project_start,
        MAX(NULLIF(t."end", '')::timestamptz)::date AS project_end,
        ARRAY_AGG(DISTINCT u.username) AS list_users
    FROM timesheets t
    JOIN users u ON u.id = t.user_id
    JOIN projects p ON p.jobcode_id = t.jobcode_id
    WHERE t.duration IS NOT NULL
    GROUP BY t.jobcode_id, p.name
    ORDER BY project_start;
END;
$$;


ALTER FUNCTION "public"."get_project_summary"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_team_allocation"("project_id_param" bigint, "start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("employee_id" bigint, "employee_name" "text", "total_hours" numeric, "billable_hours" numeric, "efficiency_score" numeric, "last_activity" "date")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id as employee_id,
        COALESCE(u.display_name, CONCAT(u.first_name, ' ', u.last_name)) as employee_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0) as billable_hours,
        -- Efficiency score based on hours logged vs expected
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                LEAST(COALESCE(SUM(t.duration) / 3600.0, 0) / 40.0 * (COUNT(DISTINCT t.date) / 20.0), 10.0)
            ELSE 0
        END as efficiency_score,
        MAX(t.date) as last_activity
    FROM users u
    JOIN timesheets t ON u.id = t.user_id
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE j.id = project_id_param
        AND u.active = true
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY u.id, u.display_name, u.first_name, u.last_name
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_project_team_allocation"("project_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_project_timsheet_summary_v1"("limit_count" integer DEFAULT 1000, "offset_count" integer DEFAULT 0) RETURNS TABLE("name" "text", "jobcode_id" bigint, "total_duration" numeric, "start_date" "text", "end_date" "text", "days_worked" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$BEGIN
    RETURN QUERY
   SELECT 
    u.name,
    t.jobcode_id, 
    ROUND(SUM(t.duration) / 3600.0, 2) AS total_duration,

    -- prefer MIN(start); if that's null/empty, use MIN(end)
    COALESCE(
      MIN(NULLIF(t.start, '')),
      MIN(NULLIF(t."end", ''))
    ) AS start_date,

    -- prefer MAX(end); if that's null/empty, use MAX(start)
    COALESCE(
      MAX(NULLIF(t."end", '')),
      MAX(NULLIF(t.start, ''))
    ) AS end_date,

    -- count distinct days using start if available else end
    COUNT(
      DISTINCT DATE(
        COALESCE(
          NULLIF(t.start, ''),
          NULLIF(t."end", '')
        )::timestamptz
      )
    ) AS days_worked

FROM timesheets AS t
LEFT JOIN jobcodes AS u ON u.id = t.jobcode_id
GROUP BY t.jobcode_id, u.name


    LIMIT limit_count OFFSET offset_count;
END;$$;


ALTER FUNCTION "public"."get_project_timsheet_summary_v1"("limit_count" integer, "offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_task_analytics"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("task_id" bigint, "jobcode_name" "text", "project_name" "text", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "unique_employees" bigint, "avg_duration_per_entry" numeric, "total_cost" numeric, "efficiency_rating" "text")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        j.id as task_id,
        j.name as jobcode_name,
        p.name as project_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0) as billable_hours,
        COUNT(t.id) as total_entries,
        COUNT(DISTINCT t.user_id) as unique_employees,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                AVG(t.duration) / 3600.0
            ELSE 0
        END as avg_duration_per_entry,
        COALESCE(SUM(t.duration) / 3600.0 * 50, 0) as total_cost,
        CASE 
            WHEN AVG(t.duration) / 3600.0 < 2 THEN 'high_efficiency'
            WHEN AVG(t.duration) / 360.0 < 4 THEN 'medium_efficiency'
            ELSE 'low_efficiency'
        END as efficiency_rating
    FROM jobcodes j
    LEFT JOIN timesheets t ON j.id = t.jobcode_id
    LEFT JOIN projects p ON j.id = p.jobcode_id
    WHERE j.active = true
        AND (start_date_param IS NULL OR t.date >= start_date_param)
        AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY j.id, j.name, p.name
    HAVING COUNT(t.id) > 0
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_task_analytics"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_task_duration_summary"("p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0, "p_jobcode_id" integer DEFAULT NULL::integer, "p_user_id" integer DEFAULT NULL::integer) RETURNS TABLE("duration_hours" numeric, "value" "text", "time_estimate" numeric)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    select 
        (sum(t.duration) / 3600.0)::numeric as duration_hours,  -- seconds → hours
        tcv.value,
        ab.time_estimate::numeric
    from timesheets t
    left join timesheet_customfield_values tcv
        on tcv.timesheet_id = t.id
    left join accubid_breakdowns ab
        on ab."Task_name" = tcv.value
    where tcv.value != ''
      and (p_jobcode_id is null or t.jobcode_id = p_jobcode_id)
      and (p_user_id is null or t.user_id = p_user_id)
    group by tcv.value, ab.time_estimate
    order by duration_hours desc
    limit p_limit offset p_offset;
end;
$$;


ALTER FUNCTION "public"."get_task_duration_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" integer, "p_user_id" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_client_activity"("start_date" "date", "end_date" "date") RETURNS TABLE("client_name" "text", "total_hours" numeric, "users_assigned" bigint, "sessions" bigint, "avg_session_hours" numeric, "working_days" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        j.name as client_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.user_id) as users_assigned,
        COUNT(t.id) as sessions,
        CASE 
            WHEN COUNT(t.id) > 0 THEN
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_hours,
        COUNT(DISTINCT t.date) as working_days
    FROM jobcodes j
    LEFT JOIN timesheets t ON j.id = t.jobcode_id AND t.date >= start_date AND t.date <= end_date
    WHERE j.active = true
    GROUP BY j.id, j.name
    HAVING COALESCE(SUM(t.duration), 0) > 0
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_time_client_activity"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_daily_distribution"("start_date" "date", "end_date" "date") RETURNS TABLE("work_date" "date", "total_hours" numeric, "users_active" bigint, "clients_active" bigint, "sessions" bigint, "longest_session_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date as work_date,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.user_id) as users_active,
        COUNT(DISTINCT t.jobcode_id) as clients_active,
        COUNT(t.id) as sessions,
        COALESCE(MAX(t.duration) / 3600.0, 0) as longest_session_hours
    FROM timesheets t
    WHERE t.date >= start_date AND t.date <= end_date
    GROUP BY t.date
    ORDER BY t.date;
END;
$$;


ALTER FUNCTION "public"."get_time_daily_distribution"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_period_overview"("start_date" "date", "end_date" "date") RETURNS TABLE("total_hours" numeric, "total_users" bigint, "total_clients" bigint, "total_sessions" bigint, "working_days" bigint, "avg_daily_hours" numeric, "avg_session_length" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.user_id) as total_users,
        COUNT(DISTINCT t.jobcode_id) as total_clients,
        COUNT(t.id) as total_sessions,
        COUNT(DISTINCT t.date) as working_days,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date)
            ELSE 0
        END as avg_daily_hours,
        CASE 
            WHEN COUNT(t.id) > 0 THEN
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_length
    FROM timesheets t
    WHERE t.date >= start_date AND t.date <= end_date;
END;
$$;


ALTER FUNCTION "public"."get_time_period_overview"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_session_analysis"("start_date" "date", "end_date" "date") RETURNS TABLE("session_type" "text", "count" bigint, "total_hours" numeric, "percentage" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH session_categories AS (
        SELECT 
            CASE 
                WHEN t.duration < 7200 THEN 'Short Sessions (< 2 hours)'
                WHEN t.duration < 14400 THEN 'Medium Sessions (2-4 hours)'
                ELSE 'Long Sessions (4+ hours)'
            END as session_type,
            t.duration / 3600.0 as hours
        FROM timesheets t
        WHERE t.date >= start_date AND t.date <= end_date
    ),
    totals AS (
        SELECT 
            COUNT(*) as total_count,
            SUM(hours) as total_hours
        FROM session_categories
    )
    SELECT 
        sc.session_type,
        COUNT(*) as count,
        SUM(sc.hours) as total_hours,
        CASE 
            WHEN t.total_count > 0 THEN
                (COUNT(*) * 100.0 / t.total_count)
            ELSE 0
        END as percentage
    FROM session_categories sc
    CROSS JOIN totals t
    GROUP BY sc.session_type, t.total_count
    ORDER BY sc.session_type;
END;
$$;


ALTER FUNCTION "public"."get_time_session_analysis"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_tracking_summary"("start_date_param" "date" DEFAULT NULL::"date", "end_date_param" "date" DEFAULT NULL::"date") RETURNS TABLE("date" "date", "total_hours" numeric, "billable_hours" numeric, "total_entries" bigint, "unique_employees" bigint, "avg_hours_per_employee" numeric, "total_cost" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date,
        COALESCE(SUM(t.duration) / 3600.0, 0)::NUMERIC as total_hours,
        COALESCE(SUM(CASE WHEN j.billable = true THEN t.duration ELSE 0 END) / 3600.0, 0)::NUMERIC as billable_hours,
        COUNT(t.id) as total_entries,
        COUNT(DISTINCT t.user_id) as unique_employees,
        CASE 
            WHEN COUNT(DISTINCT t.user_id) > 0 THEN 
                (COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.user_id))::NUMERIC
            ELSE 0::NUMERIC
        END as avg_hours_per_employee,
        COALESCE(SUM(t.duration) / 3600.0 * 50, 0)::NUMERIC as total_cost
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE (start_date_param IS NULL OR t.date >= start_date_param)
      AND (end_date_param IS NULL OR t.date <= end_date_param)
    GROUP BY t.date
    ORDER BY t.date DESC;
END;
$$;


ALTER FUNCTION "public"."get_time_tracking_summary"("start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_user_performance"("start_date" "date", "end_date" "date") RETURNS TABLE("user_name" "text", "total_hours" numeric, "working_days" bigint, "avg_hours_per_day" numeric, "clients_served" bigint, "sessions" bigint)
    LANGUAGE "plpgsql"
    AS $$BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(u.username, CONCAT(u.first_name, ' ', u.last_name)) as user_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.date) as working_days,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date)
            ELSE 0
        END as avg_hours_per_day,
        COUNT(DISTINCT t.jobcode_id) as clients_served,
        COUNT(t.id) as sessions
    FROM users u
    LEFT JOIN timesheets t ON u.id = t.user_id AND t.date >= start_date AND t.date <= end_date
    WHERE u.active = true
    GROUP BY u.id, u.username, u.first_name, u.last_name
    HAVING COALESCE(SUM(t.duration), 0) > 0
    ORDER BY total_hours DESC;
END;$$;


ALTER FUNCTION "public"."get_time_user_performance"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_time_weekly_summary"("start_date" "date", "end_date" "date") RETURNS TABLE("week_start" "date", "week_end" "date", "total_hours" numeric, "daily_average" numeric, "users" bigint, "clients" bigint, "sessions" bigint)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH weekly_data AS (
        SELECT 
            DATE_TRUNC('week', t.date) as week_start,
            DATE_TRUNC('week', t.date) + INTERVAL '6 days' as week_end,
            SUM(t.duration) / 3600.0 as total_hours,
            COUNT(DISTINCT t.user_id) as users,
            COUNT(DISTINCT t.jobcode_id) as clients,
            COUNT(t.id) as sessions
        FROM timesheets t
        WHERE t.date >= start_date AND t.date <= end_date
        GROUP BY DATE_TRUNC('week', t.date)
    )
    SELECT 
        wd.week_start::DATE,
        wd.week_end::DATE,
        COALESCE(wd.total_hours, 0) as total_hours,
        CASE 
            WHEN wd.users > 0 THEN
                COALESCE(wd.total_hours, 0) / 7.0
            ELSE 0
        END as daily_average,
        wd.users,
        wd.clients,
        wd.sessions
    FROM weekly_data wd
    ORDER BY wd.week_start;
END;
$$;


ALTER FUNCTION "public"."get_time_weekly_summary"("start_date" "date", "end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timesheet_entries_task"("p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0, "p_jobcode_id" bigint DEFAULT NULL::bigint, "p_user_id" bigint DEFAULT NULL::bigint) RETURNS TABLE("duration_hours" numeric, "value" "text", "user_id" bigint, "jobcode_id" bigint, "jobcode_name" "text", "username" "text", "start_ts" timestamp with time zone, "end_ts" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    select 
        (t.duration / 3600.0)::numeric as duration_hours,  -- seconds → hours
        tcv.value,
        t.user_id,
        t.jobcode_id,
        j.name as jobcode_name,
        u.username,
        nullif(t.start, '')::timestamptz as start_ts,
        nullif(t."end", '')::timestamptz as end_ts
    from timesheets t
    left join jobcodes j on j.id = t.jobcode_id
    left join users u on u.id = t.user_id
    left join timesheet_customfield_values tcv
        on tcv.timesheet_id = t.id
    where tcv.value != ''
      and (p_jobcode_id is null or t.jobcode_id = p_jobcode_id)
      and (p_user_id is null or t.user_id = p_user_id)
    order by start_ts
    limit p_limit offset p_offset;
end;
$$;


ALTER FUNCTION "public"."get_timesheet_entries_task"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timesheet_summary_by_jobcode"("jobcode_id_input" bigint) RETURNS TABLE("user_id" bigint, "username" "text", "jobcode_id" bigint, "total_duration" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.user_id, 
        u.username,
        t.jobcode_id, 
        SUM(t.duration)::BIGINT AS total_duration
    FROM timesheets AS t
    LEFT JOIN users AS u ON u.id = t.user_id
    WHERE t.jobcode_id = jobcode_id_input
    GROUP BY t.user_id, u.username, t.jobcode_id;
END;
$$;


ALTER FUNCTION "public"."get_timesheet_summary_by_jobcode"("jobcode_id_input" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timesheet_summary_by_jobcode_daily"("jobcode_id_input" bigint, "user_id_input" bigint DEFAULT NULL::bigint, "limit_count" integer DEFAULT 50, "offset_count" integer DEFAULT 0) RETURNS TABLE("work_date" "date", "user_id" bigint, "username" "text", "jobcode_id" bigint, "start_date" "text", "end_date" "text", "total_duration" numeric)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        DATE(NULLIF(t.start, '')::timestamptz) AS work_date,
        t.user_id,
        u.username,
        t.jobcode_id,
         MIN(t.start) AS start_date,
        MAX(t."end") AS end_date,
        ROUND(SUM(t.duration) / 3600.0, 2) AS total_duration
    FROM timesheets AS t
    LEFT JOIN users AS u ON u.id = t.user_id
    WHERE t.jobcode_id = jobcode_id_input
      AND (user_id_input IS NULL OR t.user_id = user_id_input)
    GROUP BY work_date, t.user_id, u.username, t.jobcode_id
    ORDER BY work_date DESC, total_duration DESC
    LIMIT limit_count OFFSET offset_count;
END;
$$;


ALTER FUNCTION "public"."get_timesheet_summary_by_jobcode_daily"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timesheet_summary_by_jobcode_paginated"("jobcode_id_input" bigint, "limit_count" integer DEFAULT 50, "offset_count" integer DEFAULT 0) RETURNS TABLE("user_id" bigint, "username" "text", "jobcode_id" bigint, "total_duration" numeric, "start_date" "text", "end_date" "text", "days_worked" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.user_id,
        u.username,
        t.jobcode_id,
        ROUND(SUM(t.duration) / 3600.0, 2) AS total_duration,
        MIN(t.start) AS start_date,
        MAX(t."end") AS end_date,
         COUNT(DISTINCT DATE(NULLIF(t.start, '')::timestamptz)) AS days_worked 
    FROM timesheets AS t
    LEFT JOIN users AS u ON u.id = t.user_id
    WHERE t.jobcode_id = jobcode_id_input
    GROUP BY t.user_id, u.username, t.jobcode_id
    ORDER BY total_duration DESC
    LIMIT limit_count OFFSET offset_count;
END;
$$;


ALTER FUNCTION "public"."get_timesheet_summary_by_jobcode_paginated"("jobcode_id_input" bigint, "limit_count" integer, "offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_timesheet_summary_by_jobcode_weekly"("jobcode_id_input" bigint, "user_id_input" bigint DEFAULT NULL::bigint, "limit_count" integer DEFAULT 50, "offset_count" integer DEFAULT 0) RETURNS TABLE("week_start" "date", "user_id" bigint, "username" "text", "jobcode_id" bigint, "total_duration" numeric, "start_date" "text", "end_date" "text", "days_worked" bigint)
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        date_trunc('week', NULLIF(t.start, '')::timestamptz)::date AS week_start,
        t.user_id,
        u.username,
        t.jobcode_id,
        ROUND(SUM(t.duration) / 3600.0, 2) AS total_duration,
         MIN(t.start) AS start_date,
        MAX(t."end") AS end_date,
        COUNT(DISTINCT DATE(NULLIF(t.start, '')::timestamptz)) AS days_worked
    FROM timesheets AS t
    LEFT JOIN users AS u ON u.id = t.user_id
    WHERE t.jobcode_id = jobcode_id_input
      AND (user_id_input IS NULL OR t.user_id = user_id_input)
    GROUP BY week_start, t.user_id, u.username, t.jobcode_id
    ORDER BY week_start DESC, total_duration DESC
    LIMIT limit_count OFFSET offset_count;
END;
$$;


ALTER FUNCTION "public"."get_timesheet_summary_by_jobcode_weekly"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_client_time_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("client_name" "text", "total_hours" numeric, "sessions" bigint, "avg_session_hours" numeric, "first_date" "date", "last_date" "date")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        j.name as client_name,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(t.id) as sessions,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_hours,
        MIN(t.date) as first_date,
        MAX(t.date) as last_date
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE t.user_id = user_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param
    GROUP BY j.id, j.name
    ORDER BY total_hours DESC;
END;
$$;


ALTER FUNCTION "public"."get_user_client_time_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_daily_tasks"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date") RETURNS TABLE("work_date" "date", "client_name" "text", "task_name" "text", "hours_worked" numeric)
    LANGUAGE "sql" STABLE
    AS $$
SELECT
    DATE(t.start::timestamptz) AS work_date,
    j.name AS client_name,
    COALESCE(tcf.value, 'No Task') AS task_name,
    ROUND(EXTRACT(EPOCH FROM (t."end"::timestamptz - t.start::timestamptz))/3600.0, 2) AS hours_worked
FROM timesheets t
JOIN jobcodes j ON j.id = t.jobcode_id
LEFT JOIN timesheet_customfield_values tcf ON tcf.timesheet_id = t.id
LEFT JOIN custom_fields cf ON cf.id = tcf.customfield_id
WHERE t.user_id = p_user_id
  AND (p_start_date IS NULL OR DATE(t.start::timestamptz) >= p_start_date)
  AND (p_end_date IS NULL OR DATE(t.start::timestamptz) <= p_end_date)
  AND t.start IS NOT NULL 
  AND t."end" IS NOT NULL
  AND t.start != ''
  AND t."end" != ''
  AND (tcf.value IS NOT NULL AND tcf.value != '')
ORDER BY work_date DESC, j.name, tcf.value;
$$;


ALTER FUNCTION "public"."get_user_daily_tasks"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_daily_timesheet_summary"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_jobcode_filter" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS TABLE("work_day" "text", "client" "text", "task" "text", "hours" numeric)
    LANGUAGE "plpgsql"
    AS $_$
begin
    return query
    with ts as (
        select 
            date(nullif(t."start", '')::timestamptz) as day_col,
            j.name as client,
            cfo.name as task,
            extract(
                epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)
            )/3600.0 as hours
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
    order by ts.day_col, ts.client, ts.task
    limit p_limit offset p_offset;
end;
$_$;


ALTER FUNCTION "public"."get_user_daily_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("work_date" "date", "total_hours" numeric, "clients_worked" bigint, "sessions" bigint, "longest_session_hours" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.date as work_date,
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT j.id) as clients_worked,
        COUNT(t.id) as sessions,
        COALESCE(MAX(t.duration) / 3600.0, 0) as longest_session_hours
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE t.user_id = user_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param
    GROUP BY t.date
    ORDER BY t.date DESC;
END;
$$;


ALTER FUNCTION "public"."get_user_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_period_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("total_hours" numeric, "working_days" bigint, "avg_hours_per_day" numeric, "clients_served" bigint, "total_sessions" bigint, "avg_session_length" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
        COUNT(DISTINCT t.date) as working_days,
        CASE 
            WHEN COUNT(DISTINCT t.date) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(DISTINCT t.date)
            ELSE 0
        END as avg_hours_per_day,
        COUNT(DISTINCT j.id) as clients_served,
        COUNT(t.id) as total_sessions,
        CASE 
            WHEN COUNT(t.id) > 0 THEN 
                COALESCE(SUM(t.duration) / 3600.0, 0) / COUNT(t.id)
            ELSE 0
        END as avg_session_length
    FROM timesheets t
    JOIN jobcodes j ON t.jobcode_id = j.id
    WHERE t.user_id = user_id_param
        AND t.date >= start_date_param
        AND t.date <= end_date_param;
END;
$$;


ALTER FUNCTION "public"."get_user_period_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_summary_simple_v5"("p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_user_filter" "text" DEFAULT NULL::"text", "p_client_filter" "text" DEFAULT NULL::"text", "p_sort_field" "text" DEFAULT 'total_hours'::"text", "p_sort_order" "text" DEFAULT 'desc'::"text", "p_limit_count" integer DEFAULT 1000, "p_offset_count" integer DEFAULT 0) RETURNS TABLE("user_id" bigint, "username" "text", "start_date" "date", "end_date" "date", "total_hours" numeric, "days_worked" bigint, "daily_average" numeric, "clients" "text"[], "task_custom_fields" "text"[])
    LANGUAGE "plpgsql"
    SET "statement_timeout" TO '4s'
    AS $$
BEGIN
    RETURN QUERY
    WITH user_timesheet_data AS (
        SELECT 
            t.user_id,
            COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) AS username,
            t.id AS timesheet_id,
            t.jobcode_id,
            j.name AS jobcode_name,
            NULLIF(t."start", '')::timestamptz AS start_ts,
            NULLIF(t."end", '')::timestamptz AS end_ts,
            EXTRACT(epoch FROM (NULLIF(t."end", '')::timestamptz - NULLIF(t."start", '')::timestamptz))/3600.0 AS hours,
            DATE(NULLIF(t."start", '')::timestamptz) AS work_date,
            tcf.customfield_id,
            cf.name AS custom_field_name,
            tcf.value AS custom_field_value,
            cfo.name AS custom_field_option_name
        FROM public.timesheets t
        JOIN public.users u ON u.id = t.user_id
        JOIN public.jobcodes j ON j.id = t.jobcode_id
        LEFT JOIN public.timesheet_customfield_values tcf ON tcf.timesheet_id = t.id
        LEFT JOIN public.custom_fields cf ON cf.id = tcf.customfield_id
        LEFT JOIN public.custom_field_options cfo 
            ON cfo.customfield_id = cf.id 
           AND cfo.name = tcf.value
        WHERE 
            (p_start_date IS NULL OR DATE(NULLIF(t."start", '')::timestamptz) >= p_start_date)
            AND (p_end_date IS NULL OR DATE(NULLIF(t."start", '')::timestamptz) <= p_end_date)
            AND (p_user_filter IS NULL OR COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) ILIKE '%' || p_user_filter || '%')
            AND (p_client_filter IS NULL OR j.name ILIKE '%' || p_client_filter || '%')
            AND NULLIF(t."start", '') IS NOT NULL 
            AND NULLIF(t."end", '') IS NOT NULL
    ),
    user_summary AS (
        SELECT 
            utd.user_id,
            utd.username,
            MIN(utd.work_date) AS start_date,
            MAX(utd.work_date) AS end_date,
            ROUND(SUM(utd.hours)::numeric, 2) AS total_hours,
            COUNT(DISTINCT utd.work_date) AS days_worked,
            ROUND(SUM(utd.hours)::numeric / NULLIF(COUNT(DISTINCT utd.work_date), 0), 2) AS daily_average,
            ARRAY_AGG(DISTINCT utd.jobcode_name) FILTER (WHERE utd.jobcode_name IS NOT NULL) AS clients,
            ARRAY_AGG(DISTINCT utd.custom_field_option_name) FILTER (WHERE utd.custom_field_option_name IS NOT NULL) AS task_custom_fields
        FROM user_timesheet_data utd
        GROUP BY utd.user_id, utd.username
    )
    SELECT 
        us.user_id,
        us.username,
        us.start_date,
        us.end_date,
        us.total_hours,
        us.days_worked,
        us.daily_average,
        us.clients,
        us.task_custom_fields
    FROM user_summary us
    ORDER BY
        CASE WHEN p_sort_field='username' AND p_sort_order='asc' THEN us.username END ASC,
        CASE WHEN p_sort_field='username' AND p_sort_order='desc' THEN us.username END DESC,
        CASE WHEN p_sort_field='total_hours' AND p_sort_order='asc' THEN us.total_hours END ASC,
        CASE WHEN p_sort_field='total_hours' AND p_sort_order='desc' THEN us.total_hours END DESC,
        CASE WHEN p_sort_field='daily_average' AND p_sort_order='asc' THEN us.daily_average END ASC,
        CASE WHEN p_sort_field='daily_average' AND p_sort_order='desc' THEN us.daily_average END DESC,
        CASE WHEN p_sort_field='days_worked' AND p_sort_order='asc' THEN us.days_worked END ASC,
        CASE WHEN p_sort_field='days_worked' AND p_sort_order='desc' THEN us.days_worked END DESC
    LIMIT p_limit_count OFFSET p_offset_count;
END;
$$;


ALTER FUNCTION "public"."get_user_summary_simple_v5"("p_start_date" "date", "p_end_date" "date", "p_user_filter" "text", "p_client_filter" "text", "p_sort_field" "text", "p_sort_order" "text", "p_limit_count" integer, "p_offset_count" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_team_comparison"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") RETURNS TABLE("metric_name" "text", "user_value" numeric, "team_average" numeric, "user_rank" bigint, "total_users" bigint, "percentile" numeric)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
    WITH user_metrics AS (
        SELECT 
            u.id as user_id,
            COALESCE(SUM(t.duration) / 3600.0, 0) as total_hours,
            COUNT(DISTINCT t.date) as working_days,
            COUNT(DISTINCT j.id) as clients_served,
            COUNT(t.id) as total_sessions,
            COALESCE(SUM(t.duration) / 3600.0, 0) / NULLIF(COUNT(DISTINCT t.date), 0) as avg_hours_per_day,
            COALESCE(SUM(t.duration) / 3600.0, 0) / NULLIF(COUNT(t.id), 0) as avg_session_length,
            COALESCE(MAX(t.duration) / 3600.0, 0) as longest_session
        FROM users u
        LEFT JOIN timesheets t ON u.id = t.user_id
        LEFT JOIN jobcodes j ON t.jobcode_id = j.id
        WHERE u.active = true
            AND (t.date IS NULL OR (t.date >= start_date_param AND t.date <= end_date_param))
        GROUP BY u.id
    ),
    ranked_metrics AS (
        SELECT 
            user_id,
            total_hours,
            working_days,
            clients_served,
            total_sessions,
            avg_hours_per_day,
            avg_session_length,
            longest_session,
            RANK() OVER (ORDER BY total_hours DESC) as total_hours_rank,
            RANK() OVER (ORDER BY avg_hours_per_day DESC) as avg_hours_rank,
            RANK() OVER (ORDER BY clients_served DESC) as clients_rank,
            RANK() OVER (ORDER BY avg_session_length DESC) as session_length_rank,
            RANK() OVER (ORDER BY longest_session DESC) as longest_session_rank,
            COUNT(*) OVER() as total_users
        FROM user_metrics
    )
    SELECT 
        'Total Hours'::TEXT as metric_name,
        um.total_hours as user_value,
        AVG(um.total_hours) OVER() as team_average,
        rm.total_hours_rank as user_rank,
        rm.total_users,
        (rm.total_users - rm.total_hours_rank + 1)::NUMERIC / rm.total_users * 100 as percentile
    FROM user_metrics um
    JOIN ranked_metrics rm ON um.user_id = rm.user_id
    WHERE um.user_id = user_id_param
    
    UNION ALL
    
    SELECT 
        'Avg Hours/Day'::TEXT as metric_name,
        um.avg_hours_per_day as user_value,
        AVG(um.avg_hours_per_day) OVER() as team_average,
        rm.avg_hours_rank as user_rank,
        rm.total_users,
        (rm.total_users - rm.avg_hours_rank + 1)::NUMERIC / rm.total_users * 100 as percentile
    FROM user_metrics um
    JOIN ranked_metrics rm ON um.user_id = rm.user_id
    WHERE um.user_id = user_id_param
    
    UNION ALL
    
    SELECT 
        'Clients Served'::TEXT as metric_name,
        um.clients_served as user_value,
        AVG(um.clients_served) OVER() as team_average,
        rm.clients_rank as user_rank,
        rm.total_users,
        (rm.total_users - rm.clients_rank + 1)::NUMERIC / rm.total_users * 100 as percentile
    FROM user_metrics um
    JOIN ranked_metrics rm ON um.user_id = rm.user_id
    WHERE um.user_id = user_id_param
    
    UNION ALL
    
    SELECT 
        'Avg Session Length'::TEXT as metric_name,
        um.avg_session_length as user_value,
        AVG(um.avg_session_length) OVER() as team_average,
        rm.session_length_rank as user_rank,
        rm.total_users,
        (rm.total_users - rm.session_length_rank + 1)::NUMERIC / rm.total_users * 100 as percentile
    FROM user_metrics um
    JOIN ranked_metrics rm ON um.user_id = rm.user_id
    WHERE um.user_id = user_id_param
    
    UNION ALL
    
    SELECT 
        'Longest Session'::TEXT as metric_name,
        um.longest_session as user_value,
        AVG(um.longest_session) OVER() as team_average,
        rm.longest_session_rank as user_rank,
        rm.total_users,
        (rm.total_users - rm.longest_session_rank + 1)::NUMERIC / rm.total_users * 100 as percentile
    FROM user_metrics um
    JOIN ranked_metrics rm ON um.user_id = rm.user_id
    WHERE um.user_id = user_id_param;
END;
$$;


ALTER FUNCTION "public"."get_user_team_comparison"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_weekly_timesheet_summary"("p_user_id" bigint, "p_start_date" "date" DEFAULT NULL::"date", "p_end_date" "date" DEFAULT NULL::"date", "p_jobcode_filter" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 100, "p_offset" integer DEFAULT 0) RETURNS TABLE("work_week" "text", "client" "text", "task" "text", "hours" numeric)
    LANGUAGE "plpgsql"
    AS $_$
begin
    return query
    with ts as (
        select 
            date_trunc('week', nullif(t."start", '')::timestamptz)::date as week_col,
            j.name as client,
            cfo.name as task,
            extract(
                epoch from (nullif(t."end", '')::timestamptz - nullif(t."start", '')::timestamptz)
            )/3600.0 as hours
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
    order by ts.week_col, ts.client, ts.task
    limit p_limit offset p_offset;
end;
$_$;


ALTER FUNCTION "public"."get_user_weekly_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_weekly_timesheet_summary"("p_limit" integer DEFAULT 1000, "p_offset" integer DEFAULT 0, "p_jobcode_id" bigint DEFAULT NULL::bigint, "p_user_id" bigint DEFAULT NULL::bigint) RETURNS TABLE("week_start" "date", "value" "text", "username" "text", "jobcode_name" "text", "total_duration_hours" numeric, "entry_count" bigint)
    LANGUAGE "plpgsql"
    AS $$
begin
    return query
    select 
        date_trunc('week', nullif(t.start, '')::timestamptz)::date as week_start,
        tcv.value,
        u.username,
        j.name as jobcode_name,
        round(sum(t.duration) / 3600.0, 2) as total_duration_hours,  -- hours rounded to 2 decimals
        count(*) as entry_count
    from timesheets t
    left join jobcodes j on j.id = t.jobcode_id
    left join users u on u.id = t.user_id
    left join timesheet_customfield_values tcv
        on tcv.timesheet_id = t.id
    where tcv.value is not null
      and tcv.value != ''
      and (p_jobcode_id is null or t.jobcode_id = p_jobcode_id)
      and (p_user_id is null or t.user_id = p_user_id)
    group by week_start, tcv.value, u.username, j.name
    order by week_start, u.username, j.name, tcv.value
    limit p_limit offset p_offset;
end;
$$;


ALTER FUNCTION "public"."get_weekly_timesheet_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."accubid_breakdowns" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "job_name" "text",
    "client_name" "text",
    "Task_name" "text",
    "time_estimate" double precision,
    "cost_estimate" double precision,
    "progress" double precision
);


ALTER TABLE "public"."accubid_breakdowns" OWNER TO "postgres";


ALTER TABLE "public"."accubid_breakdowns" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."accubid_breakdowns_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."auth_codes" (
    "id" bigint NOT NULL,
    "access_token" "text" NOT NULL,
    "refresh_token" "text" NOT NULL,
    "token_type" character varying(50) NOT NULL,
    "expires_in" integer NOT NULL,
    "scope" "text",
    "user_id" character varying(100) NOT NULL,
    "company_id" character varying(100),
    "client_url" character varying(255),
    "created_at" timestamp without time zone DEFAULT "now"(),
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."auth_codes" OWNER TO "postgres";


CREATE SEQUENCE IF NOT EXISTS "public"."auth_codes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "public"."auth_codes_id_seq" OWNER TO "postgres";


ALTER SEQUENCE "public"."auth_codes_id_seq" OWNED BY "public"."auth_codes"."id";



CREATE TABLE IF NOT EXISTS "public"."auth_tokens" (
    "id" bigint NOT NULL,
    "code" "text" NOT NULL,
    "state" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."auth_tokens" OWNER TO "postgres";


ALTER TABLE "public"."auth_tokens" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."auth_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."custom_field_options" (
    "id" bigint NOT NULL,
    "customfield_id" bigint,
    "active" boolean,
    "short_code" "text",
    "name" "text",
    "last_modified" timestamp with time zone,
    "required_customfields" bigint[] DEFAULT '{}'::bigint[]
);


ALTER TABLE "public"."custom_field_options" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_fields" (
    "id" bigint NOT NULL,
    "active" boolean NOT NULL,
    "required" boolean,
    "applies_to" "text",
    "type" "text",
    "short_code" "text",
    "regex_filter" "text",
    "name" "text",
    "last_modified" timestamp with time zone,
    "created" timestamp with time zone,
    "ui_preference" "text",
    "required_customfields" bigint[] DEFAULT '{}'::bigint[],
    "show_to_all" boolean DEFAULT false
);


ALTER TABLE "public"."custom_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."files" (
    "id" bigint NOT NULL,
    "uploaded_by_user_id" bigint,
    "file_name" "text" NOT NULL,
    "active" boolean,
    "size" bigint,
    "last_modified" timestamp with time zone,
    "created" timestamp with time zone,
    "file_description" "text"
);


ALTER TABLE "public"."files" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."jobcode_required_customfields" (
    "jobcode_id" bigint NOT NULL,
    "customfield_id" bigint NOT NULL
);


ALTER TABLE "public"."jobcode_required_customfields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."jobcodes" (
    "id" bigint NOT NULL,
    "parent_id" bigint,
    "assigned_to_all" boolean,
    "billable" boolean,
    "active" boolean,
    "type" "text",
    "has_children" boolean,
    "billable_rate" numeric(12,2),
    "short_code" "text",
    "name" "text" NOT NULL,
    "last_modified" timestamp with time zone,
    "created" timestamp with time zone,
    "filtered_customfielditems" "text",
    "connect_with_quickbooks" boolean,
    "progress" double precision
);


ALTER TABLE "public"."jobcodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."location_map" (
    "id" bigint NOT NULL,
    "x_table" "text" NOT NULL,
    "x_id" bigint NOT NULL,
    "location_id" bigint NOT NULL,
    "created" timestamp with time zone,
    "last_modified" timestamp with time zone
);


ALTER TABLE "public"."location_map" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."locations" (
    "id" bigint NOT NULL,
    "addr1" "text",
    "addr2" "text",
    "city" "text",
    "state" "text",
    "zip" "text",
    "country" "text",
    "formatted_address" "text",
    "active" boolean,
    "latitude" double precision,
    "longitude" double precision,
    "place_id" "text",
    "place_id_hash" "text",
    "label" "text",
    "notes" "text",
    "geocoding_status" "text",
    "created" timestamp with time zone,
    "last_modified" timestamp with time zone,
    "geofence_config_id" bigint,
    "linked_objects" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "locations_geocoding_status_check" CHECK (("geocoding_status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'complete'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."locations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."project_progress" (
    "id" bigint NOT NULL,
    "project_id" bigint,
    "jobcode_id" bigint,
    "progress" double precision,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."project_progress" OWNER TO "postgres";


ALTER TABLE "public"."project_progress" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."project_progess_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" bigint NOT NULL,
    "jobcode_id" bigint NOT NULL,
    "parent_jobcode_id" bigint,
    "name" "text" NOT NULL,
    "status" "text" DEFAULT 'not_started'::"text",
    "description" "text",
    "start_date" "text",
    "due_date" "text",
    "completed_date" "text",
    "active" boolean,
    "last_modified" "text",
    "created" "text",
    "linked_objects" "jsonb" DEFAULT '{}'::"jsonb",
    CONSTRAINT "projects_status_check" CHECK (("status" = ANY (ARRAY['not_started'::"text", 'in_progress'::"text", 'completed'::"text", 'on_hold'::"text"])))
);


ALTER TABLE "public"."projects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."task_progress" (
    "id" bigint NOT NULL,
    "task_id" bigint,
    "progress" double precision,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."task_progress" OWNER TO "postgres";


ALTER TABLE "public"."task_progress" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."task_progress_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."timesheet_customfield_values" (
    "timesheet_id" bigint NOT NULL,
    "customfield_id" bigint NOT NULL,
    "value" "text"
);


ALTER TABLE "public"."timesheet_customfield_values" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."timesheet_files" (
    "timesheet_id" bigint NOT NULL,
    "file_id" bigint NOT NULL
);


ALTER TABLE "public"."timesheet_files" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."timesheets" (
    "id" bigint NOT NULL,
    "user_id" bigint NOT NULL,
    "jobcode_id" bigint NOT NULL,
    "start" "text",
    "end" "text",
    "duration" bigint,
    "date" "date",
    "tz" integer,
    "tz_str" "text",
    "type" "text",
    "location" "text",
    "on_the_clock" boolean,
    "locked" integer,
    "notes" "text",
    "customfields" "jsonb",
    "last_modified" timestamp with time zone
);


ALTER TABLE "public"."timesheets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" bigint NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "group_id" bigint,
    "active" boolean,
    "employee_number" bigint,
    "salaried" boolean,
    "exempt" boolean,
    "username" "text",
    "email" "text",
    "email_verified" boolean,
    "payroll_id" "text",
    "mobile_number" "text",
    "hire_date" "date",
    "term_date" "date",
    "last_modified" timestamp with time zone,
    "last_active" timestamp with time zone,
    "created" timestamp with time zone,
    "client_url" "text",
    "company_name" "text",
    "profile_image_url" "text",
    "display_name" "text",
    "submitted_to" "date",
    "approved_to" "date",
    "require_password_change" boolean,
    "pay_rate" numeric,
    "pay_interval" "text",
    "permissions" "jsonb",
    "pto_balances" "jsonb",
    "manager_of_group_ids" bigint[],
    "customfields" "jsonb"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_all_employees_summary" AS
 SELECT "employee_id",
    "employee_name",
    "full_name",
    "work_start_date",
    "work_end_date",
    "total_work_hours",
    "actual_work_days",
    "average_daily_hours",
    "client_list",
    "task_list",
    "custom_field_values"
   FROM "public"."get_all_employees_summary"() "get_all_employees_summary"("employee_id", "employee_name", "full_name", "work_start_date", "work_end_date", "total_work_hours", "actual_work_days", "average_daily_hours", "client_list", "task_list", "custom_field_values");


ALTER VIEW "public"."v_all_employees_summary" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_daily_work_all_employees" AS
 SELECT "t"."user_id",
    "u"."username",
    "t"."date" AS "work_date",
    "j"."name" AS "client_name",
    COALESCE("p"."name", "j"."name") AS "task_name",
    (("t"."duration")::numeric / 3600.0) AS "hours_worked",
    "j"."short_code" AS "job_code"
   FROM ((("public"."timesheets" "t"
     JOIN "public"."users" "u" ON (("t"."user_id" = "u"."id")))
     JOIN "public"."jobcodes" "j" ON (("t"."jobcode_id" = "j"."id")))
     LEFT JOIN "public"."projects" "p" ON (("j"."id" = "p"."jobcode_id")))
  ORDER BY "t"."user_id", "t"."date" DESC;


ALTER VIEW "public"."v_daily_work_all_employees" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."v_weekly_work_all_employees" AS
 SELECT "t"."user_id",
    "u"."username",
    ("date_trunc"('week'::"text", ("t"."date")::timestamp with time zone))::"date" AS "work_week",
    "j"."name" AS "client_name",
    COALESCE("p"."name", "j"."name") AS "task_name",
    ("sum"("t"."duration") / 3600.0) AS "hours_worked",
    "j"."short_code" AS "job_code"
   FROM ((("public"."timesheets" "t"
     JOIN "public"."users" "u" ON (("t"."user_id" = "u"."id")))
     JOIN "public"."jobcodes" "j" ON (("t"."jobcode_id" = "j"."id")))
     LEFT JOIN "public"."projects" "p" ON (("j"."id" = "p"."jobcode_id")))
  GROUP BY "t"."user_id", "u"."username", ("date_trunc"('week'::"text", ("t"."date")::timestamp with time zone)), "j"."name", "p"."name", "j"."short_code"
  ORDER BY "t"."user_id", (("date_trunc"('week'::"text", ("t"."date")::timestamp with time zone))::"date") DESC;


ALTER VIEW "public"."v_weekly_work_all_employees" OWNER TO "postgres";


ALTER TABLE ONLY "public"."auth_codes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."auth_codes_id_seq"'::"regclass");



ALTER TABLE ONLY "public"."accubid_breakdowns"
    ADD CONSTRAINT "accubid_breakdowns_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_codes"
    ADD CONSTRAINT "auth_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."auth_tokens"
    ADD CONSTRAINT "auth_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_field_options"
    ADD CONSTRAINT "custom_field_options_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_fields"
    ADD CONSTRAINT "custom_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."files"
    ADD CONSTRAINT "files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."jobcode_required_customfields"
    ADD CONSTRAINT "jobcode_required_customfields_pkey" PRIMARY KEY ("jobcode_id", "customfield_id");



ALTER TABLE ONLY "public"."jobcodes"
    ADD CONSTRAINT "jobcodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."location_map"
    ADD CONSTRAINT "location_map_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."locations"
    ADD CONSTRAINT "locations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."project_progress"
    ADD CONSTRAINT "project_progess_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."task_progress"
    ADD CONSTRAINT "task_progress_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."timesheet_customfield_values"
    ADD CONSTRAINT "timesheet_customfield_values_pkey" PRIMARY KEY ("timesheet_id", "customfield_id");



ALTER TABLE ONLY "public"."timesheet_files"
    ADD CONSTRAINT "timesheet_files_pkey" PRIMARY KEY ("timesheet_id", "file_id");



ALTER TABLE ONLY "public"."timesheets"
    ADD CONSTRAINT "timesheets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_auth_codes_company_id" ON "public"."auth_codes" USING "btree" ("company_id");



CREATE INDEX "idx_auth_codes_user_id" ON "public"."auth_codes" USING "btree" ("user_id");



CREATE INDEX "idx_jobcodes_active" ON "public"."jobcodes" USING "btree" ("id") WHERE ("active" = true);



CREATE INDEX "idx_jobcodes_name" ON "public"."jobcodes" USING "btree" ("name");



CREATE INDEX "idx_jobcodes_name_new" ON "public"."jobcodes" USING "btree" ("name") WHERE ("name" IS NOT NULL);



CREATE INDEX "idx_projects_jobcode_new" ON "public"."projects" USING "btree" ("jobcode_id") WHERE ("jobcode_id" IS NOT NULL);



CREATE INDEX "idx_timesheet_customfield_values_new" ON "public"."timesheet_customfield_values" USING "btree" ("timesheet_id", "customfield_id");



CREATE INDEX "idx_timesheets_date_analytics" ON "public"."timesheets" USING "btree" ("date") WHERE ("date" IS NOT NULL);



CREATE INDEX "idx_timesheets_end_date" ON "public"."timesheets" USING "btree" ("end");



CREATE INDEX "idx_timesheets_jobcode_new" ON "public"."timesheets" USING "btree" ("jobcode_id") WHERE ("jobcode_id" IS NOT NULL);



CREATE INDEX "idx_timesheets_start_date" ON "public"."timesheets" USING "btree" ("start");



CREATE INDEX "idx_timesheets_user_date_analytics" ON "public"."timesheets" USING "btree" ("user_id", "date") WHERE ("date" IS NOT NULL);



CREATE INDEX "idx_timesheets_user_date_new" ON "public"."timesheets" USING "btree" ("user_id", "date") WHERE ("date" IS NOT NULL);



CREATE INDEX "idx_users_active" ON "public"."users" USING "btree" ("id") WHERE ("active" = true);



CREATE INDEX "idx_users_active_new" ON "public"."users" USING "btree" ("id") WHERE ("active" = true);



CREATE INDEX "idx_users_username" ON "public"."users" USING "btree" ("username");



ALTER TABLE ONLY "public"."files"
    ADD CONSTRAINT "files_uploaded_by_user_id_fkey" FOREIGN KEY ("uploaded_by_user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."custom_field_options"
    ADD CONSTRAINT "fk_customfield" FOREIGN KEY ("customfield_id") REFERENCES "public"."custom_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jobcode_required_customfields"
    ADD CONSTRAINT "jobcode_required_customfields_jobcode_id_fkey" FOREIGN KEY ("jobcode_id") REFERENCES "public"."jobcodes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."jobcodes"
    ADD CONSTRAINT "jobcodes_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."jobcodes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."location_map"
    ADD CONSTRAINT "location_map_location_id_fkey" FOREIGN KEY ("location_id") REFERENCES "public"."locations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."project_progress"
    ADD CONSTRAINT "project_progess_jobcode_id_fkey" FOREIGN KEY ("jobcode_id") REFERENCES "public"."jobcodes"("id");



ALTER TABLE ONLY "public"."project_progress"
    ADD CONSTRAINT "project_progess_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_jobcode_id_fkey" FOREIGN KEY ("jobcode_id") REFERENCES "public"."jobcodes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_parent_jobcode_id_fkey" FOREIGN KEY ("parent_jobcode_id") REFERENCES "public"."jobcodes"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."task_progress"
    ADD CONSTRAINT "task_progress_task_id_fkey" FOREIGN KEY ("task_id") REFERENCES "public"."accubid_breakdowns"("id");



ALTER TABLE ONLY "public"."timesheet_customfield_values"
    ADD CONSTRAINT "timesheet_customfield_values_customfield_id_fkey" FOREIGN KEY ("customfield_id") REFERENCES "public"."custom_fields"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timesheet_customfield_values"
    ADD CONSTRAINT "timesheet_customfield_values_timesheet_id_fkey" FOREIGN KEY ("timesheet_id") REFERENCES "public"."timesheets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timesheet_files"
    ADD CONSTRAINT "timesheet_files_file_id_fkey" FOREIGN KEY ("file_id") REFERENCES "public"."files"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timesheet_files"
    ADD CONSTRAINT "timesheet_files_timesheet_id_fkey" FOREIGN KEY ("timesheet_id") REFERENCES "public"."timesheets"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timesheets"
    ADD CONSTRAINT "timesheets_jobcode_id_fkey" FOREIGN KEY ("jobcode_id") REFERENCES "public"."jobcodes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."timesheets"
    ADD CONSTRAINT "timesheets_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."calculate_working_days"("p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."calculate_working_days"("p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."calculate_working_days"("p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_accubid_task_summary"("p_limit" integer, "p_offset" integer, "p_job_name" "text", "p_user_id" integer, "p_jobcode_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_accubid_task_summary"("p_limit" integer, "p_offset" integer, "p_job_name" "text", "p_user_id" integer, "p_jobcode_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_accubid_task_summary"("p_limit" integer, "p_offset" integer, "p_job_name" "text", "p_user_id" integer, "p_jobcode_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_all_employees_summary"("p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_all_employees_summary"("p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_all_employees_summary"("p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_comparison"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_comparison"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_comparison"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_list"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_list"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_list"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_overview_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_overview_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_overview_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_time_summary"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_time_summary"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_time_summary"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_time_summary_count"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_time_summary_count"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_time_summary_count"("p_start_date" "date", "p_end_date" "date", "p_client_filter" "text", "p_project_filter" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_user_allocation"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_user_allocation"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_user_allocation"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_limit_count" integer, "p_offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint, "p_limit_count" integer, "p_offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint, "p_limit_count" integer, "p_offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_user_data"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint, "p_limit_count" integer, "p_offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_user_data_count"("p_client_name" "text", "p_start_date" "date", "p_end_date" "date", "p_project_filter" "text", "p_user_id_filter" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_client_weekly_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_client_weekly_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_client_weekly_summary"("client_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_comprehensive_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_comprehensive_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_comprehensive_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_dashboard_summary"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_analytics"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_client_distribution"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_client_distribution"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_client_distribution"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_complete_analytics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_period_type" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_complete_analytics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_period_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_complete_analytics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_period_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_daily_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_daily_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_daily_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_detailed_data"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_detailed_data"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_detailed_data"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_detailed_performance"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_detailed_performance"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_detailed_performance"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_kpis_comprehensive"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_kpis_comprehensive"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_kpis_comprehensive"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_performance_rating"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_performance_rating"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_performance_rating"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_productivity_metrics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_productivity_metrics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_productivity_metrics"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_summary_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_summary_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_summary_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_time_tracking"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_time_tracking"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_time_tracking"("employee_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_employee_weekly_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_employee_weekly_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_employee_weekly_work_data"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_financial_metrics"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_financial_metrics"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_financial_metrics"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_client_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_client_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_client_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_employee_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_employee_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_employee_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_productivity_metrics"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_productivity_metrics"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_productivity_metrics"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_task_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_task_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_task_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_individual_weekly_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_individual_weekly_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_individual_weekly_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_jobcode_daily_summary"("jobcode_id_input" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_jobcode_daily_summary"("jobcode_id_input" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_jobcode_daily_summary"("jobcode_id_input" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_jobcode_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_jobcode_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_jobcode_summary"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_analytics"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_analytics"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_analytics"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_list"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_list"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_list"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_summary"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_summary"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_summary"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_team_allocation"("project_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_team_allocation"("project_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_team_allocation"("project_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_project_timsheet_summary_v1"("limit_count" integer, "offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_project_timsheet_summary_v1"("limit_count" integer, "offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_project_timsheet_summary_v1"("limit_count" integer, "offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_task_analytics"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_task_analytics"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_task_analytics"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_task_duration_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" integer, "p_user_id" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_task_duration_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" integer, "p_user_id" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_task_duration_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" integer, "p_user_id" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_client_activity"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_client_activity"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_client_activity"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_daily_distribution"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_daily_distribution"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_daily_distribution"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_period_overview"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_period_overview"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_period_overview"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_session_analysis"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_session_analysis"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_session_analysis"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_tracking_summary"("start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_tracking_summary"("start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_tracking_summary"("start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_user_performance"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_user_performance"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_user_performance"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_time_weekly_summary"("start_date" "date", "end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_time_weekly_summary"("start_date" "date", "end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_time_weekly_summary"("start_date" "date", "end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timesheet_entries_task"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timesheet_entries_task"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timesheet_entries_task"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode"("jobcode_id_input" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode"("jobcode_id_input" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode"("jobcode_id_input" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_daily"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_daily"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_daily"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_paginated"("jobcode_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_paginated"("jobcode_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_paginated"("jobcode_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_weekly"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_weekly"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_timesheet_summary_by_jobcode_weekly"("jobcode_id_input" bigint, "user_id_input" bigint, "limit_count" integer, "offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_client_time_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_client_time_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_client_time_distribution"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_daily_tasks"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_daily_tasks"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_daily_tasks"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_daily_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_daily_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_daily_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_daily_work_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_period_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_period_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_period_summary"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_summary_simple_v5"("p_start_date" "date", "p_end_date" "date", "p_user_filter" "text", "p_client_filter" "text", "p_sort_field" "text", "p_sort_order" "text", "p_limit_count" integer, "p_offset_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_summary_simple_v5"("p_start_date" "date", "p_end_date" "date", "p_user_filter" "text", "p_client_filter" "text", "p_sort_field" "text", "p_sort_order" "text", "p_limit_count" integer, "p_offset_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_summary_simple_v5"("p_start_date" "date", "p_end_date" "date", "p_user_filter" "text", "p_client_filter" "text", "p_sort_field" "text", "p_sort_order" "text", "p_limit_count" integer, "p_offset_count" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_team_comparison"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_team_comparison"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_team_comparison"("user_id_param" bigint, "start_date_param" "date", "end_date_param" "date") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_weekly_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_weekly_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_weekly_timesheet_summary"("p_user_id" bigint, "p_start_date" "date", "p_end_date" "date", "p_jobcode_filter" "text", "p_limit" integer, "p_offset" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_weekly_timesheet_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."get_weekly_timesheet_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_weekly_timesheet_summary"("p_limit" integer, "p_offset" integer, "p_jobcode_id" bigint, "p_user_id" bigint) TO "service_role";


















GRANT ALL ON TABLE "public"."accubid_breakdowns" TO "anon";
GRANT ALL ON TABLE "public"."accubid_breakdowns" TO "authenticated";
GRANT ALL ON TABLE "public"."accubid_breakdowns" TO "service_role";



GRANT ALL ON SEQUENCE "public"."accubid_breakdowns_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."accubid_breakdowns_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."accubid_breakdowns_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."auth_codes" TO "anon";
GRANT ALL ON TABLE "public"."auth_codes" TO "authenticated";
GRANT ALL ON TABLE "public"."auth_codes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."auth_codes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."auth_codes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."auth_codes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."auth_tokens" TO "anon";
GRANT ALL ON TABLE "public"."auth_tokens" TO "authenticated";
GRANT ALL ON TABLE "public"."auth_tokens" TO "service_role";



GRANT ALL ON SEQUENCE "public"."auth_tokens_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."auth_tokens_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."auth_tokens_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."custom_field_options" TO "anon";
GRANT ALL ON TABLE "public"."custom_field_options" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_field_options" TO "service_role";



GRANT ALL ON TABLE "public"."custom_fields" TO "anon";
GRANT ALL ON TABLE "public"."custom_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_fields" TO "service_role";



GRANT ALL ON TABLE "public"."files" TO "anon";
GRANT ALL ON TABLE "public"."files" TO "authenticated";
GRANT ALL ON TABLE "public"."files" TO "service_role";



GRANT ALL ON TABLE "public"."jobcode_required_customfields" TO "anon";
GRANT ALL ON TABLE "public"."jobcode_required_customfields" TO "authenticated";
GRANT ALL ON TABLE "public"."jobcode_required_customfields" TO "service_role";



GRANT ALL ON TABLE "public"."jobcodes" TO "anon";
GRANT ALL ON TABLE "public"."jobcodes" TO "authenticated";
GRANT ALL ON TABLE "public"."jobcodes" TO "service_role";



GRANT ALL ON TABLE "public"."location_map" TO "anon";
GRANT ALL ON TABLE "public"."location_map" TO "authenticated";
GRANT ALL ON TABLE "public"."location_map" TO "service_role";



GRANT ALL ON TABLE "public"."locations" TO "anon";
GRANT ALL ON TABLE "public"."locations" TO "authenticated";
GRANT ALL ON TABLE "public"."locations" TO "service_role";



GRANT ALL ON TABLE "public"."project_progress" TO "anon";
GRANT ALL ON TABLE "public"."project_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."project_progress" TO "service_role";



GRANT ALL ON SEQUENCE "public"."project_progess_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."project_progess_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."project_progess_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";



GRANT ALL ON TABLE "public"."task_progress" TO "anon";
GRANT ALL ON TABLE "public"."task_progress" TO "authenticated";
GRANT ALL ON TABLE "public"."task_progress" TO "service_role";



GRANT ALL ON SEQUENCE "public"."task_progress_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."task_progress_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."task_progress_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."timesheet_customfield_values" TO "anon";
GRANT ALL ON TABLE "public"."timesheet_customfield_values" TO "authenticated";
GRANT ALL ON TABLE "public"."timesheet_customfield_values" TO "service_role";



GRANT ALL ON TABLE "public"."timesheet_files" TO "anon";
GRANT ALL ON TABLE "public"."timesheet_files" TO "authenticated";
GRANT ALL ON TABLE "public"."timesheet_files" TO "service_role";



GRANT ALL ON TABLE "public"."timesheets" TO "anon";
GRANT ALL ON TABLE "public"."timesheets" TO "authenticated";
GRANT ALL ON TABLE "public"."timesheets" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."v_all_employees_summary" TO "anon";
GRANT ALL ON TABLE "public"."v_all_employees_summary" TO "authenticated";
GRANT ALL ON TABLE "public"."v_all_employees_summary" TO "service_role";



GRANT ALL ON TABLE "public"."v_daily_work_all_employees" TO "anon";
GRANT ALL ON TABLE "public"."v_daily_work_all_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."v_daily_work_all_employees" TO "service_role";



GRANT ALL ON TABLE "public"."v_weekly_work_all_employees" TO "anon";
GRANT ALL ON TABLE "public"."v_weekly_work_all_employees" TO "authenticated";
GRANT ALL ON TABLE "public"."v_weekly_work_all_employees" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
