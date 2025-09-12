-- Simplified version with essential filters for API integration
CREATE OR REPLACE FUNCTION get_user_summary_simple_v5(
    -- Essential filters
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL,
    p_user_filter TEXT DEFAULT NULL,
    p_client_filter TEXT DEFAULT NULL,
    p_project_filter TEXT DEFAULT NULL,
    
    -- Sorting and pagination
    p_sort_field TEXT DEFAULT 'username',
    p_sort_order TEXT DEFAULT 'asc',
    p_limit_count INT DEFAULT 100,
    p_offset_count INT DEFAULT 0
)
RETURNS TABLE (
    user_id BIGINT,
    username TEXT,
    start_date DATE,
    end_date DATE,
    total_hours NUMERIC,
    days_worked INT,
    daily_average NUMERIC,
    clients TEXT[],
    task_custom_fields TEXT[]
) AS $$
WITH user_timesheet_data AS (
    SELECT 
        t.user_id,
        COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) AS username,
        t.id as timesheet_id,
        t.jobcode_id,
        j.name as jobcode_name,
        p.name as project_name,
        NULLIF(t."start", '')::timestamptz AS start_ts,
        NULLIF(t."end", '')::timestamptz AS end_ts,
        EXTRACT(EPOCH FROM (NULLIF(t."end", '')::timestamptz - NULLIF(t."start", '')::timestamptz))/3600.0 AS hours,
        DATE(NULLIF(t."start", '')::timestamptz) AS work_date,
        tcf.customfield_id,
        cf.name as custom_field_name,
        tcf.value as custom_field_value,
        cfo.name as custom_field_option_name
    FROM public.timesheets t
    JOIN public.users u ON u.id = t.user_id
    JOIN public.jobcodes j ON j.id = t.jobcode_id
    LEFT JOIN public.projects p ON p.jobcode_id = j.id
    LEFT JOIN public.timesheet_customfield_values tcf ON tcf.timesheet_id = t.id
    LEFT JOIN public.custom_fields cf ON cf.id = tcf.customfield_id
    LEFT JOIN public.custom_field_options cfo ON cfo.customfield_id = cf.id AND cfo.name = tcf.value
    WHERE 
        (p_start_date IS NULL OR DATE(NULLIF(t."start", '')::timestamptz) >= p_start_date)
        AND (p_end_date IS NULL OR DATE(NULLIF(t."start", '')::timestamptz) <= p_end_date)
        AND (p_user_filter IS NULL OR COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) ILIKE '%' || p_user_filter || '%')
        AND (p_client_filter IS NULL OR j.name ILIKE '%' || p_client_filter || '%')
        AND (p_project_filter IS NULL OR p.name ILIKE '%' || p_project_filter || '%')
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
        ARRAY_AGG(DISTINCT 
            CASE 
                WHEN utd.custom_field_option_name IS NOT NULL 
                THEN utd.jobcode_name || utd.custom_field_option_name
                WHEN utd.custom_field_value IS NOT NULL AND utd.custom_field_name IS NOT NULL
                THEN utd.jobcode_name || utd.custom_field_name || ':' || utd.custom_field_value
                ELSE NULL
            END
        ) FILTER (WHERE 
            (utd.custom_field_option_name IS NOT NULL) OR 
            (utd.custom_field_value IS NOT NULL AND utd.custom_field_name IS NOT NULL)
        ) AS task_custom_fields
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
    CASE WHEN p_sort_field='daily_average' AND p_sort_order='desc' THEN us.daily_average END DESC
LIMIT p_limit_count OFFSET p_offset_count;
$$ LANGUAGE sql STABLE;


select * from get_user_summary_simple_v5(10)