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
@client_route.get("/client-time-summary", response_model=PaginatedClientTimeResponse)
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
        # Build WHERE conditions
        where_conditions = [
            "t.start is not null",
            "t.\"end\" is not null"
        ]
        params = {}
        
        if start_date:
            where_conditions.append("nullif(t.start, '')::date >= :start_date")
            params['start_date'] = start_date
            
        if end_date:
            where_conditions.append("nullif(t.\"end\", '')::date <= :end_date")
            params['end_date'] = end_date
            
        if client_name:
            where_conditions.append("j.name ilike :client_filter")
            params['client_filter'] = f'%{client_name}%'
            
        if project_name:
            where_conditions.append("p.name ilike :project_filter")
            params['project_filter'] = f'%{project_name}%'

        where_clause = " AND ".join(where_conditions)
        
        # Use direct table queries instead of raw SQL
        # First get all timesheet data with filters
        timesheet_query = supabase_client.table('timesheets').select("""
            user_id,
            duration,
            start,
            end,
            jobcode_id,
            jobcodes!inner(name)
        """)
        
        # Apply filters
        if start_date:
            timesheet_query = timesheet_query.gte('start', start_date)
        if end_date:
            timesheet_query = timesheet_query.lte('end', end_date)
        if client_name:
            timesheet_query = timesheet_query.ilike('jobcodes.name', f'%{client_name}%')
            
        # Get all data (increase limit to ensure we get all records)
        timesheet_data = timesheet_query.limit(10000).execute()
        
        if not timesheet_data.data:
            return PaginatedClientTimeResponse(
                total=0,
                limit=limit,
                offset=offset,
                page=1,
                total_pages=0,
                data=[]
            )
        
        # Get projects data separately for filtering
        projects_data = {}
        if project_name:
            # Only get projects data when project filter is applied
            projects_query = supabase_client.table('projects').select('id, name, jobcode_id').ilike('name', f'%{project_name}%')
            projects_response = projects_query.execute()
            projects_data = {proj['jobcode_id']: proj['name'] for proj in projects_response.data}
        
        # Process data in Python
        client_summary = {}
        debug_total_hours = 0
        
        for record in timesheet_data.data:
            jobcode = record.get('jobcodes', {})
            
            if not jobcode or not jobcode.get('name'):
                continue
                
            client_name_val = jobcode['name']
            jobcode_id = record.get('jobcode_id')
            
            # Apply project filtering only if project filter is specified
            if project_name:
                if jobcode_id not in projects_data:
                    continue
                project_name_val = projects_data.get(jobcode_id)
            else:
                project_name_val = None
            
            # Calculate hours
            duration = record.get('duration')
            start_time = record.get('start')
            end_time = record.get('end')
            
            if duration and duration > 0:
                # Duration is in seconds, convert to hours
                hours = duration / 3600.0
            elif start_time and end_time:
                try:
                    start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                    end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
                    hours = (end_dt - start_dt).total_seconds() / 3600.0
                except (ValueError, TypeError) as e:
                    print(f"DEBUG - Error parsing datetime: {e}")
                    hours = 0
            else:
                hours = 0
                
            if client_name_val not in client_summary:
                client_summary[client_name_val] = {
                    'client_name': client_name_val,
                    'jobcode_id': jobcode_id,
                    'total_hours': 0,
                    'client_start_date': None,
                    'client_end_date': None,
                    'total_users': set(),
                    'total_count': 0
                }
            
            client_summary[client_name_val]['total_hours'] += hours
            client_summary[client_name_val]['total_users'].add(record['user_id'])
            debug_total_hours += hours
            
            # Update dates
            if start_time:
                work_date = start_time.split('T')[0]
                if not client_summary[client_name_val]['client_start_date'] or work_date < client_summary[client_name_val]['client_start_date']:
                    client_summary[client_name_val]['client_start_date'] = work_date
                    
            if end_time:
                end_date = end_time.split('T')[0]
                if not client_summary[client_name_val]['client_end_date'] or end_date > client_summary[client_name_val]['client_end_date']:
                    client_summary[client_name_val]['client_end_date'] = end_date
        
        # Convert to list and sort
        total_count = len(client_summary)
        
        for client_data in client_summary.values():
            client_data['total_users'] = len(client_data['total_users'])
            client_data['total_hours'] = round(client_data['total_hours'], 2)
            client_data['total_count'] = total_count
        
        # Debug logging
        print(f"DEBUG - Client Time Summary - Total hours processed: {debug_total_hours}")
        print(f"DEBUG - Client Time Summary - Total records processed: {len(timesheet_data.data)}")
        for client_name, data in client_summary.items():
            print(f"DEBUG - Client: {client_name} (ID: {data['jobcode_id']}), Hours: {data['total_hours']}, Users: {data['total_users']}")
            if data['jobcode_id'] == 39280750:
                print(f"DEBUG - YEE HONG DETAILS - Hours: {data['total_hours']}, Users: {data['total_users']}")
        
        client_list = list(client_summary.values())
        client_list.sort(key=lambda x: x['total_hours'], reverse=True)
        
        # Apply pagination
        start_idx = offset
        end_idx = offset + limit
        paginated_data = client_list[start_idx:end_idx]
        
        # Calculate pagination info
        total_pages = (total_count + limit - 1) // limit if total_count > 0 else 0
        current_page = (offset // limit) + 1
        
        return PaginatedClientTimeResponse(
            total=total_count,
            limit=limit,
            offset=offset,
            page=current_page,
            total_pages=total_pages,
            data=paginated_data
        )
        
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


@client_route.get("/debug-duration-data")
async def get_debug_duration_data():
    """Debug endpoint to check duration data using the provided SQL query"""
    try:
        # Get timesheet data with duration and jobcode info
        timesheet_data = supabase_client.table('timesheets').select("""
            jobcode_id,
            duration,
            jobcodes!inner(name)
        """).not_.is_('duration', 'null').gt('duration', 0).limit(1000).execute()
        
        # Process and aggregate the data
        jobcode_totals = {}
        for record in timesheet_data.data:
            jobcode_id = record['jobcode_id']
            duration = record['duration']
            jobcode_name = record['jobcodes']['name']
            
            if jobcode_id not in jobcode_totals:
                jobcode_totals[jobcode_id] = {
                    'jobcode_id': jobcode_id,
                    'name': jobcode_name,
                    'total_duration': 0,
                    'record_count': 0
                }
            
            jobcode_totals[jobcode_id]['total_duration'] += duration
            jobcode_totals[jobcode_id]['record_count'] += 1
        
        # Convert to list and sort by total_duration
        result_data = list(jobcode_totals.values())
        result_data.sort(key=lambda x: x['total_duration'], reverse=True)
        
        return {
            "query": "Processed timesheet data with duration aggregation",
            "data": result_data[:100],  # Limit to 100 records
            "total_records": len(result_data),
            "yee_hong_data": [item for item in result_data if item['jobcode_id'] == 39280750]
        }
        
    except Exception as e:
        return {
            "error": str(e),
            "query": "Failed to process data"
        }

@client_route.get("/debug-office-data/{jobcode_id}")
async def get_debug_office_data(jobcode_id: int):
    """Debug endpoint to check Office data using the exact SQL query provided"""
    try:
        # Use the exact SQL query provided by the user
        timesheet_data = supabase_client.table('timesheets').select("""
            jobcode_id,
            duration,
            user_id
        """).eq('jobcode_id', jobcode_id).execute()
        
        # Process the data exactly like the SQL query
        user_totals = {}
        total_duration = 0
        
        for record in timesheet_data.data:
            user_id = record['user_id']
            duration = record['duration']
            
            if user_id not in user_totals:
                user_totals[user_id] = 0
            user_totals[user_id] += duration
            total_duration += duration
        
        # Convert to list format
        result_data = []
        for user_id, duration in user_totals.items():
            result_data.append({
                'jobcode_id': jobcode_id,
                'user_id': user_id,
                'duration': duration,
                'hours': duration / 3600.0
            })
        
        # Sort by duration descending
        result_data.sort(key=lambda x: x['duration'], reverse=True)
        
        return {
            "query": f"SELECT jobcode_id,sum(duration) as duration,user_id FROM timesheets WHERE jobcode_id = {jobcode_id} GROUP BY jobcode_id,user_id",
            "total_duration_seconds": total_duration,
            "total_duration_hours": total_duration / 3600.0,
            "user_count": len(result_data),
            "data": result_data
        }
        
    except Exception as e:
        return {
            "error": str(e),
            "query": "Failed to process data"
        }


@client_route.get("/client-user-data/{jobcode_id}")
async def get_client_user_data(
    jobcode_id: int,
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
        rpc_name = "get_timesheet_summary_by_jobcode_daily" if period == "daily" else "get_timesheet_summary_by_jobcode_weekly"
        timesheet_query = supabase_client.rpc(rpc_name,{
            "jobcode_id_input": jobcode_id,
            "limit_count": 1000,
            "offset_count": offset
        })

   
            
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