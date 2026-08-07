# Backend spec: Force Update / Minimum App Version

Lets us stop drivers running an app build we no longer support, after a release
that changes a contract, fixes a safety bug, or breaks compatibility with the
backend.

One whitelisted read-only method, one Single DocType holding the thresholds. No
writes, no per-driver state.

## Status

**Backend: not started. App: implemented and merged-safe against a missing
endpoint.**

| Piece | State |
|---|---|
| `check_app_version` | **Not implemented** — returns `404` today |
| `Grozfy App Release Config` (Single) | **Not implemented** |
| App: `AppVersionStatus`, `AppVersionService`, `AppController`, `ForceUpdateGate` | Implemented, 51 unit tests passing |

The app ships before the backend does. Until the method exists the endpoint
`404`s, the client treats that exactly like "up to date", and nothing about the
driver's experience changes. Deploying the backend is what turns the feature on;
no app release is needed to activate it.

### Deviation from the spec item: the block is dismissible

Spec item 20 says "Mandatory update blocks further app use until upgraded." The
shipped app does **not** do that, by product decision. `update_required: true`
raises a bottom sheet that blocks input to the app behind it, but the sheet
carries a **Later** button, and the Android back button acts as Later.

Dismissal is session-scoped and never written to disk, so every relaunch prompts
again — but a driver who keeps the app open can go on working on an unsupported
build indefinitely.

What that means for the backend: `update_required` is a strong nag, not a
kill switch. Do not rely on it to guarantee that no unsupported build is in the
field — if a release truly cannot be allowed to keep talking to the API, that
has to be enforced server-side by rejecting the old build's requests, not by
this flag.

**The one thing that must be right on day one:** an empty or zero
`android_min_build` means *no floor*, not *block everyone*. Getting that
backwards bricks every driver on the platform simultaneously, and the fix
requires them to update — which is exactly what they cannot do while blocked.
§6 states this as a hard rule and §9 makes it an acceptance test.

---

## 1. Endpoint

```
GET /api/method/grozfy_go.grozfy_go.api.app_version.check_app_version
```

Path is already wired into the app as `ApiConstants.appVersionCheck`. Changing
it requires an app release, so treat it as fixed.

`@frappe.whitelist(allow_guest=True, methods=["GET"])`.

### Why `allow_guest=True`

The check runs at three moments, and two of them have no session:

1. **App bootstrap**, before login, on a fresh install.
2. **App bootstrap** with a token the new backend has since invalidated.
3. **Foreground resume**, throttled to once per 30 minutes, when a session
   usually does exist.

A driver whose token expired must still be told to update — that is often
*why* it expired. Requiring auth here would mean the only drivers who ever see
the update screen are the ones who least need it.

The response contains no personal data and no business data: build numbers, a
store URL, and release copy. It is safe to serve to anyone. Do not add a
`driver` parameter; there is nothing per-driver about the answer.

---

## 2. Request

Query parameters, all sent by the app on every call:

| Param | Type | Always sent | Notes |
|---|---|---|---|
| `platform` | string | ✔ | `android` or `ios`, lowercase. An unrecognised value must be treated as **unconstrained** (§6), never as Android. |
| `version` | string | ✔ | Marketing version, e.g. `1.0.1`. Display and logging only — **never compare on this**, see §3. |
| `build_number` | string | ✔ | The integer build, e.g. `2`. `versionCode` on Android, `CFBundleVersion` on iOS. This is the comparison key. |

The app sends `Accept: application/json` and no auth header. It times out at
**6 seconds** — this call sits in front of the splash screen, so keep it a
single cached read of one Single DocType. No joins, no per-request computation.

Example:

```
GET /api/method/grozfy_go.grozfy_go.api.app_version.check_app_version
      ?platform=android&version=1.0.1&build_number=2
```

---

## 3. Compare on `build_number`, not on `version`

`build_number` is a monotonically increasing integer that the store itself
enforces — you cannot ship a lower `versionCode` than the one already live.
That makes it the only value where `<` means what we need it to mean.

The marketing version does not have that property:

- `1.10.0` sorts *below* `1.9.0` under string comparison, and a naive
  `split('.')` parse of `1.0.1-hotfix.2` or `1.0` throws or truncates.
- It is set by hand in `pubspec.yaml` and can be reused, lowered, or skipped.
- We have already shipped `1.0.1+2` where the same marketing version could
  cover several builds.

