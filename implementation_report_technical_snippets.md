# Technical Snippet Explanations — myGardenPlanner

---

### Snippet 1 — Sign-in and Sign-up Providers
**File:** `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart` · lines 30–66

Each provider holds a function as its value — not a simple piece of data, but a callable action. Any screen in the app can grab this function using `ref.read(signInProvider)` and call it with an email and password. The actual Firebase login is handled inside `AuthRepository`, which means screens never touch Firebase directly — they only call the provider, and the provider calls the repository. This separation means if Firebase changes, only the repository needs to be updated, not every screen.

---

### Snippet 2 — Loading Plants from Firestore with Local Fallback
**File:** `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart` · lines 22–47

The function checks three sources in order. First, it checks if plants were already loaded this session and returns them instantly without a network call. If not, it queries Firestore over the internet. If Firestore fails for any reason, the error is silently ignored and the function reads from a JSON file bundled inside the app itself. Each `Plant.fromFirestore(doc)` call converts a raw Firestore document into a typed Dart object. The result is the same regardless of which source succeeded.

---

### Snippet 3 — AI-Powered Plant Recommendation with Fallback Chain
**File:** `gardnx_backend/app/api/v1/endpoints/layout.py` · lines 186–226

This is a FastAPI endpoint — a web address the app can call. Before it runs, FastAPI automatically checks the Firebase login token in the request header and rejects the call if the token is invalid. The recommendation logic loops through two AI engines — Gemini first, then Ollama — and stops as soon as one returns results. If both fail or return nothing, the code falls through to the rule-based scorer. The `await` keyword is used when calling AI engines because those calls involve waiting for an external server to respond.

---

### Snippet 4 — Calling Gemini with 24-Hour Result Cache
**File:** `gardnx_backend/app/services/gemini_recommender.py` · lines 107–135

Before calling Gemini, the code builds a cache key by joining the four request values — sunlight, region, month, and preferences — into a single string like `"full_sun|North|4|vegetables"`. This key is looked up in a dictionary stored in server memory. If a result for that key was stored less than 24 hours ago, it is returned immediately without calling Gemini. If not, Gemini is called using `generate_content_async()` — the async version so the server is not blocked while waiting — and the result is stored in the dictionary for next time.

---

### Snippet 5 — Weighted Scoring of Plants Without AI
**File:** `gardnx_backend/app/services/plant_recommender.py` · lines 68–112

The scorer runs in two stages. First, hard filters remove plants that cannot possibly work — for example a shade plant in a full sun bed is removed immediately. Then each remaining plant gets five sub-scores between 0 and 1, multiplied by weights that add up to exactly 1.0: sunlight match (25%), planting season (25%), temperature (20%), region (15%), preferences (15%). These are added together to give a total score. Plants are then sorted from highest to lowest and the top 20 are returned. This entire process needs no internet connection.

---

### Snippet 6 — AI Segmentation with PIL Colour Fallback
**File:** `gardnx_backend/app/services/garden_analyzer.py` · lines 76–119

The photo is first sent to the Hugging Face API, which runs a Segformer model — a neural network that labels every pixel in the image with a category like grass, soil, or path. If that API call fails or times out, the code falls back to PIL, which analyses pixel colours directly using HSV ranges (Hue, Saturation, Value) — for example brown pixels are classified as soil, green pixels as lawn. Either way, the result includes a confidence score. If the average confidence across all zones is below 50%, a `fallback_recommended` flag is set to true, telling the app to warn the user to review the results.

---

### Snippet 7 — Saving Layout and Auto-Generating Calendar
**File:** `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart` · lines 147–210

`layoutNotifierProvider` is a `StateNotifierProvider` — a Riverpod provider that holds state and exposes methods to change it. Calling `.notifier` gives access to those methods, and `saveCurrentLayout()` writes the layout to Firestore and returns the new document ID. After the save succeeds, `_generateAndSaveCalendar()` is called without `await` — this means it runs in the background while the screen returns immediately and shows "Layout saved!" to the user. Inside that background function, `allPlantsProvider.future` is awaited to get the full plant list needed to compute calendar dates.

---

### Snippet 8 — Computing Sow, Transplant, and Harvest Dates
**File:** `gardnx_backend/app/services/calendar_service.py` · lines 22–94

For each plant, the code finds the next calendar month that falls within the plant's allowed sowing months — for example, if today is April and the plant sows in October, it calculates October's date. Transplant and harvest dates are then computed by adding days to that sow date using `timedelta` — Python's way of doing date arithmetic. All dates are stored as ISO 8601 strings (`"2026-10-01"`) because this format sorts alphabetically in the same order as chronologically, which makes the final `events.sort()` work correctly without any special date comparison logic.

---

### Snippet 9 — Sending Plant Data to Backend and Saving Events to Firestore
**File:** `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart` · lines 33–88

The Dio HTTP client has an `AuthInterceptor` attached to it. This interceptor runs automatically before every request and adds the user's Firebase login token to the request header — so the backend knows who is making the call without the repository needing to handle this manually. The plant data is sent as a JSON body in a POST request. The response JSON is then converted into typed `PlantingEvent` Dart objects using `PlantingEventTypeExt.fromValue()` to turn strings like `"sow"` into enum values. Events are written to Firestore using a `WriteBatch`, which sends all writes in a single network round-trip rather than one call per event.

---

### Snippet 10 — Showing Global Search Results with Loading and Error States
**File:** `gardnx_app/lib/features/plant_database/presentation/screens/plant_catalog_screen.dart` · lines 318–376

`globalPlantSearchProvider` is defined as `FutureProvider.family.autoDispose` — `family` means it accepts a query string as a parameter so each search term gets its own independent provider instance, and `autoDispose` means the provider and its in-flight network request are automatically cancelled when the user leaves the screen. `ref.watch()` subscribes the widget to the provider so it rebuilds automatically when results arrive. The `.when()` call handles all three states that an async result can be in — loading, data, and error — and the Dart compiler enforces that all three are handled, so a blank screen or unhandled crash is not possible.

---

## Summary Table

| # | Snippet | Key Technical Points |
|---|---------|----------------------|
| 1 | Auth Providers | Riverpod callable provider, repository pattern |
| 2 | Plant Fallback | Three-layer cache, factory constructor, bundled asset |
| 3 | Recommendation Chain | FastAPI auth dependency, async engine loop |
| 4 | Gemini Cache | Composite string key, in-memory TTL dictionary |
| 5 | Rules Scorer | Hard filter + weighted linear scoring, sorted top 20 |
| 6 | Photo Analysis | Segformer pixel labelling, PIL HSV fallback |
| 7 | Layout Save | StateNotifier, fire-and-forget, FutureProvider.future |
| 8 | Calendar Dates | timedelta arithmetic, ISO 8601 string sort |
| 9 | HTTP + Firestore | AuthInterceptor middleware, WriteBatch commit |
| 10 | Search Widget | family + autoDispose provider, exhaustive .when() |
