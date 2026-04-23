# Implementation Report — myGardenPlanner

---

## 1. Introduction

myGardenPlanner is a mobile app that helps people plan their garden layouts and get advice on which plants to grow. Using your phone's camera, you can take a photo of your garden and the app will analyse it to identify usable growing areas. You can also draw your garden manually on screen. Once you have a garden set up, the app recommends plants that suit your conditions — things like how sunny the spot is, what time of year it is, and where in Mauritius you are located. The app then helps you arrange those plants in a grid layout, and automatically adds planting reminders to a calendar so you know when to sow, transplant, and harvest.

This report covers what has actually been built and is working in the current codebase. It is based entirely on code that exists in the project right now.

The app is built with **Flutter** (the mobile front-end), **FastAPI** (the Python server), **Firebase** (for storing data and handling logins), and several AI services for smart recommendations.

---

## 2. Major Implemented Modules and Features

### 2.1 User Authentication

**What it does:** Lets users create an account, log in, reset their password, and delete their account.

**Why it matters:** Every feature in the app is tied to a specific user. Without authentication, the app cannot know whose garden belongs to whom, or protect anyone's data.

**How it works:** The app uses Firebase Authentication, which is Google's secure login service. When a user types their email and password and taps "Sign In", the app sends those details to Firebase. If correct, Firebase returns a secure token (a kind of digital key) that the app attaches to every future request — to the database and to the backend server. The app watches for changes in login status automatically. If a user is logged out, every screen redirects to the login page immediately.

**Main files:**
- `gardnx_app/lib/features/auth/presentation/screens/login_screen.dart`
- `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart`
- `gardnx_app/lib/features/auth/data/repositories/auth_repository.dart`
- `gardnx_app/lib/shared/providers/firebase_providers.dart`

---

### 2.2 User Profile

**What it does:** Displays the user's name, email, profile photo, experience level, plant preferences, and region. All of these can be edited in the app.

**Why it matters:** The profile stores personal preferences that feed into plant recommendations. For example, if you say you prefer vegetables, the recommendation engine will rank vegetable plants higher.

