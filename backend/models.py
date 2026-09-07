from datetime import datetime, timezone
from sqlmodel import SQLModel, Field, Column, UniqueConstraint, DateTime

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    username: str = Field(unique=True, index=True)
    password_hash: str
    created_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=utc_now, nullable=False),
    )

class Game(SQLModel, table=True):
    cfbd_id: int = Field(primary_key=True)
    season: int = Field(index=True)
    week: int = Field(index=True)
    home_team: str = Field(index=True)
    away_team: str = Field(index=True)
    home_id: int | None = None
    away_id: int | None = None
    home_conference: str | None = None
    away_conference: str | None = None
    start_date: datetime = Field(sa_column=Column(DateTime(timezone=True)))
    completed: bool = False
    home_points: int | None = None
    away_points: int | None = None
    venue: str | None = None
    last_synced_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=utc_now, nullable=False),
    )

class Pick(SQLModel, table=True):
    __table_args__ = (UniqueConstraint("user_id", "game_id"),)
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    game_id: int = Field(foreign_key="game.cfbd_id", index=True)
    predicted_winner: str
    is_correct: bool | None = None
    created_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=utc_now, nullable=False),
    )
    updated_at: datetime = Field(
        sa_column=Column(DateTime(timezone=True), default=utc_now, nullable=False),
    )