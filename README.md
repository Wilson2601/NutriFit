# NutriFit v2 — Flutter + FastAPI + Firebase

This matches your thesis's documented architecture exactly: Flutter mobile frontend,
FastAPI backend, Firebase (Auth + Firestore) as the data layer.

## What's in this repository

```
backend/    FastAPI app (app/), tests (tests/), helper scripts (scripts/), requirements.txt
mobile/     Complete Flutter project (Android, iOS, web) - run `flutter pub get` first
docs/       Evaluation material (SUS, satisfaction questionnaire, task checklist, test report)
render.yaml Render blueprint used to deploy the backend
```

Secrets are never stored in the repository: `backend/.env` and `backend/serviceAccountKey.json`
are ignored by git. Set them as environment variables on Render instead (see `render.yaml`).

## Part 1 — Backend setup

```bash
cd backend
python3 -m venv venv
# Windows: venv\Scripts\activate      macOS/Linux: source venv/bin/activate
pip install -r requirements.txt
```

### Running without a real Firebase project yet (fastest way to start)

```bash
uvicorn app.main:app --reload --port 8000
```

It auto-seeds demo data into an in-memory store and logs a warning that it's in
fake mode. Good for testing the API itself (`curl http://localhost:8000/health`),
but the Flutter app won't be able to sign in against it, because the app always
uses real Firebase Auth (see "Part 3" for why).

### Running with your real Firebase project

