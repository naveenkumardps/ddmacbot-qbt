CREATE OR REPLACE FUNCTION public.get_project_weekly_summary(
    p_jobcode_name TEXT DEFAULT NULL,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    jobcode_name TEXT,
    total_hours NUMERIC,
    jobcode_start TIMESTAMPTZ,
    jobcode_end TIMESTAMPTZ,
    weekly_hours JSONB
) AS $$
WITH project_weeks AS (
    SELECT
        j.name AS jobcode_name,
        DATE_TRUNC('week', t.start::timestamptz)::DATE AS week_start,
        DATE_TRUNC('week', t.start::timestamptz)::DATE + interval '6 days' AS week_end,
        SUM(EXTRACT(EPOCH FROM (t."end"::timestamptz - t.start::timestamptz)) / 3600.0) AS hours
    FROM timesheets t
    JOIN jobcodes j ON j.id = t.jobcode_id
    WHERE t.start IS NOT NULL AND t.start <> ''
      AND t."end" IS NOT NULL AND t."end" <> ''
      AND (p_jobcode_name IS NULL OR j.name ILIKE '%' || p_jobcode_name || '%')
      AND (p_start_date IS NULL OR t.start::date >= p_start_date)
      AND (p_end_date IS NULL OR t.start::date <= p_end_date)
    GROUP BY j.name, week_start
),

project_totals AS (
    SELECT
        j.name AS jobcode_name,
        SUM(EXTRACT(EPOCH FROM (t."end"::timestamptz - t.start::timestamptz)) / 3600.0) AS total_hours,
        MIN(t.start::timestamptz) AS jobcode_start,
        MAX(t."end"::timestamptz) AS jobcode_end
    FROM timesheets t
    JOIN jobcodes j ON j.id = t.jobcode_id
    WHERE t.start IS NOT NULL AND t.start <> ''
      AND t."end" IS NOT NULL AND t."end" <> ''
      AND (p_jobcode_name IS NULL OR j.name ILIKE '%' || p_jobcode_name || '%')
      AND (p_start_date IS NULL OR t.start::date >= p_start_date)
      AND (p_end_date IS NULL OR t.start::date <= p_end_date)
    GROUP BY j.name
)

SELECT
    pt.jobcode_name,
    pt.total_hours,
    pt.jobcode_start,
    pt.jobcode_end,
    jsonb_agg(
        jsonb_build_object(
            'week_start', pw.week_start,
            'week_end', pw.week_end,
            'hours', pw.hours
        ) ORDER BY pw.week_start
    ) AS weekly_hours
FROM project_totals pt
LEFT JOIN project_weeks pw ON pt.jobcode_name = pw.jobcode_name
GROUP BY pt.jobcode_name, pt.total_hours, pt.jobcode_start, pt.jobcode_end
ORDER BY pt.jobcode_name;
$$ LANGUAGE sql STABLE;