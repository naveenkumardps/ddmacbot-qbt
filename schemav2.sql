CREATE OR REPLACE FUNCTION get_user_summaries_v2(
    limit_count INT,
    offset_count INT,
    username_filter TEXT DEFAULT NULL,
    project_filter TEXT DEFAULT NULL,
    jobcode_filter TEXT DEFAULT NULL,
    sort_field TEXT DEFAULT 'username',
    sort_order TEXT DEFAULT 'asc'
)
RETURNS TABLE (
    user_id INT,
    username TEXT,
    total_hours NUMERIC,
    days_worked INT,
    avg_hours_per_day NUMERIC,
    jobcodes TEXT[],
    projects TEXT[]
) AS $$
WITH user_entries AS (
    SELECT 
        t.id,
        t.user_id,
        COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) AS username,
        NULLIF(t."start", '')::timestamptz AS start_ts,
        NULLIF(t."end", '')::timestamptz   AS end_ts,
        EXTRACT(EPOCH FROM (NULLIF(t."end", '')::timestamptz - NULLIF(t."start", '')::timestamptz))/3600.0 AS hours,
        t.jobcode_id
    FROM public.timesheets t
    JOIN public.users u ON u.id = t.user_id
),
summary AS (
    SELECT 
        ue.user_id,
        ue.username,
        SUM(ue.hours)::numeric AS total_hours,
        COUNT(DISTINCT DATE(ue.start_ts)) AS days_worked,
        ARRAY_AGG(DISTINCT j.name) FILTER (WHERE j.name IS NOT NULL) AS jobcodes,
        ARRAY_AGG(DISTINCT p.name) FILTER (WHERE p.name IS NOT NULL) AS projects
    FROM user_entries ue
    LEFT JOIN public.jobcodes j ON j.id = ue.jobcode_id
    LEFT JOIN public.projects p ON p.jobcode_id = ue.jobcode_id
    WHERE
        (username_filter IS NULL OR ue.username ILIKE '%' || username_filter || '%')
        AND (project_filter IS NULL OR p.name = project_filter)
        AND (jobcode_filter IS NULL OR j.name = jobcode_filter)
    GROUP BY ue.user_id, ue.username
)
SELECT
    s.user_id,
    s.username,
    s.total_hours,
    s.days_worked,
    ROUND(s.total_hours / NULLIF(s.days_worked,0), 2) AS avg_hours_per_day,
    s.jobcodes,
    s.projects
FROM summary s
ORDER BY
    CASE WHEN sort_field='username' AND sort_order='asc' THEN s.username END ASC,
    CASE WHEN sort_field='username' AND sort_order='desc' THEN s.username END DESC,
    CASE WHEN sort_field='total_hours' AND sort_order='asc' THEN s.total_hours END ASC,
    CASE WHEN sort_field='total_hours' AND sort_order='desc' THEN s.total_hours END DESC
LIMIT limit_count OFFSET offset_count;
$$ LANGUAGE sql STABLE;




CREATE OR REPLACE FUNCTION get_user_summaries_v2(
    limit_count INT,
    offset_count INT,
    username_filter TEXT DEFAULT NULL,
    project_filter TEXT DEFAULT NULL,
    jobcode_filter TEXT DEFAULT NULL,
    sort_field TEXT DEFAULT 'username',
    sort_order TEXT DEFAULT 'asc'
)
RETURNS TABLE (
    user_id INT,
    username TEXT,
    total_hours NUMERIC,
    days_worked INT,
    avg_hours_per_day NUMERIC,
    jobcodes TEXT[],
    projects TEXT[]
) AS $$
WITH user_entries AS (
    SELECT 
        t.id,
        t.user_id,
        COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) AS username,
        NULLIF(t."start", '')::timestamptz AS start_ts,
        NULLIF(t."end", '')::timestamptz   AS end_ts,
        EXTRACT(EPOCH FROM (NULLIF(t."end", '')::timestamptz - NULLIF(t."start", '')::timestamptz))/3600.0 AS hours,
        t.jobcode_id
    FROM public.timesheets t
    JOIN public.users u ON u.id = t.user_id
),
summary AS (
    SELECT 
        ue.user_id,
        ue.username,
        SUM(ue.hours)::numeric AS total_hours,
        COUNT(DISTINCT DATE(ue.start_ts)) AS days_worked,
        ARRAY_AGG(DISTINCT j.name) FILTER (WHERE j.name IS NOT NULL) AS jobcodes,
        ARRAY_AGG(DISTINCT p.name) FILTER (WHERE p.name IS NOT NULL) AS projects
    FROM user_entries ue
    LEFT JOIN public.jobcodes j ON j.id = ue.jobcode_id
    LEFT JOIN public.projects p ON p.jobcode_id = ue.jobcode_id
    WHERE
        (username_filter IS NULL OR ue.username ILIKE '%' || username_filter || '%')
        AND (project_filter IS NULL OR p.name = project_filter)
        AND (jobcode_filter IS NULL OR j.name = jobcode_filter)
    GROUP BY ue.user_id, ue.username
)
SELECT
    s.user_id,
    s.username,
    s.total_hours,
    s.days_worked,
    ROUND(s.total_hours / NULLIF(s.days_worked,0), 2) AS avg_hours_per_day,
    s.jobcodes,
    s.projects
