from fastapi import APIRouter, Query,Request
import requests
from config.config import *
from config.database import *
from Models.CustomerModel import CustomerModel



route = APIRouter(prefix="/customer", tags=["Customer"])
url = QBTBASEURL + "/jobcodes"


 

@route.get("/")
async def getCustomer(page: int = 1,count=0):
    
    return syncCustomer(page,count)
    


def syncCustomer(page,count):
    querystring = {
        "page":page
        }
    payload = ""
    headers = {
    'Authorization': "Bearer "+BEARERTOKEN,
    }
    response = requests.request("GET", url, data=payload, headers=headers, params=querystring)

    data = response.json()['results']['jobcodes']

    # Insert each user into the database
    for user_info in data.values():
        count+=1
        def sanitize_date(date_str):
            if date_str in ("0000-00-00", "0000-00-00 00:00:00", "", None):
                return None
            return date_str

        jobcodes = {
            "id": user_info.get("id"),
            "parent_id": None if user_info.get("parent_id") == 0 else user_info.get("parent_id"),
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
                    "customfield_id": customfield if isinstance(customfield, int) else customfield.get("id")
                }
                supabase_client.table("jobcode_required_customfields").upsert(jobcode_customfield).execute()

    if response.json().get('more'):
        page += 1
        return syncCustomer(page, count)
    
    return count


