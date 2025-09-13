from fastapi import APIRouter, Request, Query, Form, HTTPException, Depends
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from config.database import *
from config.config import AUTH
from middleware.auth import AuthMiddleware, get_current_user
import requests
import json
import jwt
from datetime import datetime, timedelta

# Setup templates
templates = Jinja2Templates(directory="templates")

# Create router for UI routes with prefix
ui_route = APIRouter( tags=["UI"])

# Authentication helper functions
def create_token(username: str) -> str:
    """Create JWT token for authenticated user"""
    payload = {
        "username": username,
        "exp": datetime.utcnow() + timedelta(hours=AUTH["SESSION_EXPIRE_HOURS"]),
        "iat": datetime.utcnow()
    }
    return jwt.encode(payload, AUTH["SESSION_SECRET_KEY"], algorithm="HS256")

def authenticate_user(username: str, password: str) -> bool:
    """Authenticate user against environment variables"""
    return (username == AUTH["ADMIN_USERNAME"] and 
            password == AUTH["ADMIN_PASSWORD"])

@ui_route.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {
        "request": request, 
        "title": "QB Times Dashboard"
    })

@ui_route.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    """Login page"""
    return templates.TemplateResponse("login.html", {
        "request": request, 
        "title": "Login"
    })

@ui_route.get("/users", response_class=HTMLResponse)
async def users_page(request: Request):
    """Users management page"""
    return templates.TemplateResponse("users.html", {
        "request": request, 
        "title": "Users Management"
    })

@ui_route.get("/projects", response_class=HTMLResponse)
async def projects_page(request: Request):
    """Projects management page"""
    return templates.TemplateResponse("projects.html", {
        "request": request, 
        "title": "Projects Management"
    })

@ui_route.get("/timesheets", response_class=HTMLResponse)
async def timesheets_page(request: Request):
    """Timesheets page"""
    return templates.TemplateResponse("timesheets.html", {
        "request": request, 
        "title": "Timesheets"
    })

@ui_route.get("/customers", response_class=HTMLResponse)
async def customers_page(request: Request):
    """Customers management page"""
    return templates.TemplateResponse("customers.html", {
        "request": request, 
        "title": "Customers Management"
    })

@ui_route.get("/tasks", response_class=HTMLResponse)
async def tasks_page(request: Request):
    """Tasks management page"""
    return templates.TemplateResponse("tasks.html", {
        "request": request, 
        "title": "Tasks Management"
    })

@ui_route.get("/user-listing", response_class=HTMLResponse)
async def user_listing_page(request: Request):
    """User listing page with detailed table"""
    return templates.TemplateResponse("user-listing.html", {
        "request": request, 
        "title": "User Listing - Detailed View"
    })

@ui_route.get("/user-summary", response_class=HTMLResponse)
async def user_summary_page(request: Request):
    """User summary page with weekly/daily summary"""
    return templates.TemplateResponse("user-summary.html", {
        "request": request, 
        "title": "User Summary"
    })

# Authentication endpoints
@ui_route.post("/api/login")
async def login(
    username: str = Form(...),
    password: str = Form(...)
):
    """Login endpoint for authentication"""
    if authenticate_user(username, password):
        token = create_token(username)
        response = JSONResponse({
            "success": True,
            "message": "Login successful",
            "user": {"username": username}
        })
        response.set_cookie(
            key="auth_token",
            value=token,
            max_age=AUTH["SESSION_EXPIRE_HOURS"] * 3600,
            httponly=True,
            secure=False,  # Set to True in production with HTTPS
            samesite="lax"
        )
        return response
    else:
        raise HTTPException(
            status_code=401,
            detail="Invalid username or password"
        )

@ui_route.post("/api/logout")
async def logout():
    """Logout endpoint"""
    response = JSONResponse({
        "success": True,
        "message": "Logout successful"
    })
    response.delete_cookie(key="auth_token")
    return response

