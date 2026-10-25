"""
Safe migration for existing recipes (run once after upgrading, as often as you like):

  * stores per-100 g nutrition, minimum/maximum weight and the adjustable flag on every ingredient
  * recalculates the recipe totals from the ingredients (the old totals are kept in legacyTotals)
  * flags recipes whose ingredients lack data (nutritionComplete = False) instead of guessing values
  * removes the old fixed 1,914 kcal reference (refDailyCalories)
  * adds status = "consumed" to old meal logs that have no status

Nothing is deleted, and it never touches users or Auth accounts.

Usage (backend folder, venv active):
    python -m app.migrate_ingredients
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.firebase import db
from app.ingredient_data import enrich_recipe


def main() -> dict:
    migrated = incomplete = 0
    report = []
    for snap in db.collection("recipes").stream():
        old = snap.to_dict()
        new = enrich_recipe(old)
        if new != old:
            db.collection("recipes").document(snap.id).set(new)
            migrated += 1
        if not new.get("nutritionComplete"):
            incomplete += 1
            report.append((new.get("name", snap.id), new.get("nutritionProblems", [])[:2]))

    logs = 0
    for u in db.collection("users").stream():
        col = db.collection("users").document(u.id).collection("mealLogs")
        for m in col.stream():
            if "status" not in m.to_dict():
                col.document(m.id).update({"status": "consumed"})
                logs += 1

    print(f"Recipes updated: {migrated}. Recipes without full ingredient data (kept, flagged): {incomplete}. Old meal logs marked consumed: {logs}.")
    for name, problems in report:
        print(f"  - {name}: {'; '.join(problems) if problems else 'no ingredients'}")
    return {"migrated": migrated, "incomplete": incomplete, "logs": logs}


if __name__ == "__main__":
    main()
