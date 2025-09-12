from pydantic import BaseModel,field_validator
from typing import List, Optional


# ---------- Pydantic Models ----------
class UserSummary(BaseModel):
    username: Optional[str] = None
    user_id: Optional[int] = None
    total_hours: Optional[float] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    days_worked:Optional[int] = None
    daily_average: Optional[float] = None
    clients: Optional[List[str]] = None
    task_custom_fields: Optional[List[str]] = None

    @field_validator("total_hours", "daily_average", mode="before")
    def round_two_decimals(cls, v):
        if v is not None:
            return round(float(v), 2)
        return v

class PaginatedResponse(BaseModel):
    total: int
    limit: int
    offset: int
    page: int
    total_pages: int
    data: List[UserSummary]


class WeeklyHours(BaseModel):
    week_start: str
    week_end: str
    hours: float

    @field_validator("hours", mode="before")
    def round_two_decimals(cls, v):
        if v is not None:
            return round(float(v), 2)
        return v

class ProjectSummary(BaseModel):
    jobcode_name: str
    total_hours: float
    jobcode_start: str
    jobcode_end: str
    weekly_hours: List[WeeklyHours]

    @field_validator("total_hours", mode="before")
    def round_two_decimals(cls, v):
        if v is not None:
            return round(float(v), 2)
        return v

class PaginatedProjectResponse(BaseModel):
    total: int
    limit: int
    offset: int
    page: int
    total_pages: int
    data: List[ProjectSummary]