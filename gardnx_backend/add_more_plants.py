import json
from pathlib import Path

# More plants
new_plant_names = [
    # More veg
    "Bell Pepper", "Cherry Tomato", "Zucchini", "Cauliflower", "Broccoli", 
    "Celery", "Leek", "Radish", "Turnip", "Beetroot",
    
    # More herbs
    "Basil", "Sage", "Tarragon", "Lavender", "Cumin",
    
    # More fruit
    "Watermelon", "Cantaloupe", "Lemon", "Lime", "Orange"
]

data_path = Path("app/data/plants_mauritius.json")

with open(data_path, "r", encoding="utf-8") as f:
    plants = json.load(f)

existing_ids = {p["id"] for p in plants}

for name in new_plant_names:
    plant_id = name.lower().replace(" ", "_")
    if plant_id in existing_ids:
        continue
    
    plants.append({
        "id": plant_id,
        "name": name,
        "name_fr": name,
        "scientific_name": f"{name} spp.",
        "type": "vegetable",
        "conditions": {
            "sunlight": "full_sun",
            "min_temp_c": 18,
            "max_temp_c": 35,
            "soil_types": ["loamy", "well_drained"],
            "water_needs": "moderate",
            "ph_min": 6.0,
            "ph_max": 7.0
        },
        "spacing": {
            "between_plants_cm": 40,
            "between_rows_cm": 60,
            "plant_width_cm": 40,
            "plant_height_cm": 60
        },
        "timing": {
            "sowing_months": [1, 2, 3, 9, 10, 11, 12],
            "transplant_months": [],
            "harvest_months": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            "days_to_germination": 7,
            "days_to_harvest": 60
        },
        "mauritius_regions": ["north", "south", "east", "west", "central"],
        "companion_plants": [],
        "incompatible_plants": [],
        "description": f"A wonderful tropical variety of {name.lower()} perfectly suited for Mauritius gardens.",
        "care_notes": "Water regularly and ensure good drainage.",
        "image_url": None
    })

with open(data_path, "w", encoding="utf-8") as f:
    json.dump(plants, f, indent=2)

print(f"Added {len(new_plant_names)} plants! Total is now {len(plants)}.")
