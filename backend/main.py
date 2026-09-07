from datetime import datetime, timezone
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select
from database import create_db_and_tables, get_session
from models import Game, User
from auth import hash_password, verify_password, create_token, get_current_user
import models
import cfbd


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="Gameday Pick'em API", lifespan=lifespan)


class Credentials(BaseModel):
    username: str
    password: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/register")
def register(creds: Credentials, session: Session = Depends(get_session)):
    existing = session.exec(
        select(User).where(User.username == creds.username)
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail="Username already taken")

    user = User(username=creds.username, password_hash=hash_password(creds.password))
    session.add(user)
    session.commit()
    session.refresh(user)

    return {"access_token": create_token(user.id), "token_type": "bearer"}


@app.post("/auth/login")
def login(creds: Credentials, session: Session = Depends(get_session)):
    user = session.exec(
        select(User).where(User.username == creds.username)
    ).first()
    if user is None or not verify_password(creds.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Incorrect username or password")

    return {"access_token": create_token(user.id), "token_type": "bearer"}


@app.get("/auth/me")
def me(user: User = Depends(get_current_user)):
    return {"id": user.id, "username": user.username}


@app.get("/games")
def list_games(
    season: int = 2026,
    week: int | None = Query(None, ge=1, le=15),
    team: str | None = None,
    conference: str | None = None,
    session: Session = Depends(get_session),
):
    query = select(Game).where(Game.season == season)

    if week is not None:
        query = query.where(Game.week == week)
    if team is not None:
        query = query.where((Game.home_team == team) | (Game.away_team == team))
    if conference is not None:
        query = query.where(
            (Game.home_conference == conference) | (Game.away_conference == conference)
        )

    return session.exec(query.order_by(Game.start_date)).all()


@app.post("/games/refresh")
def refresh_games(
    season: int = 2026,
    week: int = Query(..., ge=1, le=15),
    session: Session = Depends(get_session),
):
    raw_games = cfbd.fetch_games(season, week)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    for raw in raw_games:
        data = cfbd.parse_game(raw)
        existing = session.get(Game, data["cfbd_id"])

        if existing:
            for k, v in data.items():
                setattr(existing, k, v)
            existing.last_synced_at = now
        else:
            session.add(Game(**data, last_synced_at=now))

    session.commit()
    return {"synced": len(raw_games), "season": season, "week": week}