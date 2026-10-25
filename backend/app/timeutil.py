"""
Single source of truth for "what day is it?".

Meal logs, progress, suggestions and daily missions must all agree on the date.
Using the server's UTC clock for some and local time for others made late-night
and early-morning meals land on the wrong day, so everything goes through here.
Set APP_TZ (an IANA name) to change the timezone; default is Malaysia time.
"""
import os
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

APP_TZ = ZoneInfo(os.environ.get("APP_TZ", "Asia/Kuala_Lumpur"))


def now_local() -> datetime:
    return datetime.now(APP_TZ)


def today() -> date:
    return now_local().date()


def today_str() -> str:
    return today().isoformat()


def days_ago_str(n: int) -> str:
    return (today() - timedelta(days=n)).isoformat()
