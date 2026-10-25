from dotenv import load_dotenv
load_dotenv()  # reads backend/.env (GEMINI_API_KEY etc.) before anything else

import os
if os.environ.get("FORCE_IPV4", "true").lower() == "true":
    # Some home/mobile networks advertise IPv6 but cannot actually route it, which makes
    # calls to Google services (token checks, push, AI) hang until they time out.
    import urllib3.util.connection as _urllib3_conn
    _urllib3_conn.HAS_IPV6 = False

import logging
logging.basicConfig(level=logging.INFO)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.firebase import is_using_real_firebase, db
from app.routers import notifications as notifications_router
from app.routers import auth, recipes, grocery, reminders, targets, coach, messages, missions, foods, meals, evaluation

logger = logging.getLogger("nutrifit")

# Fake (in-memory) Firestore only lives for the lifetime of this process, so if we're
# not connected to a real Firebase project, auto-seed on startup whenever it's empty —
# mirrors how the app behaves gracefully on ephemeral hosting even once deployed.
if not is_using_real_firebase():
    if not list(db.collection("recipes").stream()):
        logger.info("Fake Firestore is empty — auto-seeding demo data...")
        from app.seed import main as seed_main
        seed_main()

app = FastAPI(title="NutriFit API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # tighten this to your Flutter web/app origin(s) in production
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(recipes.router)
app.include_router(grocery.router)
app.include_router(reminders.router)
app.include_router(targets.router)
app.include_router(coach.router)
app.include_router(messages.router)
app.include_router(missions.router)
app.include_router(foods.router)
app.include_router(meals.router)
app.include_router(evaluation.router)
app.include_router(notifications_router.router)


@app.get("/health")
def health():
    return {"ok": True, "service": "nutrifit-api", "firebase": "live" if is_using_real_firebase() else "fake (dev mode)"}
