from pydantic import BaseModel,Field
from typing import Optional
from fastapi import Query

class CustomFieldModel(BaseModel):
    name: str
    required: bool = Field(default=True)   # always True
    active: bool = Field(default=True)     # always True
    applies_to: str
    type: str
    show_to_all: bool = Field(default=False) 
    short_code: str


class CustomFieldItemsModel(BaseModel):
    
    name: str
    customfield_id: int
    short_code: str
