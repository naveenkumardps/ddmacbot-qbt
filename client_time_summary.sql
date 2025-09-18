CREATE OR REPLACE FUNCTION get_timesheet_summary_by_jobcode_weekly(
    jobcode_id_input BIGINT,
    user_id_input BIGINT DEFAULT NULL,
    limit_count INT DEFAULT 50,
    offset_count INT DEFAULT 0
)
RETURNS TABLE (
    week_start DATE,
    user_id BIGINT,
    username TEXT,
    jobcode_id BIGINT,
    total_duration NUMERIC,
     start_date TEXT,
    end_date TEXT,
    days_worked BIGINT
) AS $$
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
$$ LANGUAGE plpgsql STABLE;



CREATE OR REPLACE FUNCTION get_timesheet_summary_by_jobcode_daily(
     jobcode_id_input BIGINT,
    user_id_input BIGINT DEFAULT NULL,
    limit_count INT DEFAULT 50,
    offset_count INT DEFAULT 0
)
RETURNS TABLE (
    work_date DATE,
    user_id BIGINT,
    username TEXT,
    jobcode_id BIGINT,
     start_date TEXT,
    end_date TEXT,
    total_duration NUMERIC
) AS $$
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
$$ LANGUAGE plpgsql STABLE;


select * from get_timesheet_summary_by_jobcode_weekly(25538423, 2521428,100, 0);



CREATE OR REPLACE FUNCTION get_timesheet_summary_by_jobcode_paginated(
    jobcode_id_input BIGINT,
    limit_count INT DEFAULT 50,
    offset_count INT DEFAULT 0
)
RETURNS TABLE (
    user_id BIGINT,
    username TEXT,
    jobcode_id BIGINT,
    total_duration NUMERIC,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.user_id,
        u.username,
        t.jobcode_id,
        SUM(t.duration) AS total_duration,
        MIN(NULLIF(t.start, '')::timestamptz) AS start_date,
        MAX(NULLIF(t."end", '')::timestamptz) AS end_date
    FROM timesheets AS t
    LEFT JOIN users AS u ON u.id = t.user_id
    WHERE t.jobcode_id = jobcode_id_input
    GROUP BY t.user_id, u.username, t.jobcode_id
    ORDER BY total_duration DESC
    LIMIT limit_count OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE;





CREATE OR REPLACE FUNCTION get_project_timsheet_summary_v1(
    limit_count INT DEFAULT 1000,
    offset_count INT DEFAULT 0
)
RETURNS TABLE (
    name TEXT,
    jobcode_id BIGINT,
    total_duration NUMERIC,
     start_date TEXT,
    end_date TEXT,
    days_worked BIGINT
) AS $$
BEGIN
    RETURN QUERY
    select u.name,t.jobcode_id, ROUND(SUM(t.duration) / 3600.0, 2) AS total_duration, MIN(t.start) AS start_date,
        MAX(t."end") AS end_date, COUNT(DISTINCT DATE(NULLIF(t.start, '')::timestamptz)) AS days_worked  FROM timesheets AS t LEFT JOIN jobcodes AS u ON u.id = t.jobcode_id
        GROUP BY    t.jobcode_id,u.name
    LIMIT limit_count OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE;



CREATE OR REPLACE FUNCTION get_project_summary()
RETURNS TABLE (
    project_id BIGINT,
    project_name TEXT,
    project_start DATE,
    project_end DATE,
    list_users TEXT[]
) AS $$
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
$$ LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION get_jobcode_summary()
RETURNS TABLE (
    jobcode_id BIGINT,
    jobcode_name TEXT,
    jobcode_start DATE,
    jobcode_end DATE,
    list_users TEXT[]
) AS $$
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
$$ LANGUAGE plpgsql STABLE;
