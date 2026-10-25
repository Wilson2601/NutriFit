"""
Quick connectivity test for the AI food check. Run from the backend folder:
    python scripts/check_gemini.py
Prints how long each step takes so slow networks are easy to spot.
"""
import os
import socket
import time

from dotenv import load_dotenv
import requests

load_dotenv()
key = os.environ.get("GEMINI_API_KEY")
model = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
host = "generativelanguage.googleapis.com"

if not key:
    raise SystemExit("GEMINI_API_KEY is not set. Put it in backend/.env first.")

t = time.monotonic()
infos = socket.getaddrinfo(host, 443)
print(f"DNS lookup: {time.monotonic() - t:.1f}s -> {sorted({('IPv6' if i[0] == socket.AF_INET6 else 'IPv4') for i in infos})}")

import urllib3.util.connection as c
c.HAS_IPV6 = False  # same setting the server uses

t = time.monotonic()
try:
    r = requests.post(
        f"https://{host}/v1beta/models/{model}:generateContent",
        headers={"x-goog-api-key": key, "Content-Type": "application/json"},
        json={"contents": [{"parts": [{"text": "Reply with the single word: ok"}]}]},
        timeout=(5, 20),
    )
    print(f"HTTP {r.status_code} in {time.monotonic() - t:.1f}s")
    print(r.text[:300])
except Exception as e:
    print(f"FAILED after {time.monotonic() - t:.1f}s: {e!r}")
