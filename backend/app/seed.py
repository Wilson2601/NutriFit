"""
Seeds demo data: 5 recipes, one coach, five clients (linked to the coach), and
7 days of meal-log history per client so the dashboards have real numbers to show.
Safe to re-run — it wipes prior demo data first (only Firestore docs it created).

Usage:
    PYTHONPATH=. ./venv/bin/python -m app.seed
"""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import datetime, timezone, date, timedelta
import bcrypt

from app.recipe_steps import STEPS
from app.ingredient_data import enrich_recipe
from app.timeutil import today_str, days_ago_str
from app.firebase import db, is_using_real_firebase, create_firebase_user, delete_firebase_user

REF_CAL = 1914


def initials(name: str) -> str:
    parts = name.strip().split()
    return "".join(p[0] for p in parts[:2]).upper()


def wipe():
    print("Clearing existing demo data...")
    for snap in list(db.collection("users").stream()):
        # subcollections aren't auto-deleted by Firestore when a parent doc is deleted —
        # clean them explicitly so this seed script is safe to re-run.
        for sub in ("groceryItems", "reminders", "mealLogs", "coachNotes"):
            for item in list(db.collection("users").document(snap.id).collection(sub).stream()):
                db.collection("users").document(snap.id).collection(sub).document(item.id).delete()
        delete_firebase_user(snap.id)  # also remove the real Firebase Auth account, if any
        db.collection("users").document(snap.id).delete()
    for snap in list(db.collection("recipes").stream()):
        db.collection("recipes").document(snap.id).delete()
    for snap in list(db.collection("prescriptions").stream()):
        db.collection("prescriptions").document(snap.id).delete()


def recipe_definitions():
    """The built-in recipes with ingredient nutrition; totals are calculated from the ingredients."""
    return [enrich_recipe(r) for r in _raw_recipes()]


