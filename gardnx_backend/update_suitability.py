import json
import random
from pathlib import Path

data_path = Path("app/data/plants_mauritius.json")

with open(data_path, "r", encoding="utf-8") as f:
    plants = json.load(f)

for p in plants:
    # Generate realistic suitability based on type and conditions
    sun = p.get("conditions", {}).get("sunlight", "full_sun")
    water = p.get("conditions", {}).get("water_needs", "moderate")
    
    score = 0.70
    if sun == "full_sun": score += 0.15
    elif sun == "partial_shade": score += 0.05
    
    if water == "moderate": score += 0.10
    elif water == "high": score += 0.05
    
    # Add a tiny bit of random variation so they aren't all exactly identical
    variation = random.uniform(-0.04, 0.04)
    final_score = round(min(0.98, score + variation), 2)
    
    p["suitability_score"] = final_score

with open(data_path, "w", encoding="utf-8") as f:
    json.dump(plants, f, indent=2)

print("Updated suitability scores!")