**How it works:** Profile data is stored in Firestore (Google's cloud database) under a `users` collection, with each user having their own document identified by their unique user ID. When the profile screen opens, it reads this document and displays the data. Profile photo uploads go to Firebase Storage (a cloud file store), and the URL is then saved back into the Firestore profile document.

**Main files:**
- `gardnx_app/lib/features/profile/presentation/screens/profile_screen.dart`
- `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart`

---

### 2.3 Firestore Database Integration

**What it does:** Stores and retrieves all app data — gardens, beds, plant layouts, calendar events, tasks, and user profiles — using Firebase's cloud database called Firestore.

**Why it matters:** This is the backbone of the app. Without Firestore, nothing would be saved between sessions. Every garden you create, every layout you save, every planting reminder — all of it lives in Firestore.

**How it works:** The app organises data into collections (like folders). Gardens are stored in a `gardens` collection. Each garden has sub-collections for its beds, layouts, events (calendar), and tasks. The app reads and writes to these using the Firebase SDK. Security rules in Firestore ensure that users can only read and write their own data.

**Data structure used:**
```
/plants/{plantId}               — plant catalog
/users/{userId}                 — user profiles
/gardens/{gardenId}             — garden metadata
  /beds/{bedId}                 — garden beds
  /layouts/{layoutId}           — plant placements
  /events/{eventId}             — calendar events
  /tasks/{taskId}               — planting tasks
```

**Main files:**
- `gardnx_app/lib/shared/providers/firebase_providers.dart`
- `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart`
- `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart`
- `firebase/firestore.rules`

---

### 2.4 Plant Catalog and Search

**What it does:** Shows users a browsable list of plants suited to Mauritius, with filters for type (vegetable, herb, fruit, flower), sunlight needs, season, and region. Users can also search a global plant database powered by Perenual (an external plant API).

**Why it matters:** Users need to know what plants exist and what conditions they need before they can plan a layout. The global search also lets users find plants not in the local Mauritius collection and save them.

**How it works:** Local plants are fetched from Firestore's `plants` collection. If Firestore is unavailable, the app falls back to a bundled JSON file included in the app package. Global search queries the backend server, which calls the Perenual plant API and returns results in a compatible format. Both local and global results appear on the same catalog screen in separate sections.

**Main files:**
- `gardnx_app/lib/features/plant_database/presentation/screens/plant_catalog_screen.dart`
- `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart`
- `gardnx_app/lib/features/plant_database/presentation/providers/plant_provider.dart`
- `gardnx_backend/app/api/v1/endpoints/plants.py`
- `gardnx_backend/app/services/perenual_service.py`

---

### 2.5 Garden Photo Capture and Analysis

**What it does:** Lets the user take a photo of their garden or choose one from their gallery. The photo is sent to the server, which analyses it using AI to detect different zones — for example, soil areas, lawn, paths, and existing plants.

**Why it matters:** This is one of the core AI features of the app. It removes the need for users to manually measure and describe their garden. The app looks at the photo and figures out which parts are plantable.

**How it works:** The user taps "Take Photo" or "Choose from Gallery". The app checks for camera/gallery permission first. Once an image is selected, the user can crop the area they care about. The image is then uploaded to the backend via an HTTP request. The backend uses a machine learning model from Hugging Face (a research platform that hosts AI models) called Segformer, which was trained to recognise outdoor scenes. The model labels different parts of the image — grass, dirt, paths, plants — and the backend maps these to garden zone types. If the AI model fails or is slow, the backend falls back to a simpler colour-based analysis using pixel brightness and colour patterns. The zones are returned to the app, where the user can select which ones to include.

**Main files:**        
- `gardnx_app/lib/features/garden_analysis/presentation/screens/capture_screen.dart`
- `gardnx_app/lib/features/garden_analysis/presentation/screens/analysis_result_screen.dart`
- `gardnx_app/lib/features/garden_analysis/presentation/providers/analysis_provider.dart`
- `gardnx_backend/app/api/v1/endpoints/analysis.py`
- `gardnx_backend/app/services/garden_analyzer.py`
- `gardnx_backend/app/services/hf_garden_analyzer.py`

---

### 2.6 Manual Bed Drawing

**What it does:** Lets users who prefer not to use a photo draw their garden beds directly on screen by dragging rectangles on a canvas.

**Why it matters:** Not every user wants to use the camera. Manual drawing gives everyone a way to get started regardless of lighting conditions or phone camera quality.

**How it works:** The screen shows a blank canvas. The user drags their finger to draw a rectangular bed. They can add multiple beds and tap each one to edit its name, size in centimetres, sun exposure (full sun, partial shade, full shade), and soil type. When they tap "Done", the app asks for a garden name (if this is a new garden), checks the user's location (defaulting to "North" region if location is denied), creates a garden document in Firestore, and saves each bed as a sub-document. It then navigates to the recommendation screen, passing along the bed details.

**Main files:**
- `gardnx_app/lib/features/manual_input/presentation/screens/manual_input_screen.dart`
- `gardnx_app/lib/features/manual_input/presentation/providers/manual_input_provider.dart`

---

### 2.7 Plant Recommendation Engine

**What it does:** Recommends plants that are well-suited to the user's garden bed based on sun exposure, soil type, season, region, and personal preferences.

**Why it matters:** This is the core intelligence of the app. Instead of users having to research every plant themselves, the app suggests which plants are most likely to thrive in their specific conditions.

**How it works:** The recommendation system uses three engines in priority order:

1. **Gemini AI** (Google's AI model, version 2.5 Flash Lite): The backend sends a prompt to Gemini describing the garden bed — sun level, region, month, temperature, and user preferences — along with a list of all available plants. Gemini reads this and returns a ranked list with scores and reasons. Results are cached for 24 hours so the same query does not repeatedly call the AI.

2. **Ollama** (a locally running AI): If Gemini is unavailable, the backend tries a locally hosted AI model called Gemma, running through a tool called Ollama. This works without internet access.

3. **Rule-based scoring**: If both AI options fail, the backend scores each plant mathematically using five factors — sunlight match, sowing season, temperature range, region suitability, and user preferences — each weighted differently. This always produces results regardless of internet availability.

**Main files:**
- `gardnx_backend/app/api/v1/endpoints/layout.py` (recommend endpoint)
- `gardnx_backend/app/services/gemini_recommender.py`
- `gardnx_backend/app/services/ollama_recommender.py`
- `gardnx_backend/app/services/plant_recommender.py`
- `gardnx_app/lib/features/layout_planner/presentation/screens/recommendation_screen.dart`
- `gardnx_app/lib/features/layout_planner/presentation/providers/recommendation_provider.dart`

---

### 2.8 Garden Layout Planning

**What it does:** Takes the plants the user selected and arranges them into a visual grid showing where each plant should go in the garden bed. The user can also manually adjust the layout or add plants one by one.

**Why it matters:** Spacing plants correctly matters for healthy growth. Planting things too close together or next to incompatible plants can cause problems. The layout tool automates the spacing calculation.

**How it works:** The user selects plants from the recommendation screen and taps "Generate Layout". The app sends the bed dimensions and chosen plants to the backend. The backend calculates a grid size based on the smallest plant spacing in the selection, then uses a greedy placement algorithm — placing the largest plants first, checking for incompatible neighbours, and filling remaining spaces. It returns a list of grid positions. The Flutter app draws these as a colour-coded grid where each cell shows which plant occupies it. If the backend returns nothing, the app distributes plants evenly across columns as a fallback. The layout is saved to Firestore when the user taps "Save".

**Main files:**
- `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart`
- `gardnx_backend/app/api/v1/endpoints/layout.py` (generate endpoint)
- `gardnx_backend/app/services/layout_generator.py`
- `gardnx_backend/app/services/spacing_calculator.py`

---

### 2.9 Companion Planting Validation

**What it does:** Checks whether the plants placed next to each other in the layout are compatible. Some plants help each other grow (companion plants), while others harm each other (incompatible plants).

**Why it matters:** A layout that looks fine visually might be harmful to plants if incompatible species are placed side by side. This check adds a layer of gardening knowledge on top of the spatial arrangement.

**How it works:** After layout generation, the backend checks every pair of neighbouring plants against companion planting rules. This check can use Gemini AI for nuanced reasoning, or fall back to a local rules database if Gemini is unavailable. Warnings are returned to the app and shown to the user.

**Main files:**
- `gardnx_backend/app/api/v1/endpoints/layout.py` (validate endpoint)
- `gardnx_backend/app/services/gemini_companion_checker.py`
- `gardnx_backend/app/services/companion_checker.py`

---

### 2.10 Planting Calendar and Task Generation

**What it does:** After saving a layout, the app automatically generates a planting calendar — a list of dated reminders for when to sow, transplant, and harvest each plant. These appear on a calendar screen with colour-coded dots.

**Why it matters:** Knowing what to plant when is as important as knowing what to plant. The calendar removes the need for users to look up planting dates manually.

**How it works:** After a layout is saved, the app calls the backend with the list of placed plants and their timing data. The backend's calendar service computes the next appropriate sowing date for each plant (based on the current month and the plant's sowing months), then adds transplanting and harvest events calculated from the plant's days-to-maturity figure. The generated events are sent back to the app and saved to Firestore under the garden's `events` and `tasks` sub-collections. If the backend is unavailable, the app generates basic sow and harvest events locally using the plant timing data it already has. Events are displayed on a `TableCalendar` widget, and users can tap an event to mark it as done.

**Main files:**
- `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart`
- `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart`
- `gardnx_app/lib/features/calendar/presentation/screens/calendar_screen.dart`
- `gardnx_app/lib/features/calendar/presentation/providers/calendar_provider.dart`
- `gardnx_backend/app/api/v1/endpoints/calendar.py`
- `gardnx_backend/app/services/calendar_service.py`

---

### 2.11 Backend API (FastAPI)

**What it does:** The Python backend is the brain behind the AI features. It handles photo analysis, plant recommendations, layout generation, and calendar generation. The Flutter app talks to it over the internet using standard HTTP requests.

**Why it matters:** Heavy computations — calling Gemini AI, running image segmentation, calculating grid layouts — are all done on the server, not the phone. This keeps the app fast and light.

**How it works:** The backend is built with FastAPI, a Python web framework. It exposes a set of endpoints (web addresses the app can call), each protected by Firebase token verification — the app must include a valid Firebase login token in every request. The backend reads the token, verifies it, and only then processes the request.

**Endpoints implemented:**
- `POST /layout/recommend` — plant recommendations
- `POST /layout/generate` — grid layout
- `POST /layout/validate` — companion check
- `POST /analysis/upload` — photo upload
- `POST /analysis/segment/{id}` — AI segmentation
- `POST /calendar/generate` — calendar events
- `GET /plants/catalog` — plant list
- `GET /plants/search` — global plant search
- `GET /climate/current` and `/climate/monthly` — weather data

**Main files:**
- `gardnx_backend/app/main.py`
- `gardnx_backend/app/api/v1/endpoints/` (all endpoint files)
- `gardnx_backend/app/api/deps.py`

---

### 2.12 Location and Climate Awareness

**What it does:** The app detects the user's location and uses it to provide region-specific plant recommendations and current climate data.

**Why it matters:** Mauritius has different climate zones — the north is drier and hotter, the south is cooler and wetter. Recommending the same plants everywhere would not be accurate.

**How it works:** The app requests location permission when the user first creates a garden. If permission is granted, it uses the GPS coordinates to determine which Mauritius region the user is in. If permission is denied, it defaults to "North". The backend also has endpoints that call Open-Meteo (a free weather API) to get current temperature and monthly climate averages, which feed into the recommendation engine.

**Main files:**
- `gardnx_app/lib/features/climate/presentation/providers/location_provider.dart`
- `gardnx_app/lib/features/climate/data/repositories/climate_repository.dart`
- `gardnx_backend/app/services/climate_service.py`
- `gardnx_backend/app/api/v1/endpoints/climate.py`

---

### 2.13 App Navigation and Routing

**What it does:** Controls how the user moves between screens. If the user is not logged in, they are redirected to the login screen. Once logged in, they go to the home screen. A tab bar at the bottom gives quick access to the main sections.

**Why it matters:** Clean navigation prevents users from reaching screens they should not access and makes the app easy to use.

**How it works:** Navigation uses a package called go_router. The router watches the auth state — as soon as a user logs in or out, the router automatically redirects to the correct screen. The home screen has four tabs: Dashboard (gardens list), Plants (catalog), Calendar, and Profile. Complex flows like garden creation pass data between screens using route parameters.

**Main files:**
- `gardnx_app/lib/config/router/app_router.dart`
- `gardnx_app/lib/features/home/presentation/screens/home_screen.dart`

---

## 3. Code Snippets for Key Implemented Modules

---

### Snippet 1 — User Authentication

**Module:** User Authentication
**File:** `gardnx_app/lib/features/auth/presentation/providers/auth_provider.dart`
**Lines:** 30–66
**Title:** Sign-in and Sign-up Providers

```dart
final signInProvider = Provider<
    Future<UserCredential> Function({
      required String email,
      required String password,
    })>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return ({required String email, required String password}) {
    return repo.signInWithEmail(email: email, password: password);
  };
});

final signUpProvider = Provider<
    Future<UserCredential> Function({
      required String email,
      required String password,
      required String displayName,
    })>((ref) {
  final repo = ref.read(authRepositoryProvider);
  return ({
    required String email,
    required String password,
    required String displayName,
  }) {
    return repo.signUpWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    );
  };
});
```

**Explanation:** This code creates two reusable login functions — one for signing in and one for registering a new account. They both use a "repository" (a helper that talks to Firebase). When any screen in the app needs to log in a user, it simply calls `ref.read(signInProvider)` and passes the email and password. The result comes back from Firebase. If login fails, the calling screen catches the error and shows a friendly message to the user.

---

### Snippet 2 — Firestore Database Read with Fallback

**Module:** Plant Catalog / Firestore Integration
**File:** `gardnx_app/lib/features/plant_database/data/repositories/plant_repository.dart`
**Lines:** 22–47
**Title:** Loading Plants from Firestore with Local Fallback

```dart
Future<List<Plant>> getAllPlants({bool forceRefresh = false}) async {
  if (_cachedPlants != null && !forceRefresh) return _cachedPlants!;

  List<Plant> plants = [];
  try {
    final snapshot =
        await _firestore.collection('plants').orderBy('name').get();
    plants = snapshot.docs.map((doc) => Plant.fromFirestore(doc)).toList();
  } catch (_) {
    // ignore — fall through to local fallback
  }

  // Fall back to bundled asset data when Firestore is empty or unreachable
  if (plants.isEmpty) {
    plants = await _loadLocalPlants();
  }

  if (plants.isNotEmpty) {
    _cachedPlants = plants;
    _plantById.clear();
    for (final p in plants) {
      _plantById[p.id] = p;
    }
  }
  return _cachedPlants ?? plants;
}
```

**Explanation:** This function fetches the list of plants. It first checks if plants were already loaded recently (the "cache") and returns those immediately to avoid unnecessary network calls. If not cached, it reads from Firestore — the cloud database. If Firestore fails (no internet, for example), it reads from a plant list bundled inside the app itself as a backup. This three-layer approach (cache → Firestore → local file) means the plant list always works, even offline.

---

### Snippet 3 — Plant Recommendation Engine (Backend)

**Module:** Plant Recommendation
**File:** `gardnx_backend/app/api/v1/endpoints/layout.py`
**Lines:** 186–226
**Title:** AI-Powered Plant Recommendation with Fallback Chain

```python
@router.post("/recommend", response_model=RecommendBedResponse)
async def recommend_plants_for_bed(
    body: RecommendBedRequest,
    user_id: str = Depends(get_current_user),
):
    rec = _get_plant_recommender()
    season_months = _SEASON_MONTHS.get(body.season.lower(), list(range(1, 13)))
    current_month = season_months[0] if season_months else 1

    ai_req = RecommendRequest(
        bed_sunlight=body.sun_exposure,
        bed_soil_type=body.soil_type,
        month=current_month,
        region=body.region,
    )

    ai_result = None
    engine_used = "rules"

    gemini = _get_gemini_recommender()
    ollama = _get_ollama_recommender()

    for eng_name, eng in [("gemini", gemini), ("ollama", ollama)]:
        try:
            attempt = await eng.recommend(ai_req, rec.plants)
            if attempt is not None and attempt.recommendations:
                ai_result = attempt
                engine_used = eng_name
                break
            else:
                logger.warning("Bed recommend: %s returned no results — falling through", eng_name)
        except Exception as exc:
            logger.warning("Bed recommend: %s failed — %s", eng_name, exc)
```

**Explanation:** This is the recommendation endpoint on the server. When the app asks for plant suggestions, this code runs. It tries Gemini AI first. If Gemini fails or returns nothing, it tries Ollama (a local AI). If that also fails, it uses a rule-based scoring system that always works. This design means the user always gets recommendations — the quality may vary, but there is never a blank screen.

---

### Snippet 4 — Gemini AI Prompt and Caching

**Module:** Gemini AI Recommender
**File:** `gardnx_backend/app/services/gemini_recommender.py`
**Lines:** 107–135
**Title:** Calling Gemini with 24-Hour Result Cache

```python
async def recommend(
    self,
    req: RecommendRequest,
    plants: dict[str, Plant],
) -> Optional[RecommendResponse]:
    if not self._enabled:
        return None

    key = self._cache_key(req)
    cached = self._get_cache(key)
    if cached is not None:
        logger.debug("Gemini cache hit for key=%s", key)
        return cached

    try:
        prompt = self._build_prompt(req, plants)
        response = await self._model.generate_content_async(prompt)
        result = self._parse_response(response.text, req, plants)
        if result:
            self._set_cache(key, result)
            logger.info("Gemini recommendation OK — cached for 24 h (key=%s)", key)
        return result
    except Exception as e:
        logger.warning("Gemini recommendation failed: %s", e)
        return None
```

**Explanation:** This function calls Google's Gemini AI. Before making the call, it checks if the same request was made in the last 24 hours. If yes, it returns the saved result immediately — saving time and avoiding unnecessary AI costs. If not, it builds a prompt describing the garden bed and sends it to Gemini. If Gemini crashes or is unavailable, the error is caught quietly and `None` is returned, which tells the calling code to try the next engine.

---

### Snippet 5 — Rule-Based Scoring Fallback

**Module:** Plant Recommender (Rules Engine)
**File:** `gardnx_backend/app/services/plant_recommender.py`
**Lines:** 68–112
**Title:** Weighted Scoring of Plants Without AI

```python
def recommend(self, req: RecommendRequest) -> RecommendResponse:
    scored: List[PlantRecommendation] = []

    for plant in self.plants.values():
        if plant.id in req.exclude_plant_ids:
            continue
        if not self._passes_hard_filter(plant, req):
            continue

        sun_sc, sun_reason   = self._score_sun(plant, req.bed_sunlight)
        season_sc, season_reason = self._score_season(plant, req.month)
        temp_sc, temp_reason = self._score_temp(plant, req.current_temp_c)
        region_sc, region_reason = self._score_region(plant, req.region)
        pref_sc, pref_reason = self._score_preference(plant, req.preferences)

        total = (
            W_SUN * sun_sc
            + W_SEASON * season_sc
            + W_TEMP * temp_sc
            + W_REGION * region_sc
            + W_PREF * pref_sc
        )

        scored.append(
            PlantRecommendation(
                plant=plant,
                score=round(total, 3),
                reasons=reasons,
                ...
            )
        )

    scored.sort(key=lambda r: r.score, reverse=True)
    return RecommendResponse(recommendations=scored[:20], ...)
```

**Explanation:** This is the rules-based fallback that runs when AI is unavailable. It goes through every plant in the database and gives it a score from 0 to 1. The score is made up of five parts — sunlight match (25% of score), planting season (25%), temperature range (20%), Mauritius region (15%), and user preferences (15%). The plants with the highest total scores are returned as recommendations. This approach needs no internet and no AI — it just uses the data already stored in the app.

---

### Snippet 6 — Garden Photo Analysis

**Module:** Garden Image Analysis
**File:** `gardnx_backend/app/services/garden_analyzer.py`
**Lines:** 76–119
**Title:** AI Segmentation with PIL Colour Fallback

```python
def analyze(self, image_bytes: bytes, selected_area=None) -> SegmentationResponse:
    start_time = time.time()

    if self.use_mock:
        zones = self._mock_analyze()
    else:
        zones = self._ml_analyze(image_bytes, selected_area)

    processing_time = int((time.time() - start_time) * 1000)
    avg_confidence = (
        sum(z.confidence for z in zones) / len(zones) if zones else 0
    )

    return SegmentationResponse(
        segmentation_id=str(uuid.uuid4()),
        zones=zones,
        processing_time_ms=processing_time,
        fallback_recommended=avg_confidence < 0.5,
    )

def _ml_analyze(self, image_bytes: bytes, selected_area) -> List[ZoneInfo]:
    # 1. Try Hugging Face ML segmentation
    if self._hf is not None:
        try:
            result = self._hf.analyze(image_bytes, selected_area)
            if result and result.zones:
                logger.info("HF ML segmentation succeeded: %d zones", len(result.zones))
                return result.zones
        except Exception as exc:
            logger.warning("HF analyzer raised %s — falling back to PIL", exc)

    # 2. PIL colour fallback
    logger.info("Using PIL colour-analysis fallback")
    return self._colour_analyze(image_bytes, selected_area)
```

**Explanation:** This function analyses the garden photo. If the server is in live mode (not mock), it tries to use the Hugging Face AI model to detect garden zones. If that AI call fails for any reason, it falls back to a simpler method that analyses colours in the image using a Python library called PIL — for example, green areas are likely lawn, brown areas are likely soil. Either way, the result includes a list of zones with confidence scores and a flag suggesting if the user should double-check the results manually.

---

### Snippet 7 — Layout Save and Calendar Trigger

**Module:** Garden Layout Planning
**File:** `gardnx_app/lib/features/layout_planner/presentation/screens/layout_editor_screen.dart`
**Lines:** 147–210
**Title:** Saving Layout and Auto-Generating Calendar

```dart
Future<void> _save() async {
  setState(() => _isSaving = true);
  try {
    final layoutId = await ref
        .read(layoutNotifierProvider.notifier)
        .saveCurrentLayout();
    if (!mounted) return;
    if (layoutId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Layout saved!')),
      );
      ref.read(activeGardenIdProvider.notifier).state = widget.gardenId;
      _generateAndSaveCalendar(); // fire-and-forget in background
    }
  } catch (_) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save layout.')),
      );
    }
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}

Future<void> _generateAndSaveCalendar() async {
  final layout = ref.read(layoutNotifierProvider);
  if (layout == null || layout.placements.isEmpty) return;

  final Map<String, String> placementPlantNames = {};
  for (final p in layout.placements) {
    placementPlantNames[p.plantId] = p.plantName;
  }

  final allPlants = await ref.read(allPlantsProvider.future)
      .catchError((_) => <Plant>[]);
  final plants = <Plant>[];
  for (final entry in placementPlantNames.entries) {
    Plant? found = allPlants.where((p) => p.id == entry.key).firstOrNull;
    found ??= allPlants.where((p) =>
        p.name.toLowerCase() == entry.value.toLowerCase()).firstOrNull;
    if (found != null) plants.add(found);
  }

  if (plants.isEmpty) {
    _saveLocalCalendarTasks(placementPlantNames);
    return;
  }
  // continues to call backend /calendar/generate ...
}
```

**Explanation:** When the user taps "Save", this code saves the layout to Firestore and shows a success message. It then immediately starts generating the planting calendar in the background — the user does not have to wait for this. The calendar generation looks up full plant details (including sowing months and days to harvest), then calls the backend to compute real planting dates. If it cannot find plant details, it saves a simpler set of local reminders instead. This ensures the user always gets something in their calendar, even if there is a connection issue.

---

### Snippet 8 — Calendar Event Generation (Backend)

**Module:** Planting Calendar
**File:** `gardnx_backend/app/services/calendar_service.py`
**Lines:** 22–94
**Title:** Computing Sow, Transplant, and Harvest Dates

```python
def generate_calendar(self, plants: list, start_date: date | None = None) -> list:
    if start_date is None:
        start_date = date.today()

    events: list = []
    current_month = start_date.month

    for plant in plants:
        sow_date = self._next_date_for_months(
            start_date, plant.sowing_months, current_month
        )
        if sow_date:
            events.append(CalendarEvent(
                plant_id=plant.plant_id,
                plant_name=plant.plant_name,
                event_type="sow",
                start_date=sow_date.isoformat(),
                end_date=(sow_date + timedelta(days=7)).isoformat(),
                bed_name=plant.bed_name,
                description=f"Sow {plant.plant_name} seeds in {plant.bed_name}",
                priority="high" if sow_date <= start_date + timedelta(days=14) else "normal",
            ))

            if plant.transplant_months:
                transplant_date = sow_date + timedelta(
                    days=plant.days_to_germination + 14)
                events.append(CalendarEvent(
                    event_type="transplant",
                    start_date=transplant_date.isoformat(),
                    description=f"Transplant {plant.plant_name} seedlings to {plant.bed_name}",
                    ...
                ))

            harvest_date = sow_date + timedelta(days=plant.days_to_harvest)
            events.append(CalendarEvent(
                event_type="harvest",
                start_date=harvest_date.isoformat(),
                description=f"Expected harvest of {plant.plant_name} from {plant.bed_name}",
                ...
            ))

    events.sort(key=lambda e: e.start_date)
    return events
```

**Explanation:** This backend function takes the list of plants in your layout and works out the exact dates for each gardening action. It finds the next sowing month from today, calculates when to transplant based on germination time, and adds the expected harvest date using the plant's days-to-maturity figure. Events marked "high" priority are those due within two weeks. The results come back as a sorted list of dated events, which the app then saves to the user's calendar in Firestore.

---

### Snippet 9 — Frontend to Backend Communication

**Module:** Calendar Repository / API Communication
**File:** `gardnx_app/lib/features/calendar/data/repositories/calendar_repository.dart`
**Lines:** 33–88
**Title:** Sending Plant Data to Backend and Saving Events to Firestore

```dart
Future<List<PlantingEvent>> generateCalendar({
  required String gardenId,
  required String bedId,
  required String bedName,
  required String region,
  required List<Plant> plants,
}) async {
  if (plants.isEmpty) return [];

  final plantEntries = plants.map((p) => {
    'plant_id': p.id,
    'plant_name': p.name,
    'bed_name': bedName,
    'sowing_months': p.timing.sowMonths,
    'harvest_months': p.timing.harvestMonths,
    'days_to_harvest': p.timing.daysToMaturity,
  }).toList();

  try {
    final response = await _dio.post('/calendar/generate', data: {
      'plants': plantEntries,
      'garden_info': {
        'region': region,
        'latitude': -20.2,
        'longitude': 57.5,
      },
      'start_date': DateTime.now().toIso8601String().split('T')[0],
    });

    if (response.statusCode == 200 && response.data != null) {
      final raw = response.data['events'] as List<dynamic>? ?? [];
      return raw.map((e) {
        final m = e as Map<String, dynamic>;
        return PlantingEvent(
          gardenId: gardenId,
          bedId: bedId,
          plantName: m['plant_name'] as String? ?? '',
          eventType: PlantingEventTypeExt.fromValue(
              m['event_type'] as String? ?? 'general'),
          date: DateTime.parse(m['start_date'] as String),
          notes: m['description'] as String?,
          isCompleted: false,
        );
      }).toList();
    }
  } on DioException {
    // Fall through — caller handles empty list gracefully.
  }
  return [];
}
```

**Explanation:** This function is the bridge between the Flutter app and the Python backend. It takes the list of plants from the layout, packages them into a structured request, and sends it to the `/calendar/generate` server endpoint using an HTTP POST request (a standard way of sending data over the internet). The server sends back a list of events with dates. The app then turns those raw data responses into proper event objects that can be saved to Firestore. If the server call fails for any reason, the function quietly returns an empty list and the calling code handles the fallback.

---

### Snippet 10 — Global Plant Search

**Module:** Plant Catalog / Global Perenual Search
**File:** `gardnx_app/lib/features/plant_database/presentation/screens/plant_catalog_screen.dart`
**Lines:** 318–376
**Title:** Showing Global Search Results with Loading and Error States

```dart
Widget build(BuildContext context, WidgetRef ref) {
  final globalAsync = ref.watch(globalPlantSearchProvider(query));

  return globalAsync.when(
    data: (plants) {
      if (plants.isEmpty) {
        return SliverToBoxAdapter(
          child: Text('No global results for "$query"'),
        );
      }
      return SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) => PlantCard(
            plant: plants[index],
            onTap: () => onNavigate(plants[index]),
          ),
          childCount: plants.length,
        ),
        ...
      );
    },
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (_, __) => const Text(
      'Global search unavailable — check your connection.',
    ),
  );
}
```

**Explanation:** This widget shows the results from searching the global Perenual plant database. The `.when()` call handles all three possible states automatically: while waiting for results, it shows a spinning circle; when results arrive, it shows a grid of plant cards; if something goes wrong, it shows a friendly error message. This pattern is used throughout the app and ensures the user always sees appropriate feedback — never a blank screen or a crash.

---

## 4. Development Tools and Environment

### Hardware Requirements
- A computer capable of running Android Studio or VS Code alongside a running Python server. *Inferred from project structure.*
- An Android device or Android emulator for testing. *Confirmed — the app targets Android (`google-services.json` present in the Android app folder).*

### Software Requirements

| Tool / Software | Purpose | Status |
|---|---|---|
| Flutter SDK (3.x) | Build the mobile app | Confirmed — `pubspec.yaml` uses Flutter packages |
| Dart | Programming language for Flutter | Confirmed — all app code is Dart |
| Python 3.11+ | Run the FastAPI backend | Confirmed — `requirements.txt` uses modern Python syntax |
| Android Studio or VS Code | Write and run the code | Inferred — standard for Flutter development |
| Android SDK | Build and run Android apps | Inferred — required by Flutter for Android |
| Git | Version control | Confirmed — `.git` folder present |

### Backend Dependencies (from `requirements.txt`)

| Package | Purpose |
|---|---|
| `fastapi==0.115.0` | Web framework for the Python backend |
| `uvicorn` | Runs the FastAPI server |
| `firebase-admin==6.6.0` | Allows the backend to verify Firebase login tokens |
| `google-generativeai==0.8.3` | Connects to Google's Gemini AI |
| `httpx==0.28.0` | Makes HTTP requests (to Hugging Face, Perenual, Open-Meteo) |
| `Pillow==11.0.0` | Image processing for photo analysis fallback |
| `pydantic==2.10.0` | Data validation for API request/response shapes |
| `pydantic-settings` | Loads configuration from `.env` file |

### Flutter Dependencies (from `pubspec.yaml`, confirmed from imports in code)

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management (providers, async state) |
| `firebase_auth` | Firebase Authentication |
| `cloud_firestore` | Firestore database |
| `firebase_storage` | Cloud file storage (profile photos) |
| `go_router` | Navigation and routing |
| `dio` | HTTP client for backend API calls |
| `table_calendar` | Calendar widget on the calendar screen |
| `image_picker` | Pick photos from gallery or camera |
| `geolocator` | Get device GPS location |

### External Services Used

| Service | Purpose | Status |
|---|---|---|
| Firebase Authentication | User login and account management | Confirmed |
| Cloud Firestore | Database for all app data | Confirmed |
| Firebase Storage | Stores profile photos | Confirmed |
| Google Gemini AI (2.5 Flash Lite) | AI plant recommendations | Confirmed — API key in `.env` |
| Hugging Face Inference API | Garden photo segmentation (Segformer model) | Confirmed — token in `.env`, `USE_MOCK_MODEL=false` |
| Perenual API | Global plant database search | Confirmed — API key in `.env` |
| Open-Meteo | Free weather API for climate data | Confirmed — URL in `config.py` |
| Ollama (local) | Local AI fallback for recommendations | Confirmed — code implemented, requires local install |

### Testing and Execution Environment
- **Mobile:** Android physical device or Android emulator. *Confirmed — `google-services.json` present.*
- **Backend:** Runs locally using `uvicorn` on port 8000. The Flutter app connects to the backend's local IP address. *Confirmed — `api_constants.dart` configures the backend host.*
- **Firebase project:** `mygardenplanner-d9a9b`. *Confirmed — `google-services.json`.*

---

## 5. Summary

myGardenPlanner is a working mobile app with a complete set of core features. Users can register and log in securely using Firebase Authentication. They can plan their garden by either taking a photo (analysed by AI to detect plantable zones) or drawing beds manually on screen. The app recommends plants suited to their location, sun exposure, season, and preferences using a three-engine system — Google's Gemini AI, a local AI called Ollama, and a built-in rule-based scoring system that always works as a fallback. Users can arrange their chosen plants in a grid layout, with automatic checks for incompatible plant combinations. Once a layout is saved, the app generates a planting calendar with real dated reminders for sowing, transplanting, and harvesting. All data is stored securely in Firestore and protected by security rules that ensure users can only access their own information. The Flutter app communicates with a Python FastAPI backend for all AI-heavy operations, with multiple fallback paths to ensure the app stays functional even when connectivity is limited.

---

## 6. Partially Implemented or Incomplete Features

| Feature | Current State |
|---|---|
| **Push Notifications (FCM)** | The notification service is set up (permission request, background handler registered) but no actual notification triggers are connected anywhere in the app logic. |
| **Climate Tab / Screen** | The backend endpoints, data models, and providers for climate data are all implemented, but no climate screen exists in the Flutter app. Climate data is used internally by the recommendation engine only. |
| **Task List Screen** | The screen file and its provider exist and the Firestore query is implemented, but the full task interaction UI (detailed task view, delete action) was not fully verified. |
