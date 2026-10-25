"""
Connectivity test for the free food databases. Run from the backend folder:
    python scripts/check_foods.py
"""
import time

from dotenv import load_dotenv

load_dotenv()

import urllib3.util.connection as c
c.HAS_IPV6 = False  # same setting the server uses

from app import foods

for name, fn, query in (("USDA", foods._search_usda, "chicken breast"), ("Open Food Facts", foods._search_off, "nasi lemak")):
    t = time.monotonic()
    try:
        items = fn(query)
        print(f"{name}: {len(items)} results for '{query}' in {time.monotonic() - t:.1f}s")
        for i in items[:3]:
            print("   ", i["name"], i["per100g"])
    except Exception as e:
        print(f"{name}: FAILED after {time.monotonic() - t:.1f}s: {e!r}")
