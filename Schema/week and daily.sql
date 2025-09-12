-- Daily breakdown function - shows custom field values as tasks
CREATE OR REPLACE FUNCTION get_user_daily_tasks(
    p_user_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    work_date DATE,
    client_name TEXT,
    task_name TEXT,
    hours_worked NUMERIC
) AS $$
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
$$ LANGUAGE sql STABLE;

-- Weekly breakdown function - shows custom field values as tasks
CREATE OR REPLACE FUNCTION get_user_weekly_tasks(
    p_user_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    week_start DATE,
    week_end DATE,
    client_name TEXT,
    task_name TEXT,
    hours_worked NUMERIC
) AS $$
WITH weekly_data AS (
    SELECT
        DATE_TRUNC('week', t.start::timestamptz)::DATE AS week_start,
        (DATE_TRUNC('week', t.start::timestamptz) + INTERVAL '6 days')::DATE AS week_end,
        j.name AS client_name,
        COALESCE(tcf.value, 'No Task') AS task_name,
        EXTRACT(EPOCH FROM (t."end"::timestamptz - t.start::timestamptz))/3600.0 AS hours
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
)
SELECT
    wd.week_start,
    wd.week_end,
    wd.client_name,
    wd.task_name,
    ROUND(SUM(wd.hours), 2) AS hours_worked
FROM weekly_data wd
GROUP BY wd.week_start, wd.week_end, wd.client_name, wd.task_name
ORDER BY wd.week_start DESC, wd.client_name, wd.task_name;
$$ LANGUAGE sql STABLE;

-- Alternative version that shows all timesheet entries (including those without custom fields)
CREATE OR REPLACE FUNCTION get_user_daily_tasks_all(
    p_user_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    work_date DATE,
    client_name TEXT,
    task_name TEXT,
    hours_worked NUMERIC
) AS $$
SELECT
    DATE(t.start::timestamptz) AS work_date,
    j.name AS client_name,
    CASE 
        WHEN tcf.value IS NOT NULL AND tcf.value != '' THEN tcf.value
        WHEN t.notes IS NOT NULL AND t.notes != '' THEN t.notes
        ELSE 'No Task'
    END AS task_name,
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
ORDER BY work_date DESC, j.name, task_name;
$$ LANGUAGE sql STABLE;

-- Test queries
-- SELECT * FROM get_user_daily_tasks(2012419, '2020-01-01', '2025-12-31');
-- SELECT * FROM get_user_weekly_tasks(2012419, '2020-01-01', '2025-12-31');
-- SELECT * FROM get_user_daily_tasks_all(2012419, '2020-01-01', '2025-12-31');