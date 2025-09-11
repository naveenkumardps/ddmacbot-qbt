from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomerModel import CustomerModel
import time

route = APIRouter(prefix="/timesheet", tags=["Timesheet"])
url = QBTBASEURL
headers = {"Authorization": f"Bearer {BEARERTOKEN}"}


@route.get("/")
async def getTimesheetlog(page: int = 1, count :int =0):

    return syncTimesheet(page, count)


def syncTimesheet(page, count):
    start_time = time.time()
    try:
        max_pages = 1000
        delay_seconds = 2

        while True:
            ts_resp = requests.get(
                f"{url}/timesheets",
                headers=headers,
                params={"start_date": "2020-01-01", "page": page},
            )
            data = ts_resp.json()

            inserted_count = process_page(data)
            count += inserted_count

            # Stop if no more pages
            if not data.get("more") or page >= max_pages:
                break

            page += 1
            time.sleep(delay_seconds)

        elapsed = time.time() - start_time
        return {"status": "success", "count": count, "elapsed_seconds": elapsed}

    except Exception as e:
        elapsed = time.time() - start_time
        return {"status": "error", "message": str(e), "count": count, "elapsed_seconds": elapsed}



@route.get("/syncFiles")
async def syncFiles():
    # 1. Get timesheet details
    files_resp = requests.get(
        f"{url}/files", headers=headers, params={"start_date": "2020-01-01"}
    )
    data = files_resp.json()
    files = data.get("results", {}).get("files", {})
    for ts_id, fil in files.items():
        fs_data = {
            "id": int(fil["id"]),
            "uploaded_by_user_id": (
                int(fil["uploaded_by_user_id"])
                if fil.get("uploaded_by_user_id")
                else None
            ),
            "file_name": fil["file_name"],
            "active": fil.get("active", True),
            "size": int(fil["size"]) if fil.get("size") else None,
            "last_modified": fil.get("last_modified"),
            "created": fil.get("created"),
            "file_description": fil.get("file_description", ""),
        }

        supabase_client.table("files").upsert(fs_data).execute()

def process_page(data):
    """Process one page of data and upsert into Supabase"""

    timesheets = data.get("results", {}).get("timesheets", {})
    jobcodes = data.get("supplemental_data", {}).get("jobcodes", {})
    users = data.get("supplemental_data", {}).get("users", {})
    customfields = data.get("supplemental_data", {}).get("customfields", {})

    # ---- Users ----
    users_list = []
    for _, user_info in users.items():
        users_list.append({
            "id": user_info.get("id"),
            "first_name": user_info.get("first_name"),
            "last_name": user_info.get("last_name"),
            "active": user_info.get("active"),
            "email": user_info.get("email"),
            # ... (trim down fields or keep all if your schema allows)
        })
    if users_list:
        supabase_client.table("users").upsert(users_list).execute()

    # ---- Jobcodes ----
    jobcodes_list = []
    for _, jc in jobcodes.items():
        jobcodes_list.append({
            "id": jc.get("id"),
            "name": jc.get("name"),
            "active": jc.get("active"),
            "last_modified": jc.get("last_modified"),
        })
    if jobcodes_list:
        supabase_client.table("jobcodes").upsert(jobcodes_list).execute()

    # ---- Custom Fields ----
    custom_fields_list = []
    for _, field in customfields.items():
        custom_fields_list.append({
            "id": field.get("id"),
            "name": field.get("name"),
            "active": field.get("active", False),
        })
    if custom_fields_list:
        supabase_client.table("custom_fields").upsert(custom_fields_list).execute()

    # ---- Timesheets ----
    timesheets_list = []
    for _, ts in timesheets.items():
        timesheets_list.append({
            "id": int(ts["id"]),
            "user_id": int(ts["user_id"]),
            "jobcode_id": int(ts["jobcode_id"]),
            "start": ts["start"],
            "end": ts["end"],
            "date": ts["date"],
            "last_modified": ts["last_modified"],
        })
    if timesheets_list:
        supabase_client.table("timesheets").upsert(timesheets_list).execute()

    return len(timesheets)
