from fastapi import FastAPI,Request
from fastapi.responses import JSONResponse
from config.database import *
import Controller.AuthController, Controller.CustomerController, Controller.CustomeFieldController, Controller.TimesheetController, Controller.UserController


from config.config import *
import requests

app = FastAPI( title=APPNAME)

app.include_router(Controller.AuthController.route)
app.include_router(Controller.CustomerController.route)
app.include_router(Controller.CustomeFieldController.route)
app.include_router(Controller.TimesheetController.route)
app.include_router(Controller.UserController.route)




@app.get("/")
async def root():
    querystring = {
        "response_type":"code",
        "client_id":QBTCLINETID,
        "redirect_uri":"https://3301674d4b21.ngrok-free.app/callback",
        "state":"MYSTATE",
        }

    payload = ""
    headers = {
    }

    response = requests.request("GET", QBTBASEURL, data=payload, headers=headers, params=querystring)
    print(response)


@app.get("/callback")
async def callback(request: Request):
    code = request.query_params.get("code")
    state = request.query_params.get("state")

    data = {
            "code": code,
            "state": state
    }

    supabase_client.table("auth_tokens").insert(data).execute()

    
    # Do something with code and state...
    return JSONResponse({
        "code": code,
        "state": state
    })