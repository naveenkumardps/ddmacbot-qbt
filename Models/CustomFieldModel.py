from pydantic import BaseModel
from typing import Optional
from fastapi import Query

class CustomFieldModel(BaseModel):
    customfield_id: int = Query(..., description="Id of the custom field whose items you'd like to list"),
    ids: Optional[str] = Query(None, description="Comma separated list of customfielditem ids"),
    active: str = Query("yes", regex="^(yes|no|both)$", description="'yes', 'no', or 'both'. Default is 'yes'"),
    name: Optional[str] = Query(None, description="Wildcard supported. Matches from beginning of string."),
    modified_before: Optional[str] = Query(None, description="ISO 8601 date (YYYY-MM-DDThh:mm:ss±hh:mm)"),
    modified_since: Optional[str] = Query(None, description="ISO 8601 date (YYYY-MM-DDThh:mm:ss±hh:mm)"),
    supplemental_data: str = Query("yes", regex="^(yes|no)$", description="'yes' or 'no'. Default is 'yes'"),
    per_page: Optional[int] = Query(None, description="Deprecated. Max=50"),
    limit: int = Query(200, ge=1, le=200, description="Results per request. Default=200. Max=200"),
    page: Optional[int] = Query(1, description="Page number, for pagination")
    

