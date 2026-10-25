"""
One place for daily nutrition maths, shared by the dashboard, food history, coach views,
recipe optimisation and the daily mission, so every screen shows the same numbers.

  * Only CONSUMED entries (mealLogs) count as intake. Planned meals are stored separately and
    never affect the totals.
  * Targets are looked up per date from the coach's prescription history, so old days keep the
    target that applied back then.
  * Achievement H_j = I_j / T_j * 100. A day is adherent when every required component lies inside
    its configurable range AND something was logged. Days with no records are counted separately
    (missing records are not proof that the plan was ignored).
"""
import os
import json
from datetime import date, datetime, timedelta
from typing import Optional

from app.firebase import db
from app.timeutil import APP_TZ, today, today_str

NUTRIENTS = ("calories", "protein", "carbs", "fat")
TARGET_KEYS = {"calories": "calories", "protein": "proteinG", "carbs": "carbsG", "fat": "fatG"}
DEFAULT_TARGET = {"proteinG": 150, "carbsG": 200, "fatG": 60, "calories": 2000}

# Proposed FYP 2 project rules (not medical standards). Override with NUTRIFIT_ADHERENCE_JSON, e.g.
# {"ranges": {"calories": [85, 115]}, "required": ["calories", "protein"]}
ADHERENCE_RANGES = {"calories": (85.0, 115.0), "protein": (80.0, 120.0), "carbs": (80.0, 120.0), "fat": (80.0, 120.0)}
REQUIRED = list(NUTRIENTS)


def _load_overrides():
    raw = os.environ.get("NUTRIFIT_ADHERENCE_JSON", "").strip()
    if raw:
        data = json.loads(raw)
        for k, v in data.get("ranges", {}).items():
            ADHERENCE_RANGES[k] = (float(v[0]), float(v[1]))
        if "required" in data:
            REQUIRED[:] = [k for k in data["required"] if k in NUTRIENTS]


_load_overrides()


def adherence_config() -> dict:
    return {"ranges": {k: list(v) for k, v in ADHERENCE_RANGES.items()}, "required": list(REQUIRED)}


def _local_date(iso: str) -> Optional[str]:
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    if dt.tzinfo is None:
        return dt.date().isoformat()
    return dt.astimezone(APP_TZ).date().isoformat()


def _prescriptions(uid: str) -> list:
    return [s.to_dict() for s in db.collection("prescriptions").where("clientId", "==", uid).stream()]


def _all_logs(uid: str) -> list:
    return [{"id": s.id, **s.to_dict()} for s in db.collection("users").document(uid).collection("mealLogs").stream()]


def get_target(uid: str, on_date: Optional[str] = None, _rows: Optional[list] = None) -> dict:
    """Target that applied on `on_date` (default today): the latest prescription made on or before that day."""
    rows = _rows if _rows is not None else _prescriptions(uid)
    if not rows:
        return dict(DEFAULT_TARGET)
    rows.sort(key=lambda r: r.get("createdAt", ""))
    if on_date:
        applicable = [r for r in rows if (_local_date(r.get("createdAt", "")) or "") <= on_date]
        return applicable[-1] if applicable else rows[0]   # before the first prescription: use the first one
    return rows[-1]


def consumed_entries(uid: str, on_date: str, _logs: Optional[list] = None) -> list:
    """Confirmed consumed meals for one local day (entries without a status are old consumed logs)."""
    out = []
    for d in (_logs if _logs is not None else _all_logs(uid)):
        if d.get("logDate") == on_date and d.get("status", "consumed") == "consumed":
            out.append(d)
    out.sort(key=lambda m: m.get("loggedAt", ""))
    return out


def totals_of(entries: list) -> dict:
    return {k: round(sum(float(e.get(k, 0) or 0) for e in entries), 1) for k in NUTRIENTS}


def _judge(consumed: dict, target: dict, has_records: bool) -> dict:
    components = {}
    for k in NUTRIENTS:
        t = float(target[TARGET_KEYS[k]])
        i = consumed[k]
        pct = round(i / t * 100.0, 1) if t > 0 else None
        lo, hi = ADHERENCE_RANGES[k]
        if pct is None:
            state = "no_target"
        elif pct < lo:
            state = "below"
        elif pct > hi:
            state = "above"
        else:
            state = "within"
        components[k] = {
            "target": round(t, 1), "consumed": i,
            "remaining": round(max(0.0, t - i), 1), "over": round(max(0.0, i - t), 1),
            "percent": pct, "range": [lo, hi], "state": state,
        }
    adherent = has_records and all(components[k]["state"] in ("within", "no_target") for k in REQUIRED)
    return {"components": components, "adherent": bool(adherent)}


def daily_summary(uid: str, on_date: Optional[str] = None, with_meals: bool = True,
                  _logs: Optional[list] = None, _rows: Optional[list] = None) -> dict:
    on_date = on_date or today_str()
    target = get_target(uid, on_date, _rows)
    entries = consumed_entries(uid, on_date, _logs)
    consumed = totals_of(entries)
    judged = _judge(consumed, target, bool(entries))
    out = {
        "date": on_date, "hasRecords": bool(entries), "mealCount": len(entries),
        "target": {k: target[TARGET_KEYS[k]] for k in NUTRIENTS},
        "consumed": consumed,
        "remaining": {k: judged["components"][k]["remaining"] for k in NUTRIENTS},
        "components": judged["components"], "adherent": judged["adherent"],
        "status": "no_records" if not entries else ("adherent" if judged["adherent"] else "not_adherent"),
    }
    if with_meals:
        out["meals"] = entries
    return out


def adherence_report(uid: str, days: int = 7, include_today: bool = False) -> dict:
    """Adherence over the last `days` days (ending yesterday unless include_today)."""
    days = max(1, min(int(days), 90))
    end = today() if include_today else today() - timedelta(days=1)
    day_list = [(end - timedelta(days=n)).isoformat() for n in range(days - 1, -1, -1)]
    logs, rows = _all_logs(uid), _prescriptions(uid)
    history = [daily_summary(uid, d, with_meals=False, _logs=logs, _rows=rows) for d in day_list]

    logged = sum(1 for h in history if h["hasRecords"])
    adherent = sum(1 for h in history if h["adherent"])
    return {
        "days": days, "startDate": day_list[0], "endDate": day_list[-1], "includesToday": include_today,
        "config": adherence_config(),
        "observationDays": days, "loggedDays": logged, "noRecordDays": days - logged,
        "adherentDays": adherent,
        "adherenceRate": round(adherent / days * 100.0, 1),
        "adherenceRateOfLoggedDays": round(adherent / logged * 100.0, 1) if logged else None,
        "loggingCompleteness": round(logged / days * 100.0, 1),
        "history": history,
    }
