from fastapi import APIRouter, Query
import requests
from config.config import *
from config.database import *


route = APIRouter(prefix="/auth", tags=["Auth"])
url = QBTBASEURL + "/grant"


@route.get("/")
async def add_auth():

    payload = (
        "grant_type=authorization_code&client_id="
        + QBTCLINETID
        + "&client_secret="
        + QBTCLINETSECRET
        + "&code=S.6__8a369ce3d516841207a973a561b7c3df23826a99&redirect_uri=https://3301674d4b21.ngrok-free.app/callback"
    )
    headers = {}

    response = requests.request("POST", url, data=payload, headers=headers)

    if response.status_code == 200:
        token_data = response.json()
        supabase_client.table("auth_codes").insert(
            {
                "access_token": token_data.get("access_token"),
                "refresh_token": token_data.get("refresh_token"),
                "token_type": token_data.get("token_type"),
                "expires_in": token_data.get("expires_in"),
                "scope": token_data.get("scope"),
                "user_id": token_data.get("user_id"),
                "company_id": token_data.get("company_id"),
                "client_url": token_data.get("client_url"),
                "created_at": "now()",
                "updated_at": "now()",
            }
        ).execute()

    return response.json()


@route.get("/refreshToken")
async def refreshToken():
    data = supabase_client.table("auth_codes").select("*").execute()

    if data.data:
        last_record = data.data[-1]
        refresh_token = last_record["refresh_token"]

        payload = {
            "grant_type": "refresh_token",
            "client_id": "MYAPPCLIENTID",
            "client_secret": "MYAPPSECRET",
            "refresh_token": refresh_token,
        }

        payload = (
            "grant_type=refresh_token&client_id="
            + QBTCLINETID
            + "&client_secret="
            + QBTCLINETSECRET
            + "&refresh_token="
            + refresh_token
        )
        headers = {
            "Authorization": "Bearer " + last_record["access_token"],
            "Content-Type": "application/x-www-form-urlencoded",
        }

    response = requests.request("POST", url, data=payload, headers=headers)

    if response.status_code == 200:
        token_data = response.json()
        supabase_client.table("auth_codes").insert(
            {
                "access_token": token_data.get("access_token"),
                "refresh_token": token_data.get("refresh_token"),
                "token_type": token_data.get("token_type"),
                "expires_in": token_data.get("expires_in"),
                "scope": token_data.get("scope"),
                "user_id": token_data.get("user_id"),
                "company_id": token_data.get("company_id"),
                "client_url": token_data.get("client_url"),
                "created_at": "now()",
                "updated_at": "now()",
            }
        ).execute()

    return response.json()
