import os
import psycopg
from dotenv import load_dotenv

load_dotenv() # reads .env into os.environ on import

def connect() -> psycopg.Connection:
    """
    Open a connection to the project's Postgres DB.

    Reads a DATABASE_URL from in the environment (set in .env).
    Caller is responsible for closing the connection (use 'with').
    """
    url = os.environ["DATABASE_URL"]
    return psycopg.connect(url)
