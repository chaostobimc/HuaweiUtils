"""
Test Client für Backend - testet alle Endpoints
"""
import requests
import json

BASE = "http://localhost:8000"

def test_health():
    r = requests.get(f"{BASE}/health")
    print("Health:", r.json())
    assert r.status_code == 200

def test_features():
    r = requests.get(f"{BASE}/api/features")
    print("Features:", json.dumps(r.json(), indent=2))

def test_chat(prompt="Hallo, wer bist du?"):
    r = requests.post(f"{BASE}/api/chat", json={"prompt": prompt, "id": "test1"})
    print(f"\nChat '{prompt}':")
    print(json.dumps(r.json(), indent=2, ensure_ascii=False))

def test_all():
    test_health()
    test_features()
    test_chat("Was ist 2+2?")
    # Weitere Tests
    for endpoint, prompt in [
        ("/api/summarize", "Python ist eine Programmiersprache..."),
        ("/api/translate", "Hallo Welt"),
        ("/api/explain", "Quantencomputing"),
        ("/api/weather", "Wetter in Berlin"),
    ]:
        r = requests.post(f"{BASE}{endpoint}", json={"prompt": prompt, "id": "test"})
        print(f"\n{endpoint} '{prompt}': {r.json().get('response','')[:200]}")

if __name__ == "__main__":
    test_all()
