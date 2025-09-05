import os
from dotenv import load_dotenv

# Base directory of the project
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Load .env from the root directory
load_dotenv(os.path.join(BASE_DIR, "../.env"))

# Now you can use these directly
MONGO = {"MONGO_URL": os.getenv("MONGO_URL"), "MONGO_DB": os.getenv("MONGO_DB")}

SUPABASE = {
    "SUPABASE_URL": os.getenv("SUPABASE_URL"),
    "SUPABASE_API_KEY": os.getenv("SUPABASE_API_KEY"),
    "SUPABASE_KEY": os.getenv("SUPABASE_KEY"),
}


DB_CONNECTION = os.getenv("DB_CONNECTION")
APPNAME = os.getenv("APPNAME")

QBTBASEURL = os.getenv("QBTBASEURL")
QBTCLINETID = os.getenv("QBTCLINETID")
QBTCLINETSECRET = os.getenv("QBTCLINETSECRET")

APIKEY = os.getenv("X-API-KEY")