def _raw_recipes():
    return [
        {"name": "Grilled Chicken Bowl", "emoji": "🍗", "tag": "Protein",
         "baseProtein": 45, "baseCarbs": 38, "baseFat": 12, "baseCalories": 520, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Chicken Breast", "emoji": "🍗", "baseAmount": 156, "unit": "g"},
             {"name": "Jasmine Rice", "emoji": "🍚", "baseAmount": 94, "unit": "g"},
             {"name": "Olive Oil", "emoji": "🫒", "baseAmount": 12, "unit": "g"},
             {"name": "Broccoli", "emoji": "🥦", "baseAmount": 78, "unit": "g"},
             {"name": "Soy Sauce", "emoji": "🧂", "baseAmount": 8, "unit": "g"},
             {"name": "Garlic", "emoji": "🧄", "baseAmount": 6, "unit": "g"},
         ]},
        {"name": "Salmon & Quinoa", "emoji": "🐟", "tag": "Protein",
         "baseProtein": 38, "baseCarbs": 42, "baseFat": 18, "baseCalories": 480, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Salmon Fillet", "emoji": "🐟", "baseAmount": 150, "unit": "g"},
             {"name": "Quinoa", "emoji": "🌾", "baseAmount": 100, "unit": "g"},
             {"name": "Olive Oil", "emoji": "🫒", "baseAmount": 10, "unit": "g"},
             {"name": "Asparagus", "emoji": "🥬", "baseAmount": 80, "unit": "g"},
         ]},
        {"name": "Egg White Omelette", "emoji": "🍳", "tag": "Low Carb",
         "baseProtein": 32, "baseCarbs": 8, "baseFat": 10, "baseCalories": 245, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Egg Whites", "emoji": "🥚", "baseAmount": 240, "unit": "ml"},
             {"name": "Spinach", "emoji": "🍃", "baseAmount": 40, "unit": "g"},
             {"name": "Bell Pepper", "emoji": "🫑", "baseAmount": 30, "unit": "g"},
         ]},
        {"name": "Greek Yogurt Bowl", "emoji": "🥣", "tag": "Quick Prep",
         "baseProtein": 28, "baseCarbs": 35, "baseFat": 6, "baseCalories": 305, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Greek Yogurt", "emoji": "🥛", "baseAmount": 250, "unit": "g"},
             {"name": "Oats", "emoji": "🌾", "baseAmount": 40, "unit": "g"},
             {"name": "Honey", "emoji": "🍯", "baseAmount": 15, "unit": "g"},
             {"name": "Almonds", "emoji": "🥜", "baseAmount": 15, "unit": "g"},
         ]},
        {"name": "Avocado Tuna Wrap", "emoji": "🥑", "tag": "Balanced",
         "baseProtein": 40, "baseCarbs": 30, "baseFat": 20, "baseCalories": 440, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Tuna", "emoji": "🐟", "baseAmount": 150, "unit": "g"},
             {"name": "Avocado", "emoji": "🥑", "baseAmount": 80, "unit": "g"},
             {"name": "Whole Wheat Wrap", "emoji": "🫓", "baseAmount": 60, "unit": "g"},
         ]},
        {"name": "Beef & Sweet Potato", "emoji": "🥩", "tag": "Protein",
         "baseProtein": 42, "baseCarbs": 45, "baseFat": 16, "baseCalories": 510, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Lean Beef", "emoji": "🥩", "baseAmount": 150, "unit": "g"},
             {"name": "Sweet Potato", "emoji": "🍠", "baseAmount": 200, "unit": "g"},
             {"name": "Olive Oil", "emoji": "🫒", "baseAmount": 10, "unit": "g"},
             {"name": "Green Beans", "emoji": "🫛", "baseAmount": 80, "unit": "g"},
         ]},
        {"name": "Tofu Stir Fry", "emoji": "🥡", "tag": "Balanced",
         "baseProtein": 26, "baseCarbs": 48, "baseFat": 14, "baseCalories": 420, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Firm Tofu", "emoji": "🧈", "baseAmount": 180, "unit": "g"},
             {"name": "Jasmine Rice", "emoji": "🍚", "baseAmount": 120, "unit": "g"},
             {"name": "Sesame Oil", "emoji": "🫒", "baseAmount": 8, "unit": "g"},
             {"name": "Mixed Vegetables", "emoji": "🥕", "baseAmount": 100, "unit": "g"},
             {"name": "Soy Sauce", "emoji": "🧂", "baseAmount": 10, "unit": "g"},
         ]},
        {"name": "Turkey Chili", "emoji": "🌶️", "tag": "Protein",
         "baseProtein": 44, "baseCarbs": 32, "baseFat": 10, "baseCalories": 400, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Ground Turkey", "emoji": "🦃", "baseAmount": 170, "unit": "g"},
             {"name": "Kidney Beans", "emoji": "🫘", "baseAmount": 100, "unit": "g"},
             {"name": "Tomato Sauce", "emoji": "🍅", "baseAmount": 120, "unit": "g"},
             {"name": "Onion", "emoji": "🧅", "baseAmount": 40, "unit": "g"},
         ]},
        {"name": "Overnight Oats", "emoji": "🥣", "tag": "Quick Prep",
         "baseProtein": 20, "baseCarbs": 55, "baseFat": 9, "baseCalories": 380, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Oats", "emoji": "🌾", "baseAmount": 60, "unit": "g"},
             {"name": "Milk", "emoji": "🥛", "baseAmount": 200, "unit": "ml"},
             {"name": "Chia Seeds", "emoji": "🌱", "baseAmount": 12, "unit": "g"},
             {"name": "Banana", "emoji": "🍌", "baseAmount": 100, "unit": "g"},
         ]},
        {"name": "Shrimp Zoodle Bowl", "emoji": "🍤", "tag": "Low Carb",
         "baseProtein": 34, "baseCarbs": 14, "baseFat": 15, "baseCalories": 320, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Shrimp", "emoji": "🍤", "baseAmount": 160, "unit": "g"},
             {"name": "Zucchini Noodles", "emoji": "🥒", "baseAmount": 150, "unit": "g"},
             {"name": "Olive Oil", "emoji": "🫒", "baseAmount": 12, "unit": "g"},
             {"name": "Garlic", "emoji": "🧄", "baseAmount": 6, "unit": "g"},
             {"name": "Parmesan", "emoji": "🧀", "baseAmount": 15, "unit": "g"},
         ]},
        {"name": "Peanut Butter Protein Shake", "emoji": "🥤", "tag": "Quick Prep",
         "baseProtein": 36, "baseCarbs": 28, "baseFat": 14, "baseCalories": 380, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Whey Protein", "emoji": "🥛", "baseAmount": 35, "unit": "g"},
             {"name": "Peanut Butter", "emoji": "🥜", "baseAmount": 20, "unit": "g"},
             {"name": "Banana", "emoji": "🍌", "baseAmount": 100, "unit": "g"},
             {"name": "Milk", "emoji": "🥛", "baseAmount": 250, "unit": "ml"},
         ]},
        {"name": "Cottage Cheese & Berries", "emoji": "🍓", "tag": "Low Carb",
         "baseProtein": 24, "baseCarbs": 18, "baseFat": 5, "baseCalories": 210, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Cottage Cheese", "emoji": "🧀", "baseAmount": 200, "unit": "g"},
             {"name": "Mixed Berries", "emoji": "🫐", "baseAmount": 80, "unit": "g"},
             {"name": "Honey", "emoji": "🍯", "baseAmount": 10, "unit": "g"},
         ]},
        {"name": "Chickpea Buddha Bowl", "emoji": "🥗", "tag": "Balanced",
         "baseProtein": 22, "baseCarbs": 52, "baseFat": 16, "baseCalories": 430, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Chickpeas", "emoji": "🫘", "baseAmount": 150, "unit": "g"},
             {"name": "Quinoa", "emoji": "🌾", "baseAmount": 80, "unit": "g"},
             {"name": "Avocado", "emoji": "🥑", "baseAmount": 60, "unit": "g"},
             {"name": "Mixed Greens", "emoji": "🥬", "baseAmount": 60, "unit": "g"},
             {"name": "Tahini", "emoji": "🫙", "baseAmount": 15, "unit": "g"},
         ]},
        {"name": "Steak & Rice", "emoji": "🥩", "tag": "Protein",
         "baseProtein": 48, "baseCarbs": 40, "baseFat": 22, "baseCalories": 560, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Sirloin Steak", "emoji": "🥩", "baseAmount": 180, "unit": "g"},
             {"name": "Jasmine Rice", "emoji": "🍚", "baseAmount": 110, "unit": "g"},
             {"name": "Butter", "emoji": "🧈", "baseAmount": 10, "unit": "g"},
             {"name": "Broccoli", "emoji": "🥦", "baseAmount": 90, "unit": "g"},
         ]},
        {"name": "Protein Pancakes", "emoji": "🥞", "tag": "Balanced",
         "baseProtein": 30, "baseCarbs": 46, "baseFat": 10, "baseCalories": 400, "refDailyCalories": REF_CAL,
         "ingredients": [
             {"name": "Oat Flour", "emoji": "🌾", "baseAmount": 60, "unit": "g"},
             {"name": "Whey Protein", "emoji": "🥛", "baseAmount": 30, "unit": "g"},
             {"name": "Eggs", "emoji": "🥚", "baseAmount": 100, "unit": "g"},
             {"name": "Maple Syrup", "emoji": "🍁", "baseAmount": 20, "unit": "g"},
         ]},
    ]


