from fastapi import APIRouter, Query,Request,File, UploadFile,Body
import requests
from config.config import *
from config.database import *
from fastapi.responses import JSONResponse
import pandas as pd
from typing import List, Dict, Any





route = APIRouter(prefix="/task", tags=["Task"])
url = QBTBASEURL 
headers = {"Authorization": f"Bearer {BEARERTOKEN}"}


@route.post("/")
async def parseFile(file: UploadFile = File(...)):
       # Save uploaded file
    contents = await file.read()
    with open(file.filename, "wb") as f:
        f.write(contents)
    
    # Parse Excel
    xls = pd.ExcelFile(file.filename)
    sheet_names = xls.sheet_names
    
    sheets_data = {}
    if sheet == "JobInfo": 
        df = xls.parse(sheet, header=None)
        jobinfo_dict = dict(zip(df[0], df[1]))
        jobinfo_dict = {k: (None if pd.isna(v) else str(v)) for k, v in jobinfo_dict.items() if pd.notnull(k)}
        sheets_data[sheet] = jobinfo_dict
    else:
        for sheet in sheet_names:
            df = xls.parse(sheet)
            df = df.where(pd.notnull(df), None)
            for col in df.select_dtypes(include=["datetime", "datetimetz"]).columns:
                df[col] = df[col].astype(str)
            df = df.replace({float("nan"): None, float("inf"): None, -float("inf"): None})
            if  sheet == "Breakdown":
                sheets_data[sheet] = df.to_dict(orient="records")  
    
    return {
        "filename": file.filename,
        "sheets": sheets_data
    }


@route.post("/parseJson")
async def parseJson(data: List[Dict[str, Any]] = Body(...)) :
    # data = await request.json()
    return data
