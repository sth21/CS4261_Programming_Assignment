from datetime import datetime, timezone
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Query, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select
from database import create_db_and_tables, get_session
from models import Game, User, Pick
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


class PickRequest(BaseModel):
    game_id: int
    predicted_winner: str


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def sync_week(session: Session, season: int, week: int) -> int:
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
    return len(raw_games)


def week_games(session: Session, season: int, week: int) -> list[Game]:
    return session.exec(
        select(Game)
        .where(Game.season == season, Game.week == week)
        .order_by(Game.start_date)
    ).all()


def has_game_in_play(games: list[Game], now: datetime) -> bool:
    for game in games:
        kickoff = as_utc(game.start_date)
        if not game.completed and kickoff is not None and kickoff <= now:
            return True
    return False


def resolve_current_week(session: Session, season: int) -> int:
    now = datetime.now(timezone.utc)

    weeks = session.exec(
        select(Game.week).where(Game.season == season).distinct().order_by(Game.week)
    ).all()

    if not weeks:
        try:
            sync_week(session, season, 1)
        except Exception:
            session.rollback()
        return 1

    for week in weeks:
        games = week_games(session, season, week)
        if not games:
            continue

        if has_game_in_play(games, now):
            try:
                sync_week(session, season, week)
                games = week_games(session, season, week)
            except Exception:
                session.rollback()

        if any(not g.completed for g in games):
            return week

    return weeks[-1]


def grade_pending_picks(session: Session) -> int:
    picks = session.exec(select(Pick).where(Pick.is_correct == None)).all()
    graded = 0

    for pick in picks:
        game = session.get(Game, pick.game_id)
        if game is None or not game.completed:
            continue
        if game.home_points is None or game.away_points is None:
            continue
        if game.home_points == game.away_points:
            continue

        winner = game.home_team if game.home_points > game.away_points else game.away_team
        pick.is_correct = (pick.predicted_winner == winner)
        graded += 1

    session.commit()
    return graded


def is_locked(game: Game) -> bool:
    kickoff = as_utc(game.start_date)
    if kickoff is None:
        return False
    return datetime.now(timezone.utc) >= kickoff


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
    conference: str | None = None,
    session: Session = Depends(get_session),
):
    query = select(Game).where(Game.season == season)

    if week is not None:
        query = query.where(Game.week == week)
    if conference is not None:
        query = query.where(
            (Game.home_conference == conference) | (Game.away_conference == conference)
        )

    return session.exec(query.order_by(Game.start_date)).all()


@app.get("/games/current")
def current_slate(season: int = 2026, session: Session = Depends(get_session)):
    week = resolve_current_week(session, season)
    return {"week": week, "games": week_games(session, season, week)}


@app.post("/games/refresh")
def refresh_games(
    season: int = 2026,
    week: int = Query(..., ge=1, le=15),
    session: Session = Depends(get_session),
):
    synced = sync_week(session, season, week)
    graded = grade_pending_picks(session)
    return {"synced": synced, "graded": graded, "season": season, "week": week}


@app.get("/picks")
def list_picks(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    grade_pending_picks(session)

    picks = session.exec(select(Pick).where(Pick.user_id == user.id)).all()
    wins = sum(1 for p in picks if p.is_correct is True)
    losses = sum(1 for p in picks if p.is_correct is False)
    pending = sum(1 for p in picks if p.is_correct is None)

    return {
        "picks": picks,
        "record": {"wins": wins, "losses": losses, "pending": pending},
    }


@app.post("/picks/grade")
def grade_picks(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    pending = session.exec(
        select(Pick).where(Pick.user_id == user.id, Pick.is_correct == None)
    ).all()

    weeks = set()
    for pick in pending:
        game = session.get(Game, pick.game_id)
        if game is not None and not game.completed:
            weeks.add((game.season, game.week))

    for season, week in weeks:
        sync_week(session, season, week)

    graded = grade_pending_picks(session)
    return {"weeks_synced": len(weeks), "graded": graded}


@app.post("/picks")
def create_pick(
    body: PickRequest,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    game = session.get(Game, body.game_id)
    if game is None:
        raise HTTPException(status_code=404, detail="Game not found")

    if body.predicted_winner not in (game.home_team, game.away_team):
        raise HTTPException(
            status_code=400,
            detail=f"Winner must be {game.home_team} or {game.away_team}",
        )

    if is_locked(game):
        raise HTTPException(status_code=409, detail="Game has already started")

    now = datetime.now(timezone.utc).replace(microsecond=0)

    pick = session.exec(
        select(Pick).where(Pick.user_id == user.id, Pick.game_id == body.game_id)
    ).first()

    if pick:
        pick.predicted_winner = body.predicted_winner
        pick.updated_at = now
    else:
        pick = Pick(
            user_id=user.id,
            game_id=body.game_id,
            predicted_winner=body.predicted_winner,
            created_at=now,
            updated_at=now,
        )
        session.add(pick)

    session.commit()
    session.refresh(pick)
    return pick


@app.delete("/picks/{game_id}")
def delete_pick(
    game_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    pick = session.exec(
        select(Pick).where(Pick.user_id == user.id, Pick.game_id == game_id)
    ).first()
    if pick is None:
        raise HTTPException(status_code=404, detail="Pick not found")

    game = session.get(Game, game_id)
    if game is not None and is_locked(game):
        raise HTTPException(status_code=409, detail="Game has already started")

    session.delete(pick)
    session.commit()
    return {"deleted": game_id}