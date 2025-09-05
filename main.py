from fastapi import FastAPI, Request, Depends, HTTPException, Security
from fastapi.responses import JSONResponse
from config.database import *
import Controller.AuthController, Controller.CustomerController, Controller.CustomeFieldController, Controller.TimesheetController, Controller.UserController, Controller.TaskController
from fastapi.security.api_key import APIKeyHeader
from starlette.status import HTTP_403_FORBIDDEN
from fastapi.openapi.utils import get_openapi

from config.config import *
import requests

app = FastAPI(title=APPNAME)


# Define API Key + Secret headers
api_key_header = APIKeyHeader(name="X-API-KEY", auto_error=False)

VALID_API_KEY = APIKEY


async def verify_credentials(api_key: str = Security(api_key_header)):
    if api_key != VALID_API_KEY:
        raise HTTPException(status_code=HTTP_403_FORBIDDEN, detail="Invalid API Key")

    return True


@app.middleware("http")
async def api_key_middleware(request: Request, call_next):
    # allow docs, redoc, and openapi.json without auth
    if request.url.path in ["/docs", "/redoc", "/openapi.json"]:
        return await call_next(request)

    # check headers for other endpoints
    api_key = request.headers.get("X-API-KEY")

    if not api_key:
        return JSONResponse(
            status_code=403,
            content={"detail": "Missing API Key"},
        )

    if api_key != VALID_API_KEY:
        return JSONResponse(status_code=403, content={"detail": "Invalid API Key"})

    # ✅ pass request forward if valid
    return await call_next(request)


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


@app.get("/")
async def root():
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

    # Do something with code and state...
    return JSONResponse({"code": code, "state": state})