So: **`version` is for the screen, `build_number` is for the decision.** The
app enforces the same split — `AppVersionStatus` compares builds and only ever
prints `latest_version`.

---

## 4. Response

Standard Frappe envelope. Always `200` on success — this endpoint has no
"blocked" error case, only verdicts.

```json
{
  "message": {
    "update_required": false,
    "update_available": true,
    "min_supported_build": 2,
    "recommended_build": 7,
    "latest_version": "1.2.0",
    "store_url": "https://play.google.com/store/apps/details?id=com.grozfy.go",
    "title": "A new version is available",
    "message": "Faster order pickup and a fix for the map freezing on long trips.",
    "release_notes": [
      "Pickup flow is 2 steps shorter",
      "Fixed the map freezing on trips over 20 km"
    ]
  }
}
```

### Fields

| Key | Type | Required | Meaning |
|---|---|---|---|
| `update_required` | bool | ✔ | **The verdict.** `true` blocks the app entirely. Computed server-side: `build_number < min_supported_build`. |
| `update_available` | bool | ✔ | A dismissible prompt is due: `build_number < recommended_build`. May be `true` alongside `update_required`; mandatory wins. |
| `min_supported_build` | int | ✔ | The floor. `0` or absent means **no floor** (§6). |
| `recommended_build` | int | ✔ | The build we would like everyone on. `0` or absent means no recommendation. |
| `latest_version` | string | | Marketing version of the newest build, e.g. `1.2.0`. Shown as "Latest version". Display only. |
| `store_url` | string | | Deep link to this platform's store listing. Scheme must be one of `https`, `http`, `market`, `itms-apps`, `itms-appss` — the app rejects anything else and falls back to its own Play Store URL. |
| `title` | string | | Heading. Overrides the app's localised default when non-empty. |
| `message` | string | | Body copy. Same override rule. |
| `release_notes` | string[] | | Bullets under "What's new". Non-string entries are dropped by the client. |

### What the client does with it

`update_required` and `update_available` are the authority when present. If
either is **absent**, the client derives it from the build numbers
(`current < min_supported_build`, `current < recommended_build`) — so a
response carrying only the integers still works. Sending both is preferred:
it keeps the decision in one place and lets you override it later without an
app release.

`title`, `message` and `release_notes` are rendered verbatim. Send them
**localised to the `Accept-Language` header** if you can; the app falls back to
its own translated strings when they are empty, and empty is better than
English-only for a driver who reads Tamil. Do not send HTML — it renders as
plain text.

### Verdict matrix

| `build_number` vs thresholds | `update_required` | `update_available` | Driver sees |
|---|---|---|---|
| `>= recommended_build` | false | false | Nothing |
| `>= min_supported_build`, `< recommended_build` | false | true | Dismissible sheet, re-shown after 24h |
| `< min_supported_build` | true | true | Input-blocking sheet; "Later" clears it until relaunch |
| `min_supported_build == 0` | **false** | per recommended | Never prompted |

Note `build_number == min_supported_build` **passes**. The floor is the oldest
build that still works, not the first one that fails.

---

## 5. DocType: `Grozfy App Release Config`

Module `Grozfy Go`. **Single** — there is exactly one row and no naming series.

If the `Grozfy Settings` singleton introduced by the account-deletion work
(`docs/backend-specs/request_account_deletion.md`) is already live, adding these
fields to it is fine — the field names and semantics below are what matter, not
where they live. A separate DocType is suggested only so release thresholds can
have narrower write permissions than general settings.

| Fieldname | Label | Type | Notes |
|---|---|---|---|
| `android_min_build` | Android Minimum Build | Int | Default `0` = no floor. Blocking threshold. |
| `android_recommended_build` | Android Recommended Build | Int | Default `0` = no recommendation. |
| `android_latest_version` | Android Latest Version | Data | e.g. `1.2.0`. Display only. |
| `android_store_url` | Android Store URL | Data | Play listing. Blank → the app uses its own fallback. |
| `ios_min_build` | iOS Minimum Build | Int | Same semantics. |
| `ios_recommended_build` | iOS Recommended Build | Int | |
| `ios_latest_version` | iOS Latest Version | Data | |
| `ios_store_url` | iOS Store URL | Data | App Store listing. |
| `update_title` | Update Title | Data | Optional override of the app's heading. |
| `update_message` | Update Message | Small Text | Optional override of the body. |
| `release_notes` | Release Notes | Small Text | One bullet per line; the method splits on newline into the array. |
| `force_update_enabled` | Enforce Minimum Build | Check | Default **0**. A master switch — see below. |

