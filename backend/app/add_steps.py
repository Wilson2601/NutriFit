"""
Adds cooking steps to the recipes already in Firestore (matched by name).
Safe to run any time: it never deletes anything and only fills in missing steps.

Usage (from the backend folder, with the venv active):
    python -m app.add_steps
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.firebase import db
from app.recipe_steps import STEPS


def main() -> int:
    updated = 0
    for snap in db.collection("recipes").stream():
        data = snap.to_dict()
        if not data.get("steps") and data.get("name") in STEPS:
            db.collection("recipes").document(snap.id).update({"steps": STEPS[data["name"]]})
            updated += 1
    print(f"Added cooking steps to {updated} recipes.")
    return updated


if __name__ == "__main__":
    main()
