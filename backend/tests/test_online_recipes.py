from fastapi.testclient import TestClient

from app import online_recipes
from app.main import app
from app.firebase import db

client = TestClient(app)


def _uid(email):
    return next(s.id for s in db.collection("users").stream() if s.to_dict().get("email") == email)


def _h(email="sara@example.com"):
    return {"Authorization": f"Bearer fakeuid:{_uid(email)}"}


SAMPLE = {
    "id": 654959, "title": "Pasta With Tuna", "servings": 4, "readyInMinutes": 20, "dishTypes": ["lunch", "main course"],
    "sourceUrl": "https://example.com/pasta",
    "nutrition": {"nutrients": [
        {"name": "Calories", "amount": 450.4, "unit": "kcal"}, {"name": "Protein", "amount": 32.1, "unit": "g"},
        {"name": "Carbohydrates", "amount": 50.2, "unit": "g"}, {"name": "Fat", "amount": 12.0, "unit": "g"}]},
    "extendedIngredients": [
        {"name": "tuna", "nameClean": "canned tuna", "amount": 2, "measures": {"metric": {"amount": 400, "unitShort": "g"}}},
        {"name": "pasta", "amount": 1, "measures": {"metric": {"amount": 200, "unitShort": "g"}}},
        {"name": "lemon", "amount": 1, "measures": {"metric": {"amount": 4, "unitShort": ""}}},
        {"name": "ghost", "amount": 0, "measures": {"metric": {"amount": 0, "unitShort": "g"}}},
    ],
    "analyzedInstructions": [{"steps": [{"number": 1, "step": "Boil the pasta."}, {"number": 2, "step": "Mix in the tuna."}]}],
}


def test_convert_makes_per_serving_recipe():
    r = online_recipes.convert(SAMPLE)
    assert r["baseCalories"] == 450 and r["baseProtein"] == 32 and r["tag"] == "Protein"
    names = {i["name"]: i for i in r["ingredients"]}
    assert names["Canned Tuna"]["baseAmount"] == 100 and names["Canned Tuna"]["unit"] == "g"
    assert names["Lemon"]["unit"] == "pc" and "Ghost" not in names
    assert r["steps"] == ["Boil the pasta.", "Mix in the tuna."] and r["externalId"] == "sp_654959"


def test_convert_skips_recipes_missing_data():
    assert online_recipes.convert({**SAMPLE, "analyzedInstructions": []}) is None
    assert online_recipes.convert({**SAMPLE, "nutrition": {"nutrients": []}}) is None


def test_online_endpoint_saves_recipe_and_it_can_be_scaled(monkeypatch):
    monkeypatch.setattr(online_recipes, "search_online", lambda q, number=8: [online_recipes.convert(SAMPLE)])
    r = client.get("/recipes/online", params={"q": "tuna pasta"}, headers=_h())
    assert r.status_code == 200
    rid = r.json()["recipes"][0]["id"]
    assert rid == "sp_654959"

    opt = client.post(f"/recipes/{rid}/optimize", json={"mealType": "Lunch", "futureMeal": "no"}, headers=_h()).json()
    assert opt["steps"][0] == "Boil the pasta." and opt["source"] == "Spoonacular"
    # No per-ingredient nutrition for imported recipes: only the portion is adjusted, and it says so.
    assert opt["result"]["method"] == "portion_scaling_fallback"

    again = client.get("/recipes/online", params={"q": "tuna pasta"}, headers=_h())
    assert again.status_code == 200
    assert len([x for x in db.collection("recipes").stream() if x.id == "sp_654959"]) == 1


def test_online_endpoint_reports_unavailable(monkeypatch):
    def down(q, number=8):
        raise online_recipes.OnlineRecipesUnavailable("not set up")
    monkeypatch.setattr(online_recipes, "search_online", down)
    r = client.get("/recipes/online", params={"q": "tuna"}, headers=_h())
    assert r.status_code == 503 and "not set up" in r.json()["detail"]


def test_local_search_matches_ingredients_and_all_words():
    names = [x["name"] for x in client.get("/recipes", params={"search": "chicken rice"}, headers=_h()).json()["recipes"]]
    assert "Grilled Chicken Bowl" in names  # name has "chicken", ingredients have "rice"
    assert client.get("/recipes", params={"search": "chicken zzzz"}, headers=_h()).json()["recipes"] == []


def test_builtin_recipes_have_cooking_steps():
    recipes = client.get("/recipes", headers=_h()).json()["recipes"]
    assert recipes and all(r.get("steps") for r in recipes if "externalId" not in r)


def test_add_recipes_restores_missing_builtins_without_touching_others():
    from app import add_recipes
    from app.seed import recipe_definitions
    builtin = {r["name"] for r in recipe_definitions()}
    victims = [s for s in db.collection("recipes").stream() if s.to_dict().get("name") in list(builtin)[:5]]
    for s in victims:
        db.collection("recipes").document(s.id).delete()
    before_other = {s.id for s in db.collection("recipes").stream()}

    result = add_recipes.main()
    assert result["added"] == len(victims)
    after = {s.id for s in db.collection("recipes").stream()}
    assert before_other <= after  # nothing else removed
    names = {s.to_dict()["name"] for s in db.collection("recipes").stream()}
    assert builtin <= names
    assert add_recipes.main()["added"] == 0  # idempotent
