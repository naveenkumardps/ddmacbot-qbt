import requests
import json

url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_user_summary_simple_basic"

payload = json.dumps({
  "p_client_filter": None,
  "p_end_date": None,
  "p_limit_count": 10,
  "p_offset_count": 15,
  "p_project_filter": None,
  "p_sort_field": None,
  "p_sort_order": None,
  "p_start_date": None,
  "p_user_filter": None
})
headers = {
  'Content-Type': 'application/json',
  'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnZW5kbWdkcmxqdXh4eHl5bnB6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NjUyMzkxNywiZXhwIjoyMDcyMDk5OTE3fQ.tr0ZpJvPUZ7ySQLhxJTfV39ZYSEdruLBASv5bWfR1XE',
  'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnZW5kbWdkcmxqdXh4eHl5bnB6Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1NjUyMzkxNywiZXhwIjoyMDcyMDk5OTE3fQ.tr0ZpJvPUZ7ySQLhxJTfV39ZYSEdruLBASv5bWfR1XE'
}

response = requests.request("POST", url, headers=headers, data=payload)

print(response.text)