### `force_update_enabled` is the kill switch

When `0`, the method returns `update_required: false` and
`min_supported_build: 0` regardless of what the build fields say.
`update_available` still works, so optional prompts keep functioning.

This exists because a bad `android_min_build` is not a bug you can hotfix from
the app side — every affected driver is already locked out and cannot receive a
new build fast enough. Ops need one checkbox that ends the incident in seconds.
Ship with it **off**, turn it on deliberately when the first real floor is set.

### Permissions

| Role | Read | Write |
|---|---|---|
| System Manager | ✔ | ✔ |
| Grozfy Ops / Delivery Manager | ✔ | ✘ |
| Everyone else, incl. guest | via the whitelisted method only | ✘ |

Raising `android_min_build` is a decision with the blast radius of a production
outage. Keep write access narrow, and log every change — Frappe's Single
DocType versioning covers this if `track_changes` is on. Enable it.

---

## 6. Behaviour rules

These are the rules that keep a configuration mistake from becoming a fleet-wide
lockout.

1. **Zero, null or missing means "no constraint".** `android_min_build = 0`,
   the field never filled in, the Single row never created — every one of these
   returns `update_required: false`. Never interpret a missing threshold as
   "block everything". This is the single most important rule in this document.
2. **An unknown `platform` is unconstrained.** If `platform` is not `android`
   or `ios`, return zeros and `update_required: false`. Do not default to the
   Android thresholds — a future platform (or a typo) must not inherit a floor
   meant for someone else.
3. **An unparseable or missing `build_number` is unconstrained.** Return
   `update_required: false`. The app already declines to call when it cannot
   read its own build, but the server must not depend on that.
4. **`update_required` implies `update_available`.** A driver below the floor is
   also below the recommendation. Send both `true`.
5. **`force_update_enabled = 0` suppresses blocking only.** Optional prompts
   still flow. See §5.
6. **Never `throw`.** If the config read fails, catch it and return the
   unconstrained payload with a `200`. An exception here becomes a `500`, which
   the client treats as a failure and answers from its 24-hour cache — usually
   harmless, but a `500` that coincides with a stale cached block keeps drivers
   blocked for a reason unrelated to their build.
7. **No per-driver logic, no session reads, no writes.** Same input → same
   output for every caller. This is what makes it cacheable and what makes it
   safe to expose to guests.

### Failure semantics the client already implements

You do not need to build anything for these; they are stated so the two sides
are known to agree.

| Server behaviour | Client result |
|---|---|
| `404` (method not deployed) | Falls back to cache; no cache → up to date |
| `500`, `503` | Same |
| Timeout > 6s, offline, DNS/TLS failure | Same |
| `200` with a body that is not JSON, or has no `message` object | Same |
| `200` with a valid verdict | Applied, and cached for 24 hours |

**The cache is why a bad block is still recoverable but not instantly.** A
successful blocking verdict is persisted; if later checks fail, the app re-applies
it for up to 24 hours, so airplane mode is not a way around a mandatory update.
Once 24 hours pass with no successful check, the device unblocks. A device that
has never had a successful check — a fresh install — is never blocked.

Consequence for ops: **clearing `android_min_build` stops the prompt on the
driver's next successful check**, not on the next app launch if they are
offline. Until then "Later" is what keeps a wrongly-prompted driver working —
it is the only escape hatch on the sheet, so a bad floor costs a dismissal per
launch rather than stranding anyone.

---

## 7. Rollout procedure

Raising the floor is a destructive action against everyone below it. Do it in
this order:

1. **Set `recommended_build` first**, days ahead. Optional prompts drive most of
   the migration on their own.
2. **Check adoption.** Whatever telemetry exists for installed builds, read it.
   If 8% of active drivers are still below the intended floor, blocking them is
   an 8% capacity cut for the length of a store rollout.
3. **Confirm the new build is actually live on the store** — visible on the
   listing, past staged rollout, not just "published". Blocking a driver whose
   store has not received the update yet is a dead end: no button on the screen
   can help them.
4. **Set `android_min_build`, then `force_update_enabled = 1`.**
5. **Watch support volume for an hour.** If it spikes, uncheck
   `force_update_enabled` — that is what it is for.

Never raise the floor and publish the build in the same change window.

---

## 8. What the endpoint must not do

