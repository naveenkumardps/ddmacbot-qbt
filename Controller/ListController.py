from fastapi import APIRouter, Query, Request, HTTPException
import requests
from config.config import *
from config.database import *
from Models.ListModel import *
from enum import Enum
import requests
import json
from typing import Optional
from datetime import datetime

class SortOrder(str, Enum):
    asc = "asc"
    desc = "desc"

route = APIRouter(prefix="/api/v1", tags=["Listing"])
# Create a separate router for client time summary without authentication
client_route = APIRouter(prefix="/api/v1", tags=["Client Time Summary"])
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
               "p_start_date": start_date,
                "p_end_date": end_date,
                "p_user_filter": user_filter,
                "p_client_filter": client_filter,
                "p_sort_field": sort_field,
                "p_sort_order": sort_order.value,
                "p_limit_count": limit,
                "p_offset_count": offset,
    })

    try:
        data_response = requests.request("POST", data_url, headers=headers, data=data_payload)
        if data_response.status_code == 200:
            data = data_response.json()
        else:
            print(f"DEBUG - API request failed with status {data_response.status_code}: {data_response.text}")
            data = []
    except requests.RequestException as e:
        print(f"DEBUG - Request error: {e}")
        data = []


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


# Client Time Summary endpoints (without authentication)
@client_route.get("/client-time-summary")
async def get_client_time_summary(
    client_name: str = Query(None, description="Filter by client name"),
    project_name: str = Query(None, description="Filter by project name"),
    start_date: str = Query(None, description="Filter start date YYYY-MM-DD"),
    end_date: str = Query(None, description="Filter end date YYYY-MM-DD"),
    limit: int = Query(10, ge=1),
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    offset: Optional[int] = Query(None, ge=0, description="Offset (overrides page if provided)")
):
    # Calculate offset from page if not provided
    if offset is None:
        offset = (page - 1) * limit
    
    try:

        timesheet_query = supabase_client.rpc('get_project_timsheet_summary_v1')
        
        # Get all data (increase limit to ensure we get all records)
        timesheet_data = timesheet_query.execute()
        return {
            "total":len(timesheet_data.data),
            "limit":limit,
            "offset":offset,
            "page":0,
            "total_pages":0,
            "data":timesheet_data.data
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching client time summary: {str(e)}")


@client_route.get("/client-list")
async def get_client_list():
    """Get list of clients for dropdown"""
    try:
        response = supabase_client.table('jobcodes').select('name').eq('active', True).order('name').execute()
        
        # Format response to match expected structure
        client_list = [{'client_name': item['name']} for item in response.data]
        
        return client_list
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching client list: {str(e)}")


@client_route.get("/project-list")
async def get_project_list():
    """Get list of projects for dropdown"""
    try:
        response = supabase_client.table('projects').select('name').eq('active', True).order('name').execute()
        
        # Format response to match expected structure
        project_list = [{'project_name': item['name']} for item in response.data]
        
        return project_list
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error fetching project list: {str(e)}")


@client_route.get("/client-user-data/{jobcode_id}")
async def get_client_user_data(
    jobcode_id: int,
    user_id: int = None,
    period: str = "daily",
    limit: int = Query(10, ge=1),
    page: int = Query(1, ge=1, description="Page number (1-based)"),
    offset: Optional[int] = Query(None, ge=0, description="Offset (overrides page if provided)")
):
    """Get user-wise data for a specific client by jobcode ID"""
    # Calculate offset from page if not provided
    if offset is None:
        offset = (page - 1) * limit
    
    try:
        
        if user_id is None:
            rpc_name = "get_timesheet_summary_by_jobcode_paginated"
            params = {
                "jobcode_id_input": jobcode_id,
                "limit_count": 1000,
                "offset_count": offset
            }
        else:
            rpc_name = "get_timesheet_summary_by_jobcode_daily" if period == "daily" else "get_timesheet_summary_by_jobcode_weekly"
            params = {
                "jobcode_id_input": jobcode_id,
                "user_id_input": user_id,
                "limit_count": 1000,
                "offset_count": offset
            }
        timesheet_query = supabase_client.rpc(rpc_name,params)

   
            
        # Get all data (no limit to ensure we get all records)
        timesheet_data = timesheet_query.execute()
        
       
        
        return {
            "total": len(timesheet_data.data),
            "limit": limit,
            "offset": offset,
            "page": page,
            "total_pages": page,
            "data": timesheet_data.data,
        }
        
        
    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise
    except Exception as e:
        print(f"DEBUG - Unexpected error in get_client_user_data: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error fetching client user data: {str(e)}")