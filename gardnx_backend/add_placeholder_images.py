import json
import urllib.parse
from pathlib import Path

data_path = Path("app/data/plants_mauritius.json")

with open(data_path, "r", encoding="utf-8") as f:
    plants = json.load(f)

for p in plants:
    if not p.get("image_url"):
        safe_name = urllib.parse.quote(p["name"])
        p["image_url"] = f"https://placehold.co/600x400/2E7D32/FFFFFF/png?text={safe_name}"

with open(data_path, "w", encoding="utf-8") as f:
    json.dump(plants, f, indent=2)

print("Updated image URLs with placeholders!")
