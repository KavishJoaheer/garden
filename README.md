# 🌱 GardNx — AI Garden Planner

A mobile garden planning app for Mauritius home gardeners.
Take a photo of your garden → get plant recommendations → generate a layout → get a planting calendar.

**Platform:** Android (physical device or emulator, API 24+)
**Stack:** Flutter 3.27 · Python 3.11+ FastAPI · Firebase Firestore/Auth · Gemini AI

---

## Quick look

| Feature | How it works |
|---|---|
| 📸 Photo analysis | Photo → HuggingFace segmentation → sunny/shady/soil zones |
| 🌿 Plant recommendations | Zones + season + region → ranked list from 40+ Mauritius plants |
| 🗺️ Layout planner | Auto-generate or drag-and-drop grid with spacing rules |
| 📅 Planting calendar | Auto-generated month-by-month task schedule |
| 🌍 Climate data | Free Open-Meteo historical weather by GPS |

---

## Setting up on a new machine

See the full step-by-step guide: **[SETUP_GUIDE.md](SETUP_GUIDE.md)**
Or specifically for mobile: **[MOBILE_SETUP.md](MOBILE_SETUP.md)**


The short version:

```bash
# 1 — Backend
cd gardnx_backend
python -m venv venv
venv\Scripts\activate          # Windows PowerShell: .\venv\Scripts\Activate.ps1
pip install -r requirements.txt
cp .env.example .env           # then fill in your API keys
# place firebase-credentials.json here (download from Firebase Console)
python scripts/seed_database.py
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 2 — Flutter app (new terminal)
cd gardnx_app
# edit lib/config/constants/api_constants.dart — set your PC's local IP
flutter pub get
flutter run
```

---

## Repo structure

```
gardnx/
├── gardnx_app/          Flutter Android app
├── gardnx_backend/      Python FastAPI backend
│   ├── .env.example     Copy to .env and fill in your keys
│   └── scripts/         seed_database.py — populates Firestore
└── firebase/            Firestore security rules + indexes
```

---

## Files you must supply yourself (not in the repo)

| File | Where to get it |
|---|---|
| `gardnx_backend/.env` | Copy `.env.example` and fill in your values |
| `gardnx_backend/firebase-credentials.json` | Firebase Console → Project Settings → Service Accounts → Generate new private key |
| `gardnx_app/android/app/google-services.json` | Firebase Console → Project Settings → Your apps → Download |

These files contain secrets and are excluded from version control by `.gitignore`.
