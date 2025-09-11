from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomFieldModel import CustomFieldModel, CustomFieldItemsModel
from typing import Optional
import json


route = APIRouter(prefix="/customfield", tags=["CustomField"])

headers = {
    "Authorization": f"Bearer {BEARERTOKEN}",
}


@route.get("/")
async def getCustomfield():

    return headers
    url = QBTBASEURL + "/customfields"
    payload = ""

    response = requests.request("GET", url, data=payload, headers=headers)

    if response.status_code == 200:
        data = response.json()["results"]["customfields"]
        # Example: insert each custom field into the database using upsert structure
        for c, field in data.items():
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

    return response.text


@route.get("/custom-field-items")
async def customFielditems(
    customfield_id: int,
):
    # Build dict dynamically: only include non-None values
    querystring = {
        k: v
        for k, v in locals().items()
        if v is not None and k not in ["request"]  # filter out None
    }

    url = QBTBASEURL + "/customfielditems"

    response = requests.get(url, headers=headers, params=querystring)

    return response.json()


@route.post("/add-custom-field")
async def AddCustomField(request: CustomFieldModel):

    # payload = request
    payload = json.dumps({"data": [request.dict()]})
    url = QBTBASEURL + "/customfields"

    response = requests.post(url, data=payload, headers=headers)

    return response.text


@route.post("/add-custom-field-item")
async def AddCustomFieldItem(request: CustomFieldItemsModel):

    # payload = request
    payload = json.dumps({"data": [request.dict()]})
    url = QBTBASEURL + "/customfielditems"

    response = requests.post(url, data=payload, headers=headers)

    return response.text