def seed_recipes():
    recipes = recipe_definitions()
    ids = []
    for r in recipes:
        r["steps"] = STEPS.get(r["name"], [])
        _, doc = db.collection("recipes").add(r)
        ids.append(doc.id)
    return ids


DEFAULT_REMINDERS = [
    ("Defrost Reminder", "6:00 AM", "Defrost proteins for the day", "❄️", True),
    ("Pre-Workout Meal", "11:30 AM", "Carb timing window", "⚡", True),
    ("Post-Workout Protein", "2:00 PM", "Within 30 min of training", "💪", False),
    ("Evening Meal Prep", "5:30 PM", "Check grocery list", "🛒", True),
    ("Hydration Check", "10:00 AM", "Drink a glass of water", "💧", False),
    ("Evening Review", "8:00 PM", "Review tomorrow's plan", "🌙", True),
]


def seed_reminders(uid):
    col = db.collection("users").document(uid).collection("reminders")
    for i, (title, time_label, subtitle, icon, enabled) in enumerate(DEFAULT_REMINDERS):
        from app.routers.reminders import label_to_hhmm
        col.add({"title": title, "timeLabel": time_label, "time": label_to_hhmm(time_label), "subtitle": subtitle,
                 "icon": icon, "enabled": enabled, "sortOrder": i})


def create_user(role, name, email, password, phone, goal, weight, goal_weight, streak):
    # Creates the REAL Firebase Auth account (or a synthetic dev uid in fake mode) —
    # this is what was missing before: writing a Firestore profile alone doesn't let
    # anyone actually sign in, since Firebase Auth is a separate system that needs its
    # own account created for the email/password to be valid credentials.
    uid = create_firebase_user(email, password, name)
    profile = {
        "role": role, "name": name, "email": email, "phone": phone, "goal": goal,
        "weightKg": weight, "goalWeightKg": goal_weight, "streakDays": streak,
        "avatarInitials": initials(name), "coachId": None,
        "createdAt": datetime.now(timezone.utc).isoformat(),
    }
    if not is_using_real_firebase():
        profile["_devPasswordHash"] = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    # The Firestore document ID MUST match the Firebase Auth uid — that's how
    # get_current_user() looks up a signed-in user's profile after verifying their token.
    db.collection("users").document(uid).set(profile)
    return uid


