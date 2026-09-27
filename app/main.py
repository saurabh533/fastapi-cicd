"""A tiny FastAPI app used to demo a CI/CD pipeline.

Everything is in-memory so it runs with zero external dependencies.
Change something here (e.g. bump the version, add an endpoint) to see the
whole pipeline light up.
"""
from fastapi import FastAPI, HTTPException

app = FastAPI(title="Demo API", version="1.0.0")

# Pretend database.
ITEMS: dict[int, dict] = {
    1: {"name": "Widget", "price": 9.99},
    2: {"name": "Gadget", "price": 19.99},
}


@app.get("/health")
def health():
    """Liveness probe. CI hits this, Cloud Run hits this."""
    return {"status": "ok"}


@app.get("/version")
def version():
    """Handy for confirming which build is actually deployed."""
    return {"version": app.version}


@app.get("/items/{item_id}")
def read_item(item_id: int):
    item = ITEMS.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Item not found")
    return {"item_id": item_id, **item}


@app.get("/items")
def list_items(max_price: float | None = None):
    items = [{"item_id": k, **v} for k, v in ITEMS.items()]
    if max_price is not None:
        items = [i for i in items if i["price"] <= max_price]
    return items
