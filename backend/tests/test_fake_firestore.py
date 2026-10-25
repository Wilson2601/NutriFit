from app.fake_firestore import FakeFirestoreClient


def test_subcollections_are_isolated_per_parent_document():
    db = FakeFirestoreClient()
    users = db.collection("users")
    users.document("alice").set({"name": "Alice"})
    users.document("bob").set({"name": "Bob"})

    users.document("alice").collection("reminders").add({"title": "Alice's reminder"})
    users.document("bob").collection("reminders").add({"title": "Bob's reminder 1"})
    users.document("bob").collection("reminders").add({"title": "Bob's reminder 2"})

    alice_reminders = users.document("alice").collection("reminders").stream()
    bob_reminders = users.document("bob").collection("reminders").stream()

    assert len(alice_reminders) == 1
    assert alice_reminders[0].to_dict()["title"] == "Alice's reminder"
    assert len(bob_reminders) == 2


def test_where_query_filters_correctly():
    db = FakeFirestoreClient()
    col = db.collection("recipes")
    col.add({"tag": "Protein", "name": "A"})
    col.add({"tag": "Low Carb", "name": "B"})
    col.add({"tag": "Protein", "name": "C"})

    results = col.where("tag", "==", "Protein").stream()
    names = sorted(r.to_dict()["name"] for r in results)
    assert names == ["A", "C"]


def test_document_get_reflects_updates():
    db = FakeFirestoreClient()
    doc = db.collection("targets").document("u1")
    doc.set({"calories": 2000})
    doc.update({"calories": 2450})
    assert doc.get().to_dict()["calories"] == 2450
