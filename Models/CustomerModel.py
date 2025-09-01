from pydantic import BaseModel

class CustomerModel(BaseModel):
    parent_id: int
    assigned_to_all: bool = False
    billable: bool
    active: bool = True
    type:str = "regular"
    short_code: str
    name: str
    