@ui_route.get("/api/me")
async def get_current_user_info(request: Request):
    """Get current user information"""
    try:
        # Get token from cookies
        token = request.cookies.get("auth_token")
        if not token:
            raise HTTPException(status_code=401, detail="Not authenticated")
        
        # Verify token
        payload = jwt.decode(token, AUTH["SESSION_SECRET_KEY"], algorithms=["HS256"])
        return {
            "success": True,
            "user": {
                "username": payload["username"]
            }
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

# API endpoints for UI data (without authentication for UI)
@ui_route.get("/api/dashboard-stats")
async def get_dashboard_stats():
    """Get dashboard statistics for UI using the same structure as ListController"""
    try:
        # Get user count - using the same structure as ListController
        count_url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_user_summary_count"
        count_payload = json.dumps({
            "p_client_filter": None,
            "p_end_date": None,
            "p_start_date": None,
            "p_user_filter": None
        })
        headers = {
            'Content-Type': 'application/json',
            'apikey': SUPABASE['SUPABASE_BEARER_TOKEN'],
            'Authorization': 'Bearer ' + SUPABASE['SUPABASE_BEARER_TOKEN']
        }

        count_response = requests.request("POST", count_url, headers=headers, data=count_payload)
        user_count = count_response.json() if count_response.status_code == 200 else 0
        
        # Get project count - using similar structure
        project_count_url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_project_weekly_summary_count"
        project_count_payload = json.dumps({
            "p_jobcode_name": None,
            "p_start_date": None,
            "p_end_date": None
        })

        project_count_response = requests.request("POST", project_count_url, headers=headers, data=project_count_payload)
        project_count = project_count_response.json() if project_count_response.status_code == 200 else 0
        
        return {
            "total_users": user_count,
            "active_projects": project_count,
            "week_hours": 156.5,  # You can calculate this from your data
            "pending_tasks": 8     # You can calculate this from your data
        }
    except Exception as e:
        return {
            "total_users": 0,
            "active_projects": 0,
            "week_hours": 0,
            "pending_tasks": 0,
            "error": str(e)
        }

@ui_route.get("/api/users-data")
async def get_users_data(
    start_date: str = None,
    end_date: str = None,
    user_filter: str = None,
    client_filter: str = None,
    limit: int = 10,
    page: int = 1
):
    """Get users data for UI table using the same structure as ListController"""
    try:
        offset = (page - 1) * limit
        
        # Using the same structure as ListController
        # Get data
        headers = {
            'Content-Type': 'application/json',
            'apikey': SUPABASE['SUPABASE_BEARER_TOKEN'],
            'Authorization': 'Bearer ' + SUPABASE['SUPABASE_BEARER_TOKEN']
            }
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
        
        return {
            "data": data,
            "success": True
        }
    except Exception as e:
        return {
            "data": [],
            "success": False,
            "error": str(e)
        }

@ui_route.get("/api/user-listing-data")
async def get_user_listing_data(
    start_date: str = None,
    end_date: str = None,
    user_filter: str = None,
    client_filter: str = None,
    sort_field: str = "username",
    sort_order: str = "asc",
    limit: int = 20,
    page: int = 1
):
    """Get detailed user listing data for UI table using the same structure as ListController"""
    try:
        # Calculate offset from page
        offset = (page - 1) * limit
        
        # Get count first - using the same structure as ListController
      
        headers = {
            'Content-Type': 'application/json',
            'apikey': SUPABASE['SUPABASE_BEARER_TOKEN'],
            'Authorization': 'Bearer ' + SUPABASE['SUPABASE_BEARER_TOKEN']
        }

        total_count = 200

        # Get data - using the same structure as ListController
        data_url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_user_summary_simple_v5"
        data_payload = json.dumps({
             "p_start_date": start_date,
                    "p_end_date": end_date,
                    "p_user_filter": user_filter,
                    "p_client_filter": client_filter,
                    "p_sort_field": None,
                    "p_sort_order": None,
                    "p_limit_count": limit,
                    "p_offset_count": offset,
        })

        data_response = requests.request("POST", data_url, headers=headers, data=data_payload)
        data = data_response.json() if data_response.status_code == 200 else []

        # Calculate pagination info
        total_pages = (total_count + limit - 1) // limit if total_count > 0 else 0
        current_page = (offset // limit) + 1
        
        return {
            "data": data,
            "pagination": {
                "total": total_count,
                "limit": limit,
                "offset": offset,
                "page": current_page,
                "total_pages": total_pages
            },
            "success": True
        }
    except Exception as e:
        return {
            "data": [],
            "pagination": {
                "total": 0,
                "limit": limit,
                "offset": 0,
                "page": 1,
                "total_pages": 0
            },
            "success": False,
            "error": str(e)
        }

@ui_route.get("/api/projects-data")
async def get_projects_data(
    jobcode_name: str = None,
    start_date: str = None,
    end_date: str = None,
    limit: int = 10,
    page: int = 1
):
    """Get projects data for UI table using the same structure as ListController"""
    try:
        offset = (page - 1) * limit
        
        # Using the same structure as ListController
        data_url = "https://tgendmgdrljuxxxyynpz.supabase.co/rest/v1/rpc/get_project_weekly_summary_paginated"
        data_payload = json.dumps({
            "p_jobcode_name": jobcode_name,
            "p_start_date": start_date,
            "p_end_date": end_date,
            "p_limit": limit,
            "p_offset": offset
        })
        headers = {
            'Content-Type': 'application/json',
            'apikey': SUPABASE['SUPABASE_BEARER_TOKEN'],
            'Authorization': 'Bearer ' + SUPABASE['SUPABASE_BEARER_TOKEN']
        }

        data_response = requests.request("POST", data_url, headers=headers, data=data_payload)
        data = data_response.json() if data_response.status_code == 200 else []
        
        return {
            "data": data,
            "success": True
        }
    except Exception as e:
        return {
            "data": [],
            "success": False,
            "error": str(e)
        }
        

@ui_route.get("/api/user-summary-data")
async def get_user_summary_data(
    user_id: int,
    limit: int = 20,
    page: int = 1,
    period: str = "daily",
    client: str = None,
    start_date: str = Query(None),
    end_date: str = Query(None),
):
    """Get user summary data (weekly or daily) with pagination"""
    offset = (page - 1) * limit

    try:
        rpc_name = "get_user_daily_timesheet_summary" if period == "daily" else "get_user_weekly_timesheet_summary"
        
        # Get paginated data
        params = {
            "p_user_id": user_id,
            "p_start_date": start_date,
            "p_end_date": end_date,
            "p_jobcode_filter": client,
            "p_limit": limit,
            "p_offset": offset
        }
        
        response = supabase_client.rpc(rpc_name, params).execute()
        data = response.data if response.data else []
        
        # For now, we'll estimate total count based on returned data
        # In production, you'd want a separate count RPC
        total_count = len(data) + offset
        if len(data) == limit:
            total_count += 1  # Indicate there might be more data
        
        # Calculate pagination info
        total_pages = (total_count + limit - 1) // limit if total_count > 0 else 0
        current_page = (offset // limit) + 1

        return {
            "data": data,
            "pagination": {
                "total": total_count,
                "limit": limit,
                "offset": offset,
                "page": current_page,
                "total_pages": total_pages,
                "has_next": current_page < total_pages,
                "has_prev": current_page > 1
            },
            "success": True
        }

    except Exception as e:
        return {
            "data": [],
            "pagination": {
                "total": 0,
                "limit": limit,
                "offset": 0,
                "page": 1,
                "total_pages": 0,
                "has_next": False,
                "has_prev": False
            },
            "success": False,
            "error": str(e)
        }

