"""
Adds any built-in recipe that is missing from Firestore (matched by name) and fills in cooking
steps where they are missing. It never deletes or changes anything else, so it is safe to run
as often as you like. (Do NOT run app.seed on a real project: it wipes all users first.)

Usage (from the backend folder, with the venv active):
    python -m app.add_recipes
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.firebase import db
from app.recipe_steps import STEPS
from app.seed import recipe_definitions


def main() -> dict:
    existing = {}
    for snap in db.collection("recipes").stream():
        existing[snap.to_dict().get("name")] = snap

    added = steps_filled = 0
    for recipe in recipe_definitions():
        name = recipe["name"]
        steps = STEPS.get(name, [])
        if name not in existing:
            db.collection("recipes").add({**recipe, "steps": steps})
            added += 1
        elif not existing[name].to_dict().get("steps") and steps:
            db.collection("recipes").document(existing[name].id).update({"steps": steps})
            steps_filled += 1

    total = len(list(db.collection("recipes").stream()))
    print(f"Added {added} new recipes, filled cooking steps on {steps_filled}. Total recipes now: {total}.")
    return {"added": added, "stepsFilled": steps_filled, "total": total}


if __name__ == "__main__":
    main()
