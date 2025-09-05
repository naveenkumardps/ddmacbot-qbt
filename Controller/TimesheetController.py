from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomerModel import CustomerModel

route = APIRouter(prefix="/timesheet", tags=["Timesheet"])
url = QBTBASEURL
headers = {"Authorization": f"Bearer {BEARERTOKEN}"}


@route.get("/")
async def getTimesheetlog(page: int = 1, count=0):

    return syncTimesheet(page, count)


def syncTimesheet(page, count):
    # 1. Get timesheet details
    ts_resp = requests.get(
        f"{url}/timesheets",
        headers=headers,
        params={"start_date": "2018-07-15", "page": page},
    )
    data = ts_resp.json()

    timesheets = data.get("results", {}).get("timesheets", {})
    jobcodes = data.get("supplemental_data", {}).get("jobcodes", {})
    users = data.get("supplemental_data", {}).get("users", {})
    customfields = data.get("supplemental_data", {}).get("customfields", {})

    inserted = {
        "timesheets": [],
        "users": [],
        "jobcodes": [],
        "customfields": [],
        "timesheet_customfields": [],
    }

    # 2. Upsert timesheets
    for ts_id, ts in timesheets.items():
        count += 1
        ts_data = {
            "id": int(ts["id"]),
            "user_id": int(ts["user_id"]),
            "jobcode_id": int(ts["jobcode_id"]),
            "start": ts["start"],
            "end": ts["end"],
            "duration": ts["duration"],
            "date": ts["date"],
            "tz": ts["tz"],
            "tz_str": ts["tz_str"],
            "type": ts["type"],
            "location": ts["location"],
            "on_the_clock": ts["on_the_clock"],
            "locked": ts["locked"],
            "notes": ts["notes"],
            "customfields": ts.get("customfields", {}),
            "last_modified": ts["last_modified"],
        }
        res = supabase_client.table("timesheets").upsert(ts_data).execute()
        inserted["timesheets"].append(res.data)

        # handle customfields for each timesheet
        for cf_id, value in ts.get("customfields", {}).items():
            cf_res = (
                supabase_client.table("timesheet_customfield_values")
                .upsert(
                    {
                        "timesheet_id": ts["id"],
                        "customfield_id": int(cf_id),
                        "value": value,
                    }
                )
                .execute()
            )
            inserted["timesheet_customfields"].append(cf_res.data)
        for fi, file in ts.get("files", {}).items():
            supabase_client.table("timesheet_files").upsert(
                {
                    "timesheet_id": ts["id"],
                    "file_id": int(fi),
                }
            ).execute()

    if data.json().get("more"):
        page += 1
        return syncTimesheet(page, count)

    return {"status": "success", "count": count}


@route.get("/syncFiles")
async def syncFiles():
    # 1. Get timesheet details
    files_resp = requests.get(
        f"{url}/files", headers=headers, params={"start_date": "2025-07-15"}
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
