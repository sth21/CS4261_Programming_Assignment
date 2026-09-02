import os
from datetime import datetime
import httpx
from dotenv import load_dotenv

load_dotenv()

CFBD_API_KEY = os.getenv("CFBD_API_KEY")
BASE_URL = "https://api.collegefootballdata.com"

def fetch_games(season: int, week: int) -> list[dict]:
    """Fetch games for a given season and week from CollegeFootballData"""

    if not CFBD_API_KEY:
        raise RuntimeError("CFBD_API_KEY is not set")

    response = httpx.get(
        f"{BASE_URL}/games",
        params={"year": season, "week": week, "classification": "fbs"},
        headers={"Authorization": f"Bearer {CFBD_API_KEY}"},
        timeout=30.0,
    )

    response.raise_for_status()
    return response.json()

def parse_game(raw: dict) -> dict:
    """Map CFBD game object to Game column names"""
    return {
        "cfbd_id": raw["id"],
        "season": raw["season"],
        "week": raw["week"],
        "home_team": raw["homeTeam"],
        "away_team": raw["awayTeam"],
        "home_conference": raw["homeConference"],
        "away_conference": raw["awayConference"],
        "start_date": datetime.fromisoformat(raw["startDate"].replace("Z", "+00:00")),
        "completed": raw["completed"],
        "home_points": raw.get("homePoints"),
        "away_points": raw.get("awayPoints"),
        "venue": raw.get("venue")
    }