def seed_meal_logs(uid, recipe_ids, target, day_factors):
    for day_offset, factor in enumerate(day_factors):
        log_date = days_ago_str(day_offset)
        picks = [recipe_ids[day_offset % len(recipe_ids)], recipe_ids[(day_offset + 2) % len(recipe_ids)], recipe_ids[(day_offset + 4) % len(recipe_ids)]]
        recipe_docs = [db.collection("recipes").document(rid).get().to_dict() for rid in picks]
        base_protein_sum = sum(r["baseProtein"] for r in recipe_docs)
        day_factor = (target["proteinG"] * factor) / base_protein_sum if base_protein_sum else factor
        for i, r in enumerate(recipe_docs):
            db.collection("users").document(uid).collection("mealLogs").add({
                "recipeId": picks[i], "recipeName": r["name"], "recipeEmoji": r["emoji"],
                "mealType": ["Breakfast", "Lunch", "Dinner"][i], "logDate": log_date,
                "loggedAt": datetime.now(timezone.utc).isoformat(),
                "protein": round(r["baseProtein"] * day_factor, 1),
                "carbs": round(r["baseCarbs"] * day_factor, 1),
                "fat": round(r["baseFat"] * day_factor, 1),
                "calories": round(r["baseCalories"] * day_factor, 1),
            })


def main():
    wipe()
    print("Seeding recipes...")
    recipe_ids = seed_recipes()

    print("Seeding coach...")
    coach_id = create_user("coach", "Wilson Lu", "wilson@nutrifit.my", "password123", "+60 11-1263 7542", "coaching", 0, 0, 0)

    clients = [
        {"name": "Wilson Lu Yew Siong", "email": "wilson@example.com", "phone": "+60 11-1263 7542", "goal": "muscle_gain",
         "weight": 75.2, "goalWeight": 80, "streak": 14, "target": {"proteinG": 180, "carbsG": 280, "fatG": 65, "calories": 2450}, "factors": [0.79, 0.9, 0.95, 0.88, 0.92, 0.8, 0.85]},
        {"name": "Ahmad Faiz", "email": "ahmad@example.com", "phone": "+60 12-345 6789", "goal": "weight_loss",
         "weight": 82.5, "goalWeight": 78, "streak": 5, "target": {"proteinG": 160, "carbsG": 200, "fatG": 55, "calories": 1950}, "factors": [0.61, 0.6, 0.5, 0.65, 0.58, 0.5, 0.61]},
        {"name": "Raj Kumar", "email": "raj@example.com", "phone": "+60 13-456 7890", "goal": "muscle_gain",
         "weight": 70, "goalWeight": 75, "streak": 2, "target": {"proteinG": 180, "carbsG": 280, "fatG": 60, "calories": 2350}, "factors": [0.36, 0.35, 0.4, 0.32, 0.36, 0.3, 0.36]},
        {"name": "Sara Lim", "email": "sara@example.com", "phone": "+60 14-567 8901", "goal": "maintain",
         "weight": 58, "goalWeight": 58, "streak": 21, "target": {"proteinG": 120, "carbsG": 160, "fatG": 50, "calories": 1650}, "factors": [0.98, 0.98, 1.0, 0.97, 0.99, 0.96, 0.98]},
        {"name": "Mei Ling", "email": "meiling@example.com", "phone": "+60 16-678 9012", "goal": "weight_loss",
         "weight": 62, "goalWeight": 56, "streak": 9, "target": {"proteinG": 130, "carbsG": 160, "fatG": 45, "calories": 1700}, "factors": [0.85, 0.88, 0.9, 0.86, 0.89, 0.87, 0.88]},
    ]

    for c in clients:
        print(f"Seeding client {c['name']}...")
        uid = create_user("user", c["name"], c["email"], "password123", c["phone"], c["goal"], c["weight"], c["goalWeight"], c["streak"])
        db.collection("users").document(uid).update({"coachId": coach_id})
        db.collection("prescriptions").add({
            "clientId": uid, "coachId": coach_id, **c["target"],
            "createdAt": datetime.now(timezone.utc).isoformat(),
        })
        seed_reminders(uid)
        seed_meal_logs(uid, recipe_ids, c["target"], c["factors"])

    print("Seed complete.")
    print("  Coach login  -> wilson@nutrifit.my / password123")
    print("  User logins  -> wilson@example.com, ahmad@example.com, raj@example.com, sara@example.com, meiling@example.com (all password123)")


if __name__ == "__main__":
    main()
