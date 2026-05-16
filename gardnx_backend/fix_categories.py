import json
from pathlib import Path

# Category classification — keyword rules (ordered: first match wins)
_CATEGORY_KEYWORDS = [
    ("herb", (
        "basil", "mint", "thyme", "parsley", "rosemary", "sage", "oregano",
        "cilantro", "coriander", "chive", "dill", "lavender", "lemon balm",
        "tarragon", "bay", "marjoram", "fennel", "anise", "chamomile",
        "stevia", "lemongrass", "curry leaf",
    )),
    ("fruit", (
        "apple", "pear", "peach", "plum", "cherry", "strawberry", "raspberry",
        "blueberry", "blackberry", "mango", "papaya", "banana", "pineapple",
        "grape", "citrus", "orange", "lemon", "lime", "melon", "watermelon",
        "passionfruit", "fig", "guava", "lychee", "avocado", "coconut",
        "jackfruit", "breadfruit", "starfruit", "carambola", "longan",
        "rambutan", "durian", "sapodilla", "soursop",
    )),
    ("vegetable", (
        "tomato", "lettuce", "cabbage", "carrot", "onion", "potato", "pepper",
        "chili", "chilli", "bean", "pea", "squash", "cucumber", "zucchini",
        "broccoli", "cauliflower", "spinach", "kale", "chard", "corn", "maize",
        "radish", "beet", "eggplant", "aubergine", "pumpkin", "okra", "garlic",
        "leek", "celery", "turnip", "sweet potato", "yam", "cassava",
        "artichoke", "asparagus", "brussels sprout", "collard", "mustard green",
        "watercress", "fennel bulb", "pak choi", "bok choy", "taro",
    )),
    ("flower", (
        "rose", "tulip", "daisy", "sunflower", "lily", "orchid", "marigold",
        "hibiscus", "jasmine", "peony", "daffodil", "dahlia", "iris", "poppy",
        "petunia", "zinnia", "begonia", "geranium", "pansy", "anthurium",
        "bougainvillea", "frangipani", "plumeria", "lantana", "heliconia",
        "bird of paradise", "strelitzia", "chrysanthemum", "carnation",
        "gerbera", "impatiens", "salvia", "verbena", "cosmos", "aster",
    )),
    ("ornamental", (
        "fern", "succulent", "cactus", "aloe", "agave", "palm", "bamboo",
        "grass", "sedge", "rush", "hosta", "philodendron", "pothos", "monstera",
        "dracaena", "sansevieria", "snake plant", "peace lily", "bromeliad",
        "air plant", "tillandsia", "calathea", "maranta", "dieffenbachia",
        "rubber plant", "fiddle leaf", "schefflera", "yucca",
    )),
    ("tree", (
        "tree", "oak", "maple", "pine", "eucalyptus", "teak", "mahogany",
        "neem", "moringa", "casuarina", "acacia", "tamarind",
    )),
    ("shrub", ("shrub", "hedge", "bush", "bougainvillea shrub")),
]

data_path = Path("app/data/plants_mauritius.json")

with open(data_path, "r", encoding="utf-8") as f:
    plants = json.load(f)

for p in plants:
    if "perenual" in p.get("tags", []):
        name = p.get("name", "").lower()
        sci = p.get("scientific_name", "").lower()
        haystack = f"{name} {sci}"
        found_category = "ornamental"
        for category, keywords in _CATEGORY_KEYWORDS:
            if any(kw in haystack for kw in keywords):
                found_category = category
                break
        
        # update the type
        if p.get("type") == "vegetable" and found_category != "vegetable":
            p["type"] = found_category

with open(data_path, "w", encoding="utf-8") as f:
    json.dump(plants, f, indent=2)

print("Updated categories for perenual plants!")
