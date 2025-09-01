from motor.motor_asyncio import AsyncIOMotorClient
from config.config import MONGO,DB_CONNECTION,SUPABASE
from supabase import create_client, Client






# MongoDB client
if(DB_CONNECTION == 'mongodb'):
    client = AsyncIOMotorClient(MONGO['MONGO_URL'])
    db = client[MONGO['MONGO_DB']]

if(DB_CONNECTION == 'mysql'):
    pass

if(DB_CONNECTION == 'supabase'):
    supabase_client = Client = create_client(SUPABASE['SUPABASE_URL'], SUPABASE['SUPABASE_KEY'])
    data = supabase_client.table("auth_codes").select("*").execute()

    if data.data:
        last_record = data.data[-1]
        BEARERTOKEN = last_record["access_token"]

