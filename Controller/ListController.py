from fastapi import APIRouter, Query, Request,HTTPException
import requests
from config.config import *
from config.database import *
from Models.ListModel import *
from enum import Enum
import requests
import json

class SortOrder(str, Enum):
    asc = "asc"
    desc = "desc"

route = APIRouter(prefix="/api/v1", tags=["Listing"])
url = QBTBASEURL + "/jobcodes"


@route.get("/user-listing", response_model=PaginatedResponse)
async def user_listing(
    start_date: Optional[str] = Query(None, description="Start date YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="End date YYYY-MM-DD"),
    user_filter: Optional[str] = Query(None, description="Filter by username"),
    client_filter: Optional[str] = Query(None, description="Filter by client name"),
    sort_field: str = Query("username", description="Field to sort by"),
    sort_order: SortOrder = Query(SortOrder.asc, description="Sort order"),
    limit: int = Query(10, ge=1, le=100),  # Reduced limit
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    offset: Optional[int] = Query(None, ge=0, description="Offset (overrides page if provided)")
):
    # Calculate offset from page if not provided
    if offset is None:
        offset = (page - 1) * limit
    
    headers = {
        'Content-Type': 'application/json',
        'apikey': SUPABASE['SUPABASE_BEARER_TOKEN'],
        'Authorization': 'Bearer ' + SUPABASE['SUPABASE_BEARER_TOKEN']
    }
    total_count = 200
    # Get data
    data_url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_user_summary_simple_v5"
    data_payload = json.dumps({
               "p_start_date": None,
                "p_end_date": None,
                "p_user_filter": None,
                "p_client_filter": None,
                "p_sort_field": None,
                "p_sort_order": None,
                "p_limit_count": 10,
                "p_offset_count": 0,
    })

    data_response = requests.request("POST", data_url, headers=headers, data=data_payload)
    data = data_response.json() if data_response.status_code == 200 else []


    # Calculate pagination info
    total_pages = (total_count + limit - 1) // limit if total_count > 0 else 0
    current_page = (offset // limit) + 1

    return PaginatedResponse(
        total=total_count,
        limit=limit,
        offset=offset,
        page=current_page,
        total_pages=total_pages,
        data=data
    )


@route.get("/user-summary/{user_id}")
async def user_summary(
    user_id: int,
    period: str = "daily",
    client: str = Query(None),
    project: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
):
    rpc_name = "get_user_daily_timesheet_summary" if period == "daily" else "get_user_weekly_timesheet_summary"
    
    # Convert dates to proper format
    #  get_user_daily_timesheet_summary(123, '2025-12-01', '2025-12-31', 'Shlegel');
    params = {
        "p_user_id": user_id,
        "p_start_date": start_date,
        "p_end_date": end_date,
        "p_jobcode_filter": client
        
    }
    
    # Remove the debug return statement
    response = supabase_client.rpc(rpc_name, params).execute()
    return response.data


@route.get("/projects-summary", response_model=PaginatedProjectResponse)
async def get_projects_summary(
    jobcode_name: Optional[str] = Query(None, description="Filter by jobcode name"),
    start_date: Optional[str] = Query(None, description="Filter start date YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="Filter end date YYYY-MM-DD"),
    limit: int = Query(10, ge=1),
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    offset: Optional[int] = Query(None, ge=0, description="Offset (overrides page if provided)")
):
    # Calculate offset from page if not provided
    if offset is None:
        offset = (page - 1) * limit
    
    # Get count first
    count_response = supabase_client.rpc(
        "get_project_weekly_summary_count",
        {
            "p_jobcode_name": jobcode_name,
            "p_start_date": start_date,
            "p_end_date": end_date
        }
    ).execute()
    
    total_count = count_response.data if count_response.data else 0

    # Get data
    data_response = supabase_client.rpc(
        "get_project_weekly_summary_paginated",
        {
            "p_jobcode_name": jobcode_name,
            "p_start_date": start_date,
            "p_end_date": end_date,
            "p_limit": limit,
            "p_offset": offset
        }
    ).execute()

    # Calculate pagination info
    total_pages = (total_count + limit - 1) // limit if total_count > 0 else 0
    current_page = (offset // limit) + 1

    return PaginatedProjectResponse(
        total=total_count,
        limit=limit,
        offset=offset,
        page=current_page,
        total_pages=total_pages,
        data=data_response.data
    )