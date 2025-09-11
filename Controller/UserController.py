from fastapi import APIRouter, Query, Request
import requests
from config.config import *
from config.database import *
from Models.CustomerModel import CustomerModel

route = APIRouter(prefix="/user", tags=["User"])
url = QBTBASEURL
headers = {"Authorization": f"Bearer {BEARERTOKEN}"}


@route.get("/")
async def getUser(page: int = 1, count:int=0):

    return syncUser(page, count)


def syncUser(page, count):
    payload = ""
    querystring = {"page": page}
    user_response = requests.get(
        f"{url}/users", headers=headers, data=payload, params=querystring
    )
    data = user_response.json()



    users = data['results']['users']

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
    if data['more']:
        page += 1
        return syncUser(page, count)
    return {"count": count}
