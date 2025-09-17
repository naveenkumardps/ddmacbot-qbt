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

# Client Time Summary Models
class ClientTimeSummary(BaseModel):
    client_name: str
    jobcode_id: int
    total_hours: float
    client_start_date: Optional[str] = None
    client_end_date: Optional[str] = None
    total_users: int
    total_count: int

    @field_validator("total_hours", mode="before")
    def round_two_decimals(cls, v):
        if v is not None:
            return round(float(v), 2)
        return v

class PaginatedClientTimeResponse(BaseModel):
    total: int
    limit: int
    offset: int
    page: int
    total_pages: int
    data: List[ClientTimeSummary]

# Dropdown Models
class ClientOption(BaseModel):
    client_name: str

class ProjectOption(BaseModel):
    project_name: str

# Client User Data Models
class ClientUserData(BaseModel):
    user_id: int
    username: str
    total_hours: float
    user_start_date: Optional[str] = None
    user_end_date: Optional[str] = None
    days_worked: int
    avg_hours_per_day: float
    projects: Optional[List[str]] = []
    project_hours: Optional[dict] = {}  # Dictionary of project_name: hours
    total_count: int

    @field_validator("total_hours", "avg_hours_per_day", mode="before")
    def round_two_decimals(cls, v):
        if v is not None:
            return round(float(v), 2)
        return v

    @field_validator("projects", mode="before")
    def handle_none_projects(cls, v):
        if v is None:
            return []
        return v

class PaginatedClientUserResponse(BaseModel):
    total: int
    limit: int
    offset: int
    page: int
    total_pages: int
    data: List[ClientUserData]