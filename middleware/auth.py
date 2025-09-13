from fastapi import Request, HTTPException, status
from fastapi.responses import RedirectResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response
import jwt
import time
from datetime import datetime, timedelta
from config.config import AUTH
import json

class AuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, excluded_paths=None):
        super().__init__(app)
        self.excluded_paths = excluded_paths or [
            "/login",
            "/api/login",
            "/api/logout",
            "/static",
            "/docs",
            "/openapi.json",
            "/favicon.ico"
        ]
    
    def is_excluded_path(self, path: str) -> bool:
        """Check if the path should be excluded from authentication"""
        for excluded in self.excluded_paths:
            if path.startswith(excluded):
                return True
        
        # Also exclude API routes that require API key authentication
        # These should be handled by the API key middleware instead
        if path.startswith("/api/v1/"):
            return True
            
        return False
    
    def create_token(self, username: str) -> str:
        """Create JWT token for authenticated user"""
        payload = {
            "username": username,
            "exp": datetime.utcnow() + timedelta(hours=AUTH["SESSION_EXPIRE_HOURS"]),
            "iat": datetime.utcnow()
        }
        return jwt.encode(payload, AUTH["SESSION_SECRET_KEY"], algorithm="HS256")
    
    def verify_token(self, token: str) -> dict:
        """Verify JWT token and return payload"""
        try:
            payload = jwt.decode(token, AUTH["SESSION_SECRET_KEY"], algorithms=["HS256"])
            return payload
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expired")
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=401, detail="Invalid token")
    
    def authenticate_user(self, username: str, password: str) -> bool:
        """Authenticate user against environment variables"""
        return (username == AUTH["ADMIN_USERNAME"] and 
                password == AUTH["ADMIN_PASSWORD"])
    
    async def dispatch(self, request: Request, call_next):
        # Skip authentication for excluded paths
        if self.is_excluded_path(request.url.path):
            response = await call_next(request)
            return response
        
        # Check for authentication token
        token = None
        
        # Try to get token from Authorization header
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
        
        # Try to get token from cookies
        if not token:
            token = request.cookies.get("auth_token")
        
        # If no token, redirect to login
        if not token:
            if request.url.path.startswith("/api/"):
                return Response(
                    content=json.dumps({"error": "Authentication required"}),
                    status_code=401,
                    media_type="application/json"
                )
            else:
                return RedirectResponse(url="/login", status_code=302)
        
        # Verify token
        try:
            payload = self.verify_token(token)
            # Add user info to request state
            request.state.user = payload
        except HTTPException as e:
            if request.url.path.startswith("/api/"):
                return Response(
                    content=json.dumps({"error": e.detail}),
                    status_code=e.status_code,
                    media_type="application/json"
                )
            else:
                return RedirectResponse(url="/login", status_code=302)
        
        # Process the request
        response = await call_next(request)
        
        # Add token to response cookies if it's a successful request
        if response.status_code < 400:
            response.set_cookie(
                key="auth_token",
                value=token,
                max_age=AUTH["SESSION_EXPIRE_HOURS"] * 3600,
                httponly=True,
                secure=False,  # Set to True in production with HTTPS
                samesite="lax"
            )
        
        return response

def get_current_user(request: Request) -> dict:
    """Get current authenticated user from request state"""
    if not hasattr(request.state, 'user'):
        raise HTTPException(status_code=401, detail="Not authenticated")
    return request.state.user