FROM summary s
ORDER BY
    CASE WHEN sort_field='username' AND sort_order='asc' THEN s.username END ASC,
    CASE WHEN sort_field='username' AND sort_order='desc' THEN s.username END DESC,
    CASE WHEN sort_field='total_hours' AND sort_order='asc' THEN s.total_hours END ASC,
    CASE WHEN sort_field='total_hours' AND sort_order='desc' THEN s.total_hours END DESC
LIMIT limit_count OFFSET offset_count;
$$ LANGUAGE sql STABLE;




CREATE OR REPLACE FUNCTION get_user_summaries_v3(
    limit_count INT,
    offset_count INT,
    username_filter TEXT DEFAULT NULL,
    project_filter TEXT DEFAULT NULL,
    jobcode_filter TEXT DEFAULT NULL,
    sort_field TEXT DEFAULT 'username',
    sort_order TEXT DEFAULT 'asc'
)
RETURNS TABLE (
    user_id INT,
    username TEXT,
    total_hours NUMERIC,
    days_worked INT,
    avg_hours_per_day NUMERIC,
    jobcodes TEXT[],
    projects TEXT[]
) AS $$
WITH user_entries AS (
    SELECT 
        t.id,
        t.user_id,
        COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) AS username,
        NULLIF(t."start", '')::timestamptz AS start_ts,
        NULLIF(t."end", '')::timestamptz AS end_ts,
        EXTRACT(EPOCH FROM (NULLIF(t."end", '')::timestamptz - NULLIF(t."start", '')::timestamptz))/3600.0 AS hours,
        t.jobcode_id,
        j.name AS jobcode_name,
        p.name AS project_name
    FROM public.timesheets t
    JOIN public.users u ON u.id = t.user_id
    LEFT JOIN public.jobcodes j ON j.id = t.jobcode_id
    LEFT JOIN public.projects p ON p.jobcode_id = j.id
    WHERE
       (username_filter IS NULL OR COALESCE(u.username, TRIM(u.first_name || ' ' || u.last_name)) ILIKE '%' || username_filter || '%')
        AND (project_filter IS NULL OR p.name ILIKE '%' || project_filter || '%')
        AND (jobcode_filter IS NULL OR j.name ILIKE '%' || jobcode_filter || '%')
),
summary AS (
    SELECT 
        ue.user_id,
        ue.username,
        ROUND(SUM(ue.hours)::numeric, 2) AS total_hours,
        COUNT(DISTINCT DATE(ue.start_ts)) AS days_worked,
        ARRAY_AGG(DISTINCT ue.jobcode_name) FILTER (WHERE ue.jobcode_name IS NOT NULL) AS jobcodes,
        ARRAY_AGG(DISTINCT ue.project_name) FILTER (WHERE ue.project_name IS NOT NULL) AS projects
    FROM user_entries ue
    GROUP BY ue.user_id, ue.username
)
SELECT
    s.user_id,
    s.username,
    s.total_hours,
    s.days_worked,
    ROUND(s.total_hours / NULLIF(s.days_worked, 0), 2) AS avg_hours_per_day,
    s.jobcodes,
    s.projects
FROM summary s
ORDER BY
    CASE WHEN sort_field='username' AND sort_order='asc' THEN s.username END ASC,
    CASE WHEN sort_field='username' AND sort_order='desc' THEN s.username END DESC,
    CASE WHEN sort_field='total_hours' AND sort_order='asc' THEN s.total_hours END ASC,
    CASE WHEN sort_field='total_hours' AND sort_order='desc' THEN s.total_hours END DESC
LIMIT limit_count OFFSET offset_count;
$$ LANGUAGE sql STABLE;
