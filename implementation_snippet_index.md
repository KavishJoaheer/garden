# Code Snippet Index — myGardenPlanner Implementation Report

All snippets referenced in `implementation_report_simple.md`, with exact file paths and line numbers.

---

| # | Module | File | Lines | Title |
|---|--------|------|-------|-------|
| 1 | User Authentication | `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart` | 30–66 | Sign-in and Sign-up Providers |
| 2 | Plant Catalog / Firestore | `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart` | 22–47 | Loading Plants from Firestore with Local Fallback |
| 3 | Plant Recommendation | `gardnx_backend/app/api/v1/endpoints/layout.py` | 186–226 | AI-Powered Plant Recommendation with Fallback Chain |
| 4 | Gemini AI Recommender | `gardnx_backend/app/services/gemini_recommender.py` | 107–135 | Calling Gemini with 24-Hour Result Cache |
| 5 | Rules Engine Fallback | `gardnx_backend/app/services/plant_recommender.py` | 68–112 | Weighted Scoring of Plants Without AI |
| 6 | Garden Photo Analysis | `gardnx_backend/app/services/garden_analyzer.py` | 76–119 | AI Segmentation with PIL Colour Fallback |
| 7 | Layout Save + Calendar | `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart` | 147–210 | Saving Layout and Auto-Generating Calendar |
| 8 | Calendar Generation | `gardnx_backend/app/services/calendar_service.py` | 22–94 | Computing Sow, Transplant, and Harvest Dates |
| 9 | API Communication | `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart` | 33–88 | Sending Plant Data to Backend and Saving Events to Firestore |
| 10 | Global Plant Search | `gardnx_app/lib/features/plant_database/presentation/screens/plant_catalog_screen.dart` | 318–376 | Showing Global Search Results with Loading and Error States |

---

## Snippet Details

### Snippet 1 — Auth Providers
**File:** `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart:30–66`
**Key pattern:** Riverpod `Provider` wrapping `AuthRepository` sign-in / sign-up methods.
**Why notable:** All screens call the provider — no direct Firebase SDK usage in UI layer.

---

### Snippet 2 — Plant Repository with Fallback
**File:** `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart:22–47`
**Key pattern:** Cache → Firestore → bundled JSON asset (three-layer).
**Why notable:** Guarantees the plant list is always available, even offline.

---

### Snippet 3 — Recommendation Endpoint Fallback Chain
**File:** `gardnx_backend/app/api/v1/endpoints/layout.py:186–226`
**Key pattern:** `for eng_name, eng in [("gemini", gemini), ("ollama", ollama)]` — loop tries each engine, breaks on first success.
**Why notable:** Graceful degradation — Gemini → Ollama → rules. User never sees an empty recommendation screen.

---

### Snippet 4 — Gemini Cache
**File:** `gardnx_backend/app/services/gemini_recommender.py:107–135`
**Key pattern:** `_cache_key(req)` → in-memory dict with 24 h TTL before calling `generate_content_async`.
**Why notable:** Prevents repeated Gemini API calls for identical bed conditions (same sun/region/month/prefs).

---

### Snippet 5 — Rules-Based Scorer
**File:** `gardnx_backend/app/services/plant_recommender.py:68–112`
**Key pattern:** Five weighted subscores — `W_SUN=0.25, W_SEASON=0.25, W_TEMP=0.20, W_REGION=0.15, W_PREF=0.15`.
**Why notable:** Zero internet/AI dependency — always produces results.

---

### Snippet 6 — Garden Analyzer
**File:** `gardnx_backend/app/services/garden_analyzer.py:76–119`
**Key pattern:** `_ml_analyze` tries Hugging Face Segformer; on exception falls to `_colour_analyze` (PIL).
**Why notable:** `fallback_recommended` flag returned to app when confidence < 0.5.

---

### Snippet 7 — Layout Save + Calendar Trigger
**File:** `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart:147–210`
**Key pattern:** `_generateAndSaveCalendar()` called fire-and-forget after layout save success.
**Why notable:** Calendar generation does not block the save UX — user sees "Layout saved!" immediately.

---

### Snippet 8 — Calendar Service
**File:** `gardnx_backend/app/services/calendar_service.py:22–94`
**Key pattern:** `_next_date_for_months` → sow date → `sow + germination + 14` → transplant → `sow + days_to_harvest` → harvest.
**Why notable:** Events sorted by `start_date`; urgent events (≤ 14 days) flagged `priority="high"`.

---

### Snippet 9 — Calendar Repository HTTP Call
**File:** `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart:33–88`
**Key pattern:** `_dio.post('/calendar/generate', data: {...})` with `AuthInterceptor` injecting Firebase Bearer token.
**Why notable:** `DioException` caught silently → caller handles empty list → local fallback kicks in.

---

### Snippet 10 — Global Search Widget
**File:** `gardnx_app/lib/features/plant_database/presentation/screens/plant_catalog_screen.dart:318–376`
**Key pattern:** `ref.watch(globalPlantSearchProvider(query)).when(data:..., loading:..., error:...)`.
**Why notable:** Three-state `.when()` covers all cases — no blank screens or unhandled async states.

---

## Backend Endpoints Cross-Reference

| Endpoint | File | Snippet # |
|----------|------|-----------|
| `POST /layout/recommend` | `gardnx_backend/app/api/v1/endpoints/layout.py` | 3 |
| `POST /layout/generate` | `gardnx_backend/app/api/v1/endpoints/layout.py` | — |
| `POST /layout/validate` | `gardnx_backend/app/api/v1/endpoints/layout.py` | — |
| `POST /analysis/upload` | `gardnx_backend/app/api/v1/endpoints/analysis.py` | — |
| `POST /analysis/segment/{id}` | `gardnx_backend/app/api/v1/endpoints/analysis.py` | 6 (service) |
| `POST /calendar/generate` | `gardnx_backend/app/api/v1/endpoints/calendar.py` | 8 (service), 9 (client) |
| `GET /plants/catalog` | `gardnx_backend/app/api/v1/endpoints/plants.py` | — |
| `GET /plants/search` | `gardnx_backend/app/api/v1/endpoints/plants.py` | 10 (client) |
| `GET /climate/current` | `gardnx_backend/app/api/v1/endpoints/climate.py` | — |
| `GET /climate/monthly` | `gardnx_backend/app/api/v1/endpoints/climate.py` | — |
