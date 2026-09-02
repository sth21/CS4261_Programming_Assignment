from datetime import datetime, timezone
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Query
from sqlmodel import Session, select
from database import create_db_and_tables, get_session
from models import Game
import models
import cfbd


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="Gameday Pick'em API", lifespan=lifespan)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/games")
def list_games(
    season: int = 2026,
    week: int | None = None,
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
    week: int = Query(...),
    session: Session = Depends(get_session),
):
    raw_games = cfbd.fetch_games(season, week)
    now = datetime.now(timezone.utc)

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