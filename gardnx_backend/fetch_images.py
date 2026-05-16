import json
import urllib.request
import urllib.parse
from pathlib import Path
import time

data_path = Path("app/data/plants_mauritius.json")

with open(data_path, "r", encoding="utf-8") as f:
    plants = json.load(f)

print(f"Loaded {len(plants)} plants.")

changes = 0
for p in plants:
    if p.get("image_url"):
        continue
    
    name = p["name"]
    # Quick fix for scientific names
    if "spp." in p.get("scientific_name", ""):
        p["scientific_name"] = name
        
    query = urllib.parse.quote(name)
    url = f"https://en.wikipedia.org/w/api.php?action=query&titles={query}&prop=pageimages&format=json&pithumbsize=600"
    
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            pages = data["query"]["pages"]
            for page_id, page_data in pages.items():
                if "thumbnail" in page_data:
                    p["image_url"] = page_data["thumbnail"]["source"]
                    print(f"Found image for {name}: {p['image_url']}")
                    changes += 1
                    break
    except Exception as e:
        print(f"Failed to fetch image for {name}: {e}")
    
    time.sleep(0.1) # Be nice to wikipedia

with open(data_path, "w", encoding="utf-8") as f:
    json.dump(plants, f, indent=2)

print(f"Added {changes} images!")
