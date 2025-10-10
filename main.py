from fastapi import FastAPI, Request, Depends, HTTPException, Security
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from config.database import *
import Controller.AuthController, Controller.CustomerController, Controller.CustomeFieldController, Controller.TimesheetController, Controller.UserController, Controller.TaskController,Controller.ProjectController,Controller.ListController, Controller.UIController
from middleware.auth import AuthMiddleware
import os

from Controller.UserController import *
from Controller.CustomerController import *
from Controller.CustomeFieldController import *
from Controller.TimesheetController import *
from Controller.TaskController import *
from Controller.AuthController import *
from fastapi.security.api_key import APIKeyHeader
from starlette.status import HTTP_403_FORBIDDEN
from fastapi.openapi.utils import get_openapi
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from config.config import *
import requests
import datetime
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("app.log"),   # Save to file
        logging.StreamHandler()           # Show in console
    ]
)

app = FastAPI(title=APPNAME)

# Add authentication middleware
# app.add_middleware(AuthMiddleware, excluded_paths=[
#     "/login",
#     "/api/login", 
#     "/api/logout",
#     "/api/me",
#     "/api/dashboard-stats",
#     "/api/users-data",
#     "/api/user-listing-data", 
#     "/api/user-summary-data",
#     "/api/projects-data",
#     "/api/v1/client-time-summary",
#     "/api/v1/task-user-list",
#     "/api/v1/client-list",
#     "/api/v1/project-list",
#     "/api/v1/client-user-data",
#     "/api/v1/debug-duration-data",
#     "/api/v1/debug-office-data",
#     "/static",
#     "/docs",
#     "/openapi.json",
#     "/favicon.ico"
# ])

# Mount static files only if directory exists
if os.path.exists("static"):
    app.mount("/static", StaticFiles(directory="static"), name="static")
else:
    print("Warning: static directory not found. Creating it...")
    os.makedirs("static", exist_ok=True)
    os.makedirs("static/css", exist_ok=True)
    os.makedirs("static/js", exist_ok=True)
    os.makedirs("static/images", exist_ok=True)
    app.mount("/static", StaticFiles(directory="static"), name="static")

# Define API Key + Secret headers
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)

VALID_API_KEY = APIKEY

async def verify_credentials(api_key: str = Security(api_key_header)):
    if api_key != VALID_API_KEY:
        raise HTTPException(status_code=HTTP_403_FORBIDDEN, detail="Invalid API Key")
    return True

@app.middleware("http")
async def api_key_middleware(request: Request, call_next):
    # Allow docs, redoc, openapi.json, and UI routes without auth
    if request.url.path in ["/docs", "/redoc", "/openapi.json", "/", "/dashboard", "/login", "/users", "/user-listing", "/user-summary", "/projects", "/timesheets", "/customers", "/tasks", "/client-time-summary"] or request.url.path.startswith("/client-user-details/") or request.url.path.startswith("/api/dashboard-stats") or request.url.path.startswith("/api/users-data") or request.url.path.startswith("/api/user-listing-data") or request.url.path.startswith("/api/user-summary-data") or request.url.path.startswith("/api/projects-data") or request.url.path.startswith("/api/login") or request.url.path.startswith("/api/logout") or request.url.path.startswith("/api/me") or request.url.path.startswith("/api/v1/client-time-summary") or request.url.path.startswith("/api/v1/client-list") or request.url.path.startswith("/api/v1/project-list") or request.url.path.startswith("/api/v1/client-user-data") or request.url.path.startswith("/api/v1/debug-duration-data") or request.url.path.startswith("/api/v1/debug-office-data")  or request.url.path.startswith("/api/v1/task-user-list")    or request.url.path.startswith("/api/v1/task-estmate-list"):
        return await call_next(request)

    # Check headers for other endpoints
    api_key = request.headers.get("X-API-KEY")

    if not api_key:
        return JSONResponse(
            status_code=403,
            content={"detail": "Missing API Key"},
        )

    if api_key != VALID_API_KEY:
        return JSONResponse(status_code=403, content={"detail": "Invalid API Key"})

    return await call_next(request)

# Include UI routes (without authentication)
app.include_router(Controller.UIController.ui_route)

# Include client time summary routes (without authentication)
app.include_router(Controller.ListController.client_route)

# Include all your existing API routers with authentication
app.include_router(
    Controller.AuthController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.CustomerController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.CustomeFieldController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.TimesheetController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.UserController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.TaskController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.ProjectController.route, dependencies=[Depends(verify_credentials)]
)
app.include_router(
    Controller.ListController.route, dependencies=[Depends(verify_credentials)]
)

# Your existing task function
def daily_task():
    print("Running daily task at 5 PM:", datetime.datetime.now())

# Start scheduler when app starts
@app.on_event("startup")
def start_scheduler():
    scheduler = BackgroundScheduler()
    # Run daily at 5 PM
    scheduler.add_job(getUser, CronTrigger(hour=16, minute=0))
    scheduler.add_job(getCustomer, CronTrigger(hour=16, minute=10))
    scheduler.add_job(getCustomfield, CronTrigger(hour=16, minute=15))
    scheduler.add_job(getTimesheetlog, CronTrigger(hour=17, minute=0))
    scheduler.add_job(syncFiles, CronTrigger(hour=17, minute=5))
    scheduler.start()

# Your existing API routes
@app.get("/api/auth")
async def auth_endpoint():
    querystring = {
        "response_type": "code",
        "client_id": QBTCLINETID,
        "redirect_uri": "https://3301674d4b21.ngrok-free.app/callback",
        "state": "MYSTATE",
    }

    payload = ""
    headers = {}

    response = requests.request(
        "GET", QBTBASEURL, data=payload, headers=headers, params=querystring
    )
    print(response)

@app.get("/callback")
async def callback(request: Request):
    code = request.query_params.get("code")
    state = request.query_params.get("state")

    data = {"code": code, "state": state}

    supabase_client.table("auth_tokens").insert(data).execute()

    return JSONResponse({"code": code, "state": state})