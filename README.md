# হবু বাবা — Flutter Android App (V2 source)

This source project contains the original Flutter screens and the following additions:

1. Onboarding: EDD (pregnancy) or actual DOB (born) saved in SharedPreferences. Settings permit date/mode changes. EDD-based gestational weeks assume a 40-week pregnancy; clinical EDD may change.
2. 300 notification entries across 10 categories (30 per category) with rotating daily schedules and user-selectable 1–3 notifications/day. Entries include variations on 10 core ideas per category. Scheduling covers **the next 14 days**, refreshed on app opening; notifications outside that window cannot be guaranteed unless reopened. Android may delay inexact notifications; battery restrictions apply. The current rule engine does not fully filter every tip by developmental stage, so check appropriateness before following it. Not a clinical vaccination reminder system.
3. Hospital search: requests GPS location permission or accepts a manual place and launches **live Google Maps search results** and directions; there is no in-app Places API result list, no verified NICU/emergency status, and no reliable strict-radius filter yet.
4. AI chat: Direct Google Gemini API inside Flutter; user adds key in AI Guide (top-right key icon), stored with Android encrypted secure storage. No backend or Firebase needed for personal prototypes. Gemini API calls are authenticated using an on-device key; **not safe for public distribution**.

5. Brand icon and onboarding logo at `assets/branding/`, Bangla launcher label, icon-generator configuration.

## Build on GitHub

Upload the **contents** of this ZIP into your GitHub repo at its root, including the hidden `.github` directory (replace the old `lib/main.dart`, `pubspec.yaml`, workflow and assets). Then Actions -> Build Hobu Baba APK -> Run workflow. Find `hobu-baba-updated-apk` under Artifacts when successful.

This workspace has no Flutter SDK, so **the source has not been compiled or tested**. If the build fails, inspect the earliest actual Dart/Gradle error and correct it before retrying. The GitHub workflow scaffolds missing Android files, injects needed manifest permissions, enables desugaring and creates the launcher icon.

## Gemini AI setup (simple / personal testing only)

1. Get a Gemini API key from https://aistudio.google.com/api-keys (select a Gemini Free Tier-capable project/model if available in your region).
2. Build/install the APK normally from GitHub Actions; no GitHub secret is needed.
3. Open app -> AI Guide -> top-right key icon -> paste your key -> Save.
4. Ask a test question in Bangla; replies appear inside the app. The model configured in `lib/main.dart` is `gemini-2.5-flash`.
5. To change or remove key: same key icon. If the Gemini API returns rate limit (429), wait for quota to reset.

**Warning:** `flutter_secure_storage` encrypts the key at rest, but the key must still be sent from the app to Google and can be extracted from an instrumented device or intercepted via app runtime. Never publish an APK configured with a shared owner key; each tester should enter their own key. Free Tier quotas, availability, data-handling terms and model access vary and can change. In some Free Tier configurations Google may use input/output to improve products. Do not enter identifying medical records or highly sensitive information. Clinical advice needs professional verification. Backend-based authentication remains the production-grade solution.

This version does not use the `backend/` folder, which remains from the earlier prototype only. No `HOBU_API_URL` secret is required.

## Testing checklist

- Fresh install prompts EDD/DOB, restart preserves date.
- Profile settings modify date and frequency, re-open changes tracker.
- Grant/deny Android notification permission, verify schedules on a physical device and after restart.
- Select current location and manual location, verify Google Maps opens.
- With no Gemini key the UI prompts for setup; with a valid key it returns dynamic Gemini chat responses.
- Icon looks correct on Android launcher and title displays 'হবু বাবা'.
