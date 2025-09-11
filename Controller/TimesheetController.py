from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomerModel import CustomerModel

route = APIRouter(prefix="/timesheet", tags=["Timesheet"])
url = QBTBASEURL
headers = {"Authorization": f"Bearer {BEARERTOKEN}"}


@route.get("/")
async def getTimesheetlog(page: int = 1, count :int =0):

    return syncTimesheet(page, count)


def syncTimesheet(page, count):
    # 1. Get timesheet details
    ts_resp = requests.get(
        f"{url}/timesheets",
        headers=headers,
        params={"start_date": "2020-01-01", "page": page},
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
    

     # Insert each user into the database
    for user_id, user_info in users.items():
        count += 1

        def sanitize_date(date_str):
            if date_str in ("0000-00-00", "0000-00-00 00:00:00", "", None):
                return None
            return date_str

        customer = {
            "id": user_info.get("id"),
            "first_name": user_info.get("first_name"),
            "last_name": user_info.get("last_name"),
            "group_id": user_info.get("group_id"),
            "active": user_info.get("active"),
            "employee_number": user_info.get("employee_number"),
            "salaried": user_info.get("salaried"),
            "exempt": user_info.get("exempt"),
            "username": user_info.get("username"),
            "email": user_info.get("email"),
            "email_verified": user_info.get("email_verified"),
            "payroll_id": user_info.get("payroll_id"),
            "mobile_number": user_info.get("mobile_number"),
            "hire_date": sanitize_date(user_info.get("hire_date")),
            "term_date": sanitize_date(user_info.get("term_date")),
            "last_modified": sanitize_date(user_info.get("last_modified")),
            "last_active": sanitize_date(user_info.get("last_active")),
            "created": sanitize_date(user_info.get("created")),
            "client_url": user_info.get("client_url"),
            "company_name": user_info.get("company_name"),
            "profile_image_url": user_info.get("profile_image_url"),
            "display_name": user_info.get("display_name"),
            "pto_balances": user_info.get("pto_balances"),
            "submitted_to": user_info.get("submitted_to"),
            "approved_to": user_info.get("approved_to"),
            "manager_of_group_ids": user_info.get("manager_of_group_ids"),
            "require_password_change": user_info.get("require_password_change"),
            "pay_rate": user_info.get("pay_rate"),
            "pay_interval": user_info.get("pay_interval"),
            "permissions": user_info.get("permissions"),
            "customfields": user_info.get("customfields"),
        }
        supabase_client.table("users").upsert(customer).execute()

    # Insert each user into the database
    for user_info in jobcodes.values():
        count += 1

        def sanitize_date(date_str):
            if date_str in ("0000-00-00", "0000-00-00 00:00:00", "", None):
                return None
            return date_str

        jobcodes = {
            "id": user_info.get("id"),
            "parent_id": (
                None if user_info.get("parent_id") == 0 else user_info.get("parent_id")
            ),
            "assigned_to_all": user_info.get("assigned_to_all"),
            "billable": user_info.get("billable"),
            "active": user_info.get("active"),
            "type": user_info.get("type"),
            "has_children": user_info.get("has_children"),
            "billable_rate": user_info.get("billable_rate"),
            "short_code": user_info.get("short_code"),
            "name": user_info.get("name"),
            "last_modified": sanitize_date(user_info.get("last_modified")),
            "created": sanitize_date(user_info.get("created")),
            "filtered_customfielditems": user_info.get("filtered_customfielditems"),
            "connect_with_quickbooks": user_info.get("connect_with_quickbooks"),
        }
        # First, upsert the jobcode to ensure it exists for foreign key constraints
        supabase_client.table("jobcodes").upsert(jobcodes).execute()
        if user_info.get("required_customfields"):
            for customfield in user_info.get("required_customfields", []):
                jobcode_customfield = {
                    "jobcode_id": user_info.get("id"),
                    "customfield_id": (
                        customfield
                        if isinstance(customfield, int)
                        else customfield.get("id")
                    ),
                }
                supabase_client.table("jobcode_required_customfields").upsert(
                    jobcode_customfield
                ).execute()


        

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
    ## for Custome field
    for c, field in customfields.items():
            customfield_data = {
                "id": field.get("id"),
                "active": field.get("active", False),
                "required": field.get("required", False),
                "applies_to": field.get("applies_to"),
                "type": field.get("type"),
                "short_code": field.get("short_code"),
                "regex_filter": field.get("regex_filter"),
                "name": field.get("name"),
                "last_modified": field.get("last_modified"),
                "created": field.get("created"),
                "ui_preference": field.get("ui_preference"),
                "required_customfields": field.get("required_customfields", []),
                "show_to_all": field.get("show_to_all", False),
            }

            # Upsert the custom field using supabase_client
            supabase_client.table("custom_fields").upsert(customfield_data).execute()

            # Fetch custom field items for each custom field and insert into "custom_field_items" table
            item_querystring = {
                "customfield_id": field.get("id"),
            }
            item_url = QBTBASEURL + "/customfielditems"
            item_headers = {
                "Authorization": f"Bearer {BEARERTOKEN}",
            }
            item_response = requests.get(
                item_url, headers=item_headers, params=item_querystring
            )

            if item_response.status_code == 200:
                items_data = item_response.json()["results"]["customfielditems"]
                for t, item in items_data.items():
                    itemdata = {
                        "id": item.get("id"),
                        "customfield_id": item.get("customfield_id"),
                        "active": item.get("active", False),
                        "short_code": item_headers.get("short_code", ""),
                        "name": item.get("name"),
                        "last_modified": item.get("last_modified"),
                        "required_customfields": item.get("required_customfields", []),
                    }
                    supabase_client.table("custom_field_options").upsert(
                        itemdata
                    ).execute()

    if data.get("more"):
        page += 1
        return syncTimesheet(page, count)

    return {"status": "success", "count": count}


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
