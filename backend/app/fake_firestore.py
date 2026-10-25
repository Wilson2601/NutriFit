"""
A minimal in-memory stand-in for google.cloud.firestore.Client, implementing just
the surface area this app uses (collection/document/get/set/update/delete/where/stream,
plus subcollections). This exists purely so the backend can run and be fully tested
without a live Firebase project. The moment real credentials are present
(see app/firebase.py), the app talks to real Firestore instead — no code changes
needed anywhere else in the app, since routers only ever call this same interface.
"""
import itertools
import copy

_id_counter = itertools.count(1)


class FakeSnapshot:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = copy.deepcopy(data) if data is not None else None

    @property
    def exists(self):
        return self._data is not None

    def to_dict(self):
        return copy.deepcopy(self._data) if self._data is not None else None


class FakeDocument:
    def __init__(self, store, doc_id):
        self._store = store
        self.id = doc_id

    def set(self, data, merge=False):
        if merge and self.id in self._store:
            self._store[self.id].update(data)
        else:
            self._store[self.id] = copy.deepcopy(data)

    def update(self, data):
        if self.id not in self._store:
            raise KeyError(f"Document {self.id} does not exist")
        self._store[self.id].update(copy.deepcopy(data))

    def get(self):
        return FakeSnapshot(self.id, self._store.get(self.id))

    def delete(self):
        self._store.pop(self.id, None)

    def collection(self, name):
        # Subcollection, namespaced by THIS document's id + name, so sibling documents
        # (e.g. different users) never share the same subcollection bucket.
        sub_key = f"{self.id}:{name}"
        parent_subs = self._store.setdefault("__sub__", {})
        bucket = parent_subs.setdefault(sub_key, {})
        return FakeCollection(bucket, key=sub_key)


class FakeQuery:
    def __init__(self, store, predicate):
        self._store = store
        self._predicate = predicate

    def where(self, field, op, value):
        def combined(doc_id, data):
            return self._predicate(doc_id, data) and _match(data, field, op, value)
        return FakeQuery(self._store, combined)

    def order_by(self, field, direction="ASCENDING"):
        # No-op for ordering guarantees in the fake store; callers should sort in Python if needed.
        return self

    def limit(self, n):
        return self

    def stream(self):
        items = [(doc_id, data) for doc_id, data in self._store.items()
                 if doc_id != "__sub__" and self._predicate(doc_id, data)]
        return [FakeSnapshot(doc_id, data) for doc_id, data in items]


def _match(data, field, op, value):
    actual = data.get(field)
    if op == "==":
        return actual == value
    if op == "!=":
        return actual != value
    if op == ">":
        return actual is not None and actual > value
    if op == ">=":
        return actual is not None and actual >= value
    if op == "<":
        return actual is not None and actual < value
    if op == "<=":
        return actual is not None and actual <= value
    if op == "in":
        return actual in value
    raise ValueError(f"Unsupported operator: {op}")


class FakeCollection:
    def __init__(self, store=None, key="root"):
        self._store = store if store is not None else {}
        self._key = key

    def document(self, doc_id=None):
        if doc_id is None:
            doc_id = f"auto_{next(_id_counter)}"
        return FakeDocument(self._store, doc_id)

    def add(self, data):
        doc_id = f"auto_{next(_id_counter)}"
        self._store[doc_id] = copy.deepcopy(data)
        return (None, FakeDocument(self._store, doc_id))

    def where(self, field, op, value):
        return FakeQuery(self._store, lambda doc_id, data: True).where(field, op, value)

    def stream(self):
        return [FakeSnapshot(doc_id, data) for doc_id, data in self._store.items() if doc_id != "__sub__"]


class FakeFirestoreClient:
    """Drop-in stand-in for firestore.Client() used only when no real credentials are configured."""

    def __init__(self):
        self._collections = {}

    def collection(self, name):
        if name not in self._collections:
            self._collections[name] = FakeCollection()
        return self._collections[name]
