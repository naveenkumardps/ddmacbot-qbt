CREATE OR REPLACE FUNCTION get_user_daily_summary(
    p_user_id BIGINT,
    p_client_filter TEXT DEFAULT NULL,
    p_project_filter TEXT DEFAULT NULL,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    day DATE,
    client TEXT,
    project TEXT,
    hours NUMERIC
) AS $$
SELECT
    DATE(t.start::timestamptz) AS day,
    j.name AS client,
    p.name AS project,
    ROUND(SUM(EXTRACT(EPOCH FROM (t."end"::timestamptz - t.start::timestamptz))/3600.0), 2) AS hours
FROM timesheets t
JOIN jobcodes j ON j.id = t.jobcode_id
LEFT JOIN projects p ON p.jobcode_id = j.id
WHERE t.user_id = p_user_id
  AND (p_client_filter IS NULL OR j.name ILIKE '%' || p_client_filter || '%')
  AND (p_project_filter IS NULL OR p.name ILIKE '%' || p_project_filter || '%')
  AND (p_start_date IS NULL OR DATE(t.start::timestamptz) >= p_start_date)
  AND (p_end_date IS NULL OR DATE(t.start::timestamptz) <= p_end_date)
GROUP BY DATE(t.start::timestamptz), j.name, p.name
ORDER BY DATE(t.start::timestamptz), j.name, p.name;
$$ LANGUAGE sql STABLE;


CREATE OR REPLACE FUNCTION get_user_weekly_summary(
    p_user_id BIGINT,
    p_client_filter TEXT DEFAULT NULL,
    p_project_filter TEXT DEFAULT NULL,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    week_start DATE,
    client TEXT,
    project TEXT,
    hours NUMERIC
) AS $$
WITH week_dates AS (
    SELECT
        t.*,
        DATE_TRUNC('week', t.start::timestamptz)::DATE AS week_start
    FROM timesheets t
    WHERE t.user_id = p_user_id
      AND (p_start_date IS NULL OR DATE(t.start::timestamptz) >= p_start_date)
      AND (p_end_date IS NULL OR DATE(t.start::timestamptz) <= p_end_date)
)
SELECT
    w.week_start,
    j.name AS client,
    p.name AS project,
    ROUND(SUM(EXTRACT(EPOCH FROM (w."end"::timestamptz - w.start::timestamptz))/3600.0), 2) AS hours
FROM week_dates w
JOIN jobcodes j ON j.id = w.jobcode_id
LEFT JOIN projects p ON p.jobcode_id = j.id
WHERE (p_client_filter IS NULL OR j.name ILIKE '%' || p_client_filter || '%')
  AND (p_project_filter IS NULL OR p.name ILIKE '%' || p_project_filter || '%')
GROUP BY w.week_start, j.name, p.name
ORDER BY w.week_start, j.name, p.name;
$$ LANGUAGE sql STABLE;
