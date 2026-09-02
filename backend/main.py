from contextlib import asynccontextmanager
from fastapi import FastAPI
from database import create_db_and_tables
import models

@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield

app = FastAPI(title="Gameday Pick'em API", lifespan=lifespan)

@app.get("/health")

def health():
    return {"status": "ok"}