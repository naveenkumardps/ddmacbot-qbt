from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomFieldModel import CustomFieldModel, CustomFieldItemsModel
from typing import Optional
import json


route = APIRouter(prefix="/projects", tags=["Projects"])

headers = {
    "Authorization": f"Bearer {BEARERTOKEN}",
}


@route.get("/")
async def getProjects():
    url = QBTBASEURL + "/projects"
    payload = ""

    response = requests.request("GET", url, data=payload, headers=headers)

    if response.status_code == 200:
        data = response.json()["results"]["projects"]
        # Example: insert each custom field into the database using upsert structure
        for c, field in data.items():
            project_data = {
                "id": field.get("id"),
                "active": field.get("active", False),

                "parent_jobcode_id": field.get("parent_jobcode_id"),
                "jobcode_id": field.get("jobcode_id"),
                "status": field.get("status"),
              
                "name": field.get("name"),
                "description": field.get("description"),
                "start_date": field.get("start_date"),
                "due_date": field.get("due_date"),
                "completed_date": field.get("completed_date"),
                "last_modified": field.get("last_modified"),
                "created": field.get("created"),
                "linked_objects": field.get("linked_objects", [])
            }

            # Upsert the custom field using supabase_client
            supabase_client.table("projects").upsert(project_data).execute()

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

    return response.text