1. In the [Firebase console](https://console.firebase.google.com), open your
   project → gear icon → **Project settings** → **Service accounts** tab →
   **Generate new private key**. This downloads a JSON file.
2. Rename it to `serviceAccountKey.json` and place it in the `backend/` folder
   (next to `requirements.txt`). It's already gitignored — never commit this file.
3. Run the same command as above: `uvicorn app.main:app --reload --port 8000`.
   The startup log will now say `Connected to real Firebase project`.
4. Seed demo data into your real project:
   ```bash
   PYTHONPATH=. python -m app.seed
   ```

### Running the test suite

```bash
PYTHONPATH=. pytest tests/ -v
```

## Part 2 — Flutter project setup

```bash
flutter create nutrifit_app
cd nutrifit_app
flutter run   # confirms your toolchain works before touching any of my code
```

Once that default counter app runs successfully, copy files from this package
into it:

- Copy everything inside `mobile/lib/` → overwrite `nutrifit_app/lib/`
- Copy `mobile/pubspec.yaml` → overwrite `nutrifit_app/pubspec.yaml`
  (or merge the `dependencies:` section into your existing one if you customized it)

Then:

```bash
flutter pub get
```

## Part 3 — Connect Flutter to your Firebase project

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This walks you through selecting your Firebase project and platforms (choose
Android, and iOS if you have a Mac), then **overwrites**
`lib/firebase_options.dart` with your project's real values.

This is why the Flutter app always uses real Firebase Auth (not the backend's
dev-mode fallback): once `flutterfire configure` has run, `firebase_auth` talks
directly to your real Firebase project's Auth servers. The backend needs to be
running in real mode too (Part 1's second option) so the ID tokens Flutter
generates can be verified — both sides must point at the **same** Firebase project.

## Part 4 — Point Flutter at your backend

By default the app expects the backend at `http://10.0.2.2:8000` — this is a
special alias the Android emulator uses to reach `localhost` on your own machine.

- **Android emulator + backend running locally:** no change needed.
- **Physical device:** it can't reach your machine's localhost at all. Either run
  the backend on the same Wi-Fi network and use your machine's LAN IP
  (`http://192.168.x.x:8000`), or deploy the backend somewhere reachable
  (Render, Railway, etc. — free tiers work fine for FastAPI, same as we discussed
  for the earlier web version).
- **iOS simulator:** use `http://localhost:8000` (no special alias needed there).

To change it, run with:
```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8000
```

## Setting up push & local notifications

This is new since your last update. Two pieces work differently:

**Local scheduled reminders** (Defrost Reminder, Pre-Workout Meal, etc.) — these
run on-device and need no extra setup beyond `flutter pub get`. Toggle one on and
Save in the Reminders screen; it schedules a real daily OS notification.

**Push notifications** (coach sets new targets → you get notified) — these need
one more Firebase Console step, since push requires a "Web Push certificate" (VAPID key):

1. Firebase Console → your project → gear icon → Project settings → **Cloud Messaging** tab.
2. Under "Web configuration", click **Generate key pair**. Copy the key it shows you.
3. Run the app with that key attached:
   ```
   flutter run --dart-define=API_BASE_URL=http://localhost:8000 --dart-define=FCM_VAPID_KEY=your-key-here
   ```
4. Copy this package's `mobile/web/firebase-messaging-sw.js` into your project's
   `nutrifit_app/web/` folder (don't replace anything else in that folder — just
   add this one file). Open it and replace the `REPLACE_WITH_YOUR_...` placeholders
   with the same values from your `lib/firebase_options.dart`'s `web` section.
5. When you sign in, your browser will ask for notification permission — allow it.

**Testing the push flow:** sign in as a user in one browser tab, sign in as the
coach in another (or an incognito window), and use "Set Targets" or "Adjust Targets"
on that client from the coach side. The user tab should get a notification.

**Android note:** if you build for Android instead of web, none of the VAPID key
steps apply — `flutter run` on an Android emulator/device just works once you've
run `flutter pub get`, since native push doesn't need a web certificate.

## Verifying this checkpoint

1. Start the backend in real-Firebase mode (Part 1).
2. Run `flutter analyze` first — it catches Dart errors in seconds without
   needing an emulator. Fix anything it flags (or send me the output).
3. `flutter run` on an emulator or device.
4. Try registering a new user account, and separately try logging in as the
   coach (`wilson@nutrifit.my` / `password123`, once you've run the seed script
   against your real project).
5. You should land on a simple placeholder screen confirming who's signed in,
   with a working Sign Out button. That confirms the entire chain — Flutter →
   Firebase Auth → FastAPI → Firestore — is wired correctly before we build the
   real screens on top of it.

If anything errors at any step, send me the exact output and I'll fix it —
same as we did with the earlier Node.js version.

---

## New in this version

### Coach ↔ client chat
- Client: **Home → Chat with Coach**. Coach: **Dashboard → Messages** (inbox with unread counts) or **Client → Message Client**.
- Messages are stored in Firestore under `users/{clientId}/messages`; the open screen refreshes every 4 seconds and the other person gets a push notification.

### Daily mission with camera-only meal photos
- **Home → Daily Mission**. Log your meals, then tap **Take photo** on each one.
- The app uses a live camera preview (`camera` package). There is no gallery or file picker anywhere in the flow, and the server also rejects any photo whose `source` is not `camera`, or that was captured more than 10 minutes ago.
- The server checks every photo: it must decode, be at least 240 px, not be blank/too dark/too bright, and not duplicate an earlier photo.
- A day **passes** when (1) every logged meal has an accepted photo, (2) calories are 70–115% of target and (3) protein is at least 75% of target. The coach sees the result on the client's progress screen and is notified when a client passes.
- Food recognition with AI is *not* included. `verify_photo()` in `backend/app/photo_check.py` is the one place to plug a vision model in.
- Android: if the camera does not open, add `<uses-permission android:name="android.permission.CAMERA"/>` to `android/app/src/main/AndroidManifest.xml`. On web, the browser asks for camera permission (works on `localhost` or HTTPS).

### Profile screens (no more placeholders)
Account Settings, Coach Info, Notification Prefs (per-category push switches), Privacy & Security (password reset email, delete account) and Help & Support are all real.

### Other fixes
- All "what day is it" logic now uses one timezone (`APP_TZ`, default `Asia/Kuala_Lumpur`), so meals logged after midnight no longer land on the wrong day.
- `/auth/me` no longer returns internal fields such as the push token.

### After updating
```
# backend
pip install -r requirements.txt     # adds Pillow and tzdata
uvicorn app.main:app --reload

# mobile
flutter pub get                      # adds the camera package
```

### AI check for meal photos (optional but recommended)
Without a key, the server only checks that the photo is a real, non-blank, non-duplicate image. With a key, a Gemini vision model also checks that the photo shows food and roughly matches the logged recipe.
1. Create a free key at https://aistudio.google.com/apikey
2. In `backend`, copy `.env.example` to `.env` and paste the key after `GEMINI_API_KEY=`
3. Restart uvicorn. If the AI service is down, photos are not accepted and the user is asked to retry.

### Notifications while a tab is open
Browsers do not show system push notifications for a focused tab, so the app now shows an in-app banner for pushes that arrive while it is open. System notifications still appear when the tab is in the background or closed.

### More foods: free online food databases
**Home → Find Foods** searches two free databases at once and logs any food by weight:
- **USDA FoodData Central** for generic foods (chicken breast, rice, eggs). Optional free key in `backend/.env` as `USDA_API_KEY` (get one at https://fdc.nal.usda.gov/api-key-signup). Without it the shared `DEMO_KEY` is used, which has a small hourly limit.
- **Open Food Facts** for packaged and local products, including many sold in Malaysia. No key needed.

Foods that are in neither database (for example a hawker dish) can be added with **Add custom food**. Logged foods count toward the daily targets and the daily mission like recipes do. Run `python scripts/check_foods.py` in `backend` to test that your computer can reach both databases.

### Online recipes you can cook at home
In **Recipes**, type what you want (for example "chicken rice"). If the built-in recipes do not have it, tap **Search online**. Matching recipes are fetched from Spoonacular (free plan, key from https://spoonacular.com/food-api, put it in `backend/.env` as `SPOONACULAR_API_KEY`), saved to Firestore, and from then on behave like built-in recipes: ingredients scale to your calorie target and the **How to Cook** steps are shown. Run `python -m app.add_steps` once to add cooking steps to the 15 built-in recipes that are already in your database.

## FYP 2 upgrade: ingredient-level optimization

**What changed**
- The old "one factor from calories" scaling (and the fixed 1,914 kcal reference) is gone. `backend/app/optimizer.py` adjusts every ingredient weight separately (SciPy SLSQP) to minimise
  `Z = sum_j lambda_j ((N_j(W) - A_j) / max(A_j, eps))^2` with per-ingredient min/max weights, fixed ingredients (seasonings) and a tiny tie-breaker that keeps the dish close to the original recipe. Same inputs always give the same result.
- `backend/app/nutrition.py` is the single source for remaining targets (`R_j = max(0, T_j - I_j)`), daily totals and adherence (`H_j = I_j / T_j * 100`). Dashboard, food history, daily mission and the coach view all use it.
- `backend/app/meal_allocation.py` turns the remaining nutrition into the meal target from the **meal type** and the **"another meal today?" (yes / no / not sure)** answer. All factors are in `AllocationConfig` (override with `NUTRIFIT_ALLOCATION_JSON`).
- Planned meals (`/meals/plan`) never count; only `/meals/consume` (or food logging) is intake. Duplicate submits are ignored through `requestId`.
- Adherence ranges (default Calories 85-115 %, others 80-120 %) are configurable in `nutrition.py` or with `NUTRIFIT_ADHERENCE_JSON`. Days without records are counted separately.
- Recipes without per-ingredient nutrition (for example imported online recipes) only get a clearly labelled portion adjustment, never invented ingredient values.

**One-time migration for your existing database** (backend folder, venv active)
```
pip install -r requirements.txt
python -m app.migrate_ingredients
```
It stores per-100 g nutrition and limits on each ingredient, recalculates recipe totals from the ingredients (old totals kept in `legacyTotals`) and marks old meal logs as consumed. It deletes nothing.

**Tests and evaluation material**
```
python -m pytest -q          # 77 automated tests
python make_test_report.py   # writes docs/evaluation/TEST_REPORT.md
```
`docs/evaluation/` has the SUS and satisfaction questionnaires and the task checklist. Real answers can be recorded with `/evaluation/*` and summarised at `GET /evaluation/summary` (coach login). No sample results are included.

Ingredient nutrition values in `backend/app/ingredient_data.py` are rounded typical figures (USDA style). Check them against your chosen source before using them in the thesis.