- **No blocking for a reason other than build number.** Not for a suspended
  driver, an unpaid balance, or an expired document. Those need their own
  screens with their own resolutions; a driver told "update the app" when the
  real problem is a document expiry updates the app, sees the same screen, and
  files a ticket.
- **No `min_supported_build` derived from "latest minus N".** Set it explicitly.
  A derived floor moves on its own every release and will eventually move
  during an incident.
- **No auth, no rate-limit keyed on identity.** If abuse protection is needed,
  rate-limit by IP generously (this is a once-per-30-minutes-per-device call),
  and make sure exceeding it returns a `429` — which the client treats as a
  failure and answers from cache, i.e. safely.

---

## 9. Acceptance criteria

**Contract**

- [ ] `GET …check_app_version?platform=android&version=1.0.1&build_number=2`
      with no auth header returns `200` and a `message` object.
- [ ] The same call **with** an expired/invalid bearer token also returns `200`.
      A driver whose session died must still get a verdict.
- [ ] Every response contains `update_required`, `update_available`,
      `min_supported_build` and `recommended_build`. The booleans are real JSON
      booleans, or `0`/`1`, or `"true"`/`"false"` — all three are parsed by the
      client, but pick one and be consistent.
- [ ] Response time under 200ms at p95. The app's timeout is 6 seconds and this
      call gates the splash screen.

**Verdicts** (with `android_min_build = 5`, `android_recommended_build = 7`,
`force_update_enabled = 1`)

- [ ] `build_number=4` → `update_required: true`, `update_available: true`.
- [ ] `build_number=5` → `update_required: false`, `update_available: true`.
      Equal to the floor **passes**.
- [ ] `build_number=7` → both `false`.
- [ ] `build_number=9` → both `false`. A build ahead of the config is never
      blocked.

**Safety — the ones that matter**

- [ ] `android_min_build = 0` → `update_required: false` for **every**
      `build_number`, including `1`.
- [ ] The Single row never having been saved → `update_required: false`. Test
      this on a fresh site before the fields are ever filled in.
- [ ] `force_update_enabled = 0` with `android_min_build = 5` and
      `build_number=1` → `update_required: false`, and `update_available` still
      reflects the recommendation.
- [ ] `platform=web`, `platform=ANDROID`, `platform=` (empty), `platform`
      omitted → `update_required: false` in every case. (Note the app always
      sends lowercase; casing is defence in depth.)
- [ ] `build_number=abc`, `build_number=-1`, `build_number` omitted →
      `update_required: false`.
- [ ] Deleting or corrupting the config row does not produce a `500`.

**End to end, on device**

- [ ] With the method undeployed (`404`), the app launches, logs in and works
      normally. No update UI appears anywhere.
- [ ] With `android_min_build` above the installed build, the sheet appears over
      every route — including one opened from an FCM notification tap — and the
      app behind it does not respond to taps.
- [ ] Tapping the scrim does **not** dismiss it; "Later" and the back button do.
- [ ] After "Later", the app is fully usable, and force-quitting and relaunching
      brings the sheet straight back.
- [ ] "Update now" opens the Play Store listing for the installed package.
- [ ] With only `android_recommended_build` above the installed build, the
      dismissible sheet appears; "Later" hides it, and it stays hidden across a
      restart for 24 hours.
- [ ] Turning airplane mode on after a blocking verdict keeps the driver
      blocked (cache), and the block lifts by itself after 24 hours offline.

---

## 10. App side — done, for reference

| File | Role |
|---|---|
| `lib/core/models/app_version_status.dart` | Parses the payload. Every ambiguous input resolves to "up to date". |
| `lib/core/services/app_version_service.dart` | The call, the 6s timeout, the 24h cache, the "Later" snooze. Never throws. |
| `lib/core/state/app_controller.dart` | Checks on bootstrap and on foreground resume, throttled to 30 minutes. |
| `lib/features/settings/force_update_screen.dart` | `ForceUpdateGate`, the non-dismissible blocking sheet, the optional sheet. |
| `lib/core/constants/api_constants.dart` | `ApiConstants.appVersionCheck` — the path above. |

Tests: `test/core/models/app_version_status_test.dart` (20),
`test/core/services/app_version_service_test.dart` (22),
`test/core/state/app_controller_version_test.dart` (9).

The app **does not** clear the cached verdict on logout — the verdict is about
the build on the device, not the driver — so "log out and back in" is not a way
around a block.
