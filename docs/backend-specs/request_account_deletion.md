# Backend spec: Account Deletion

Lets a delivery partner delete their account from inside the app, as the Privacy
Policy promises and as Google Play requires of any app that allows account
creation.

## Status

**Backend: implemented and verified on `store2.com`** (API paths only — the
erasure job has never been run). **App: wired.**

| Piece | State |
|---|---|
| `request_account_deletion`, `get_account_deletion_status`, `cancel_account_deletion` | Implemented, 11/11 API checks passed |
| `Account Deletion Request`, `Account Deletion Blocker` | Implemented |
| `Grozfy Settings` (new singleton) | Implemented — holds `account_deletion_grace_days`, default 7 |
| `Driver.custom_legal_hold`, consent withdrawal fields | Implemented via patch |
| Nightly erasure job, `hooks.py` cron, tombstone patch | Implemented, **never executed** |
| App: `ApiConstants`, `AppController`, `DeleteAccountScreen` | Wired against the live contract |

### Outstanding before this ships

- [ ] **Rate limiter on `request_account_deletion` rejects every call.** The
      live failure as of 2026-08-03: `Either key or IP flag is required.`,
      thrown by `@frappe.rate_limit` before the function body, because its
      `key` is not in `form_dict`. Fix in §7. Confirmed on device — the
      undecorated `get_account_deletion_status` returned `{"status": "none"}`
      on the same account in the same session, so identity resolution is
      working.
- [ ] **`Driver.user_id` backfill patch.** Most Driver records have no
      `user_id`, so the strict ownership check in §2 cannot resolve a Driver
      from the session user and returns `404`. Being fixed by a backend data
      migration — **not** by a Flutter change and **not** by relaxing the
      ownership check. Separate from the rate-limiter bug above, which affects
      accounts that *do* have `user_id`.
- [ ] **Run the erasure job end to end on a disposable site.** Steps 1–11 of
      `_erase_one` have never executed. Every acceptance criterion under
      *Erasure* in §10 is unverified.
- [ ] Confirm the grace period the copy promises matches
      `account_deletion_grace_days` if it is ever changed from 7.

Worth adding to the backfill patch's own acceptance: a Driver whose `user_id`
is still empty afterwards should be reported, not skipped silently. A partner
who cannot delete their account is a compliance problem that shows up as a
support ticket, not as an alert.

### Deviations from this spec as written

1. **`UNPAID_EARNINGS` and `OPEN_DISPUTE` settlement checks were dropped**
   (§7), by decision. `COD_OUTSTANDING`, `ACTIVE_TRIP` and `LEGAL_HOLD` ship.
   Consequence: a partner owed money can delete their account and lose the
   bank details we would pay it to. Worth revisiting.
2. **`Driver.full_name`**, not `driver_name`, is the real field — this spec's
   §4 said the wrong one, and the copy-at-creation logic was fixed to match.
3. **COD balance** comes from the existing
   `driver_wallet.get_driver_cash_balance` rather than a fresh `COD Handover`
   query.
4. **The tombstone Driver patch needs `ignore_mandatory`** — this site enforces
   KYC fields on Driver that a system tombstone legitimately cannot have.
5. **`_resolve_lang()` fails soft** without a bound HTTP request, matching the
   existing `driver_uplink.py` pattern. Only reachable outside real traffic
   (jobs, console), but it crashed there.
6. **The app sends JSON**, not form-encoded — `_authorizedPostJson` is the
   established helper. Frappe accepts both; §3.1's table still describes the
   fields correctly.

---

## 1. Endpoints

Three methods. All live in the `grozfy_go` app, all authenticated.

### 1.1 Create a request

```
POST /api/method/grozfy_go.grozfy_go.api.account.request_account_deletion
```

### 1.2 Read current status

```
GET /api/method/grozfy_go.grozfy_go.api.account.get_account_deletion_status
```

Called on app launch and when the Delete Account screen opens, so a partner with
a request already running sees its state instead of being able to raise a second
one.

### 1.3 Cancel during the grace period

```
POST /api/method/grozfy_go.grozfy_go.api.account.cancel_account_deletion
```

---

## 2. Authentication

- **Session-authenticated.** `allow_guest=False`. The app already sends
  `Authorization: <token_type> <access_token>` on every authenticated call
  (`AppController._requestHeaders` / `_authHeaders`); reuse that.
- **The caller must be the account being deleted.** Resolve the Driver from the
  session user server-side. A `driver` parameter is accepted for consistency
  with the other custom methods, but if it is supplied and does not resolve to
  the session user's Driver, reject with `403`. **Never** delete a Driver named
  only by the request body.
- **System Manager / Grozfy Ops** may act on requests through Desk (approve,
  reject, force-complete). Those transitions are not exposed to the app.
- Unauthenticated callers get `401`. This is the one endpoint where falling back
  to a guest path would be catastrophic, so there is no guest path.

---

## 3. Request & response format

Standard Frappe `message` envelope throughout.

### 3.1 `request_account_deletion`

**Request** — `application/x-www-form-urlencoded` (what the app's `http.post`
sends today):

| Field            | Type   | Required | Notes |
|------------------|--------|----------|-------|
| `driver`         | string | no       | Driver docname, e.g. `HR-DRI-2026-00009`. Cross-checked against the session user; mismatch → `403`. |
| `reason`         | string | no       | Free text from the partner, max 500 chars. Not currently collected by the app — reserved so a "why are you leaving?" field can be added without a contract change. |
| `reason_code`    | string | no       | One of `Not Working Anymore`, `Privacy Concern`, `Switching Platform`, `Too Few Orders`, `Other`. Reserved, same as above. |
| `app_version`    | string | no       | e.g. `1.0.1+2`. Stored for audit, exactly as the consent record does. |
| `confirmed`      | `1`    | yes      | The partner ticked the acknowledgement. Absent or not `1` → `417`. Server-side proof that the destructive-action confirmation was shown. |

**Response — accepted (`200`)**

```json
{
  "message": {
    "status": "success",
    "request_name": "ADR-2026-00014",
    "request_status": "Approved",
    "requested_on": "2026-08-03 14:22:07",
    "scheduled_deletion_on": "2026-08-10 14:22:07",
    "cancellable_until": "2026-08-10 14:22:07",
    "blockers": []
  }
}
```

**Response — blocked by settlement (`200`, not an HTTP error)**

The partner has not done anything wrong, so this is a normal outcome the UI
renders as guidance, not as a failure:

```json
{
  "message": {
    "status": "blocked",
    "request_name": "ADR-2026-00015",
    "request_status": "Blocked",
    "requested_on": "2026-08-03 14:22:07",
    "blockers": [
      {
        "code": "COD_OUTSTANDING",
        "message": "You are holding ₹1,240 in cash collections. Hand this over before deleting your account.",
        "amount": 1240.0,
        "reference": "COD Handover"
      },
      {
        "code": "ACTIVE_TRIP",
        "message": "You have 1 delivery still in progress. Finish or return it first.",
        "count": 1,
        "reference": "EXT-DEL-TRIP-2026-00311"
      }
    ]
  }
}
```

`message` on each blocker is **display-ready and localised** to the
`Accept-Language` header the app sends (`en`, plus whatever else
`AppStrings.isSupportedLanguageCode` accepts). The app shows it verbatim; it
must not have to build sentences from codes.

**Response — already requested (`200`)**

Idempotent. Returns the existing request rather than creating a second:

```json
{
  "message": {
    "status": "already_requested",
    "request_name": "ADR-2026-00014",
    "request_status": "Approved",
    "requested_on": "2026-08-01 09:10:00",
    "scheduled_deletion_on": "2026-08-08 09:10:00",
    "cancellable_until": "2026-08-08 09:10:00",
    "blockers": []
  }
}
```

### 3.2 `get_account_deletion_status`

**Request:** no parameters (session identifies the Driver). Optional `driver`,
validated as above.

**Response — nothing pending**

```json
{ "message": { "status": "none" } }
```

**Response — pending**

Same shape as the create response, so the app has one parser.

### 3.3 `cancel_account_deletion`

**Request**

| Field          | Type   | Required | Notes |
|----------------|--------|----------|-------|
| `request_name` | string | yes      | Must belong to the session user's Driver. |

**Response**

```json
{
  "message": {
    "status": "cancelled",
    "request_name": "ADR-2026-00014",
    "request_status": "Cancelled"
  }
}
```

### 3.4 Error contract

Frappe's standard error envelope. The app reads it with
`AppController._extractServerError`, so `_server_messages` or `message` must
carry a human-readable string.

| HTTP | When | `exc_type` |
|------|------|------------|
| `401` | No session | `AuthenticationError` |
| `403` | `driver` is not the session user's Driver | `PermissionError` |
| `404` | `request_name` unknown, or the session user has no Driver record | `DoesNotExistError` |
| `409` | Cancel attempted after `cancellable_until`, or on a `Completed` request | `ValidationError` |
| `417` | `confirmed` missing | `ValidationError` |
| `429` | Rate limit hit (see §7) | `ValidationError` |

---

## 4. DocType: `Account Deletion Request`

Module `Grozfy Go`. Naming series `ADR-.YYYY.-.#####`. Submittable: **no** —
status is a plain field driven by the workflow in §5; submit/cancel semantics
would fight the grace period.

| Fieldname | Label | Type | Reqd | Notes |
|---|---|---|---|---|
| `driver` | Driver | Link → Driver | ✔ | Indexed. |
| `driver_name` | Partner Name | Data | | Fetched from `driver.driver_name`. **Copied, not fetched-on-read** — the Driver row is anonymised at completion and this must survive as an audit record. |
| `mobile_no` | Registered Mobile | Data | | Same: copied at creation. Store hashed if legal prefers (see §8). |
| `user` | User | Link → User | ✔ | The session user, captured server-side. |
| `status` | Status | Select | ✔ | `Requested`, `Blocked`, `Approved`, `Cancelled`, `Rejected`, `Completed`. Default `Requested`. Indexed. **Read-only in Desk for every role** — see §5.1. |
| `requested_on` | Requested On | Datetime | ✔ | Server clock. Never accepted from the client. |
| `scheduled_deletion_on` | Scheduled Deletion | Datetime | | `requested_on` + grace period. Set when status becomes `Approved`. |
| `cancellable_until` | Cancellable Until | Datetime | | Equals `scheduled_deletion_on`. Separate field so the two can diverge later. |
| `completed_on` | Completed On | Datetime | | Set by the erasure job. Read-only; validated together with `erasure_report` (§5.1). |
| `reason_code` | Reason | Select | | See §3.1. |
| `reason` | Reason (free text) | Small Text | | Max 500 chars. |
| `blockers` | Blockers | Table → `Account Deletion Blocker` | | Rewritten on every re-check. |
| `blocker_summary` | Blocker Summary | Small Text | | Read-only, denormalised for Desk list view. |
| `app_version` | App Version | Data | | e.g. `1.0.1+2`. |
| `request_ip` | Request IP | Data | ✔ | `frappe.local.request_ip`. Server-side only. |
| `consent_reference` | Consent Withdrawn | Link → Delivery Partner Consent | | The consent record this deletion withdraws. |
| `erasure_report` | Erasure Report | Long Text (JSON) | | What the job actually did — see §8.3. Written at completion. |
| `handled_by` | Handled By | Link → User | | Set on manual approve/reject from Desk. |
| `internal_notes` | Internal Notes | Text | | Ops only. `Permlevel 1` — never returned to the app. |

### Child DocType: `Account Deletion Blocker`

| Fieldname | Type | Notes |
|---|---|---|
| `code` | Data | `COD_OUTSTANDING`, `ACTIVE_TRIP`, `UNPAID_EARNINGS`, `OPEN_DISPUTE`, `LEGAL_HOLD` |
| `message` | Small Text | Localised, display-ready |
| `amount` | Currency | Nullable |
| `count` | Int | Nullable |
| `reference_doctype` | Link → DocType | Nullable |
| `reference_name` | Dynamic Link | Nullable |

### Permissions

| Role | Read | Write | Create | Delete |
|---|---|---|---|---|
| Grozfy Ops / Delivery Manager | ✔ | ✔ | ✔ | ✘ |
| System Manager | ✔ | ✔ | ✔ | ✔ |
| Delivery Partner (the API user) | own row only, via the whitelisted methods | ✘ | ✘ | ✘ |

The Driver must never be able to read another partner's request. Enforce with a
permission query condition on `driver`, not only in the method bodies.

---

## 5. Workflow / status flow

```
                        ┌─────────────┐
      POST request ────►│  Requested  │  (transient — checks run in the same call)
                        └──────┬──────┘
                               │ run settlement checks (§7)
                 ┌─────────────┴─────────────┐
        fail     │                           │    pass
                 ▼                           ▼
          ┌─────────────┐            ┌──────────────┐
          │   Blocked   │            │   Approved   │
          └──────┬──────┘            └──────┬───────┘
                 │ partner clears it        │ grace period elapses
                 │ → re-POST re-checks      │ (nightly scheduled job)
                 └────────────┬─────────────┘
                              ▼
                       ┌─────────────┐
                       │  Completed  │  erasure job has run; terminal
                       └─────────────┘

  Approved ──(partner cancels before cancellable_until)──► Cancelled   terminal
  Requested/Blocked/Approved ──(ops declines, with a reason)──► Rejected  terminal
```

**Grace period: 7 days.** Long enough that an accidental or angry deletion can be
undone, short enough to stay well inside the 30 days the Privacy Policy commits
to. Make it a setting (`Grozfy Settings.account_deletion_grace_days`, default 7)
rather than a constant.

**Rules**

- `Blocked` re-checks on each new POST. It does not auto-resolve — a partner who
  hands over cash and never reopens the app stays `Blocked`, which is correct:
  they have not re-asked.
- `Cancelled` and `Rejected` are terminal. A partner who changes their mind
  again raises a fresh request.
- `Rejected` requires `internal_notes` to be non-empty. Ops must say why.
- The erasure job re-runs the settlement checks immediately before erasing. Seven
  days is long enough for a new COD Handover to appear. If a check now fails, move
  back to `Blocked` and notify.
- Deletion is not reversible after `Completed`. Do not build an "undo".

### 5.1 Transition guards — `Completed` is an output, never an input

**Setting `status = "Completed"` does not erase anything.** Erasure happens in
`_erase_one()`; the job stamps `Completed` *after* it succeeds. A status edit is
therefore a silent no-op on the data — and the most dangerous edit available on
this DocType.

Left unguarded, an admin who flips the Select produces a request row asserting
the partner's data was erased on a date when it was not. The Aadhaar, PAN and
licence scans, bank details and location history are all still there. The row
then reads as compliant to anyone auditing it, `erasure_report` is empty, and
the nightly job never touches it again because it only selects `Approved`. An
erasure you cannot evidence is worse than one you never performed — you have
documented a false claim.

Guard it in four places:

1. **`status` is read-only in Desk**, for every role including System Manager.
   Ops move requests with actions, not by editing a field.
2. **Validate the transition.** `Completed` may only be set from inside the
   erasure workflow:

   ```python
   def validate(self):
       if self.has_value_changed("status") and self.status == "Completed":
           if not frappe.flags.in_account_erasure:
               frappe.throw(_(
                   "Completed is set by the erasure job. Use "
                   "\"Run Erasure Now\" — editing the status does not delete "
                   "any data."
               ))
   ```

   `_erase_one()` sets `frappe.flags.in_account_erasure = True` for the duration
   of its own run and clears it in a `finally`. The message says what to do
   instead, so the guard teaches rather than just blocks.
3. **`completed_on` and `erasure_report` are read-only too**, and validated
   together: if either is set without the other, the row was written by hand.
4. **Same rule server-side, not only in Desk.** The guard belongs in
   `validate()` so it also covers `/api/resource` writes, `db_set`, and console
   edits — not in a client script, which only covers the form.

### 5.2 The supported manual path — "Run Erasure Now"

Ops legitimately need to erase without waiting for the nightly run: closing a
grievance, honouring a regulator deadline, or exercising steps 1–11 on a test
site. That need is real, so give it a door rather than leaving the status field
as the only lever.

Add a **Run Erasure Now** button on the Account Deletion Request form, visible
only on `Approved` requests, calling a whitelisted method that invokes **the
same `_erase_one()` the scheduler uses** — not a parallel implementation:

```python
@frappe.whitelist()
def run_erasure_now(request_name):
    frappe.only_for(("System Manager",))          # narrower than the ops role
    doc = frappe.get_doc("Account Deletion Request", request_name)
    if doc.status != "Approved":
        frappe.throw(_("Only an approved request can be erased."))
    _erase_one(doc)        # re-runs settlement checks, erases, stamps Completed
```

Requirements:

- **One implementation.** `run_nightly_erasure()` iterates due requests and
  calls `_erase_one()`; this calls the same function on one request. Two code
  paths would drift, and the one used least would be the one that breaks.
- **The settlement re-check is not skipped.** Manual invocation is not an
  override — a request with outstanding COD goes back to `Blocked` here exactly
  as it would at 02:00.
- **The grace period is not skipped either.** Before `cancellable_until`, refuse
  and say why: the partner may still cancel. Erasing early removes a right the
  Privacy Policy grants in writing. If ops genuinely must erase early (a
  regulator order), that is a separate, separately-audited action — not this
  button.
- **Confirm destructively.** A modal naming the partner and the record counts
  about to be erased, not a bare "Are you sure?".
- **`handled_by` records who pressed it.** A manual erasure must name a person.

---

## 6. Validation rules

On `request_account_deletion`:

1. Session resolves to exactly one Driver. Zero → `404`. More than one → `500`
   with an ops alert; that is a data bug, not a partner problem.
2. `confirmed == "1"` → else `417`.
3. No existing request in `Requested`, `Blocked` or `Approved` → else return
   `already_requested` (not an error).
4. `reason` ≤ 500 chars; strip HTML. It reaches Desk and email.
5. `reason_code` is in the allowed set, if present.
6. Driver is not flagged `legal_hold` → else `Blocked` with `LEGAL_HOLD`.
7. `requested_on`, `request_ip`, `user` are **always** server-derived. Silently
   discard any client-supplied value; do not merely ignore it in the happy path.

On `cancel_account_deletion`:

1. Request belongs to the session user's Driver → else `403`.
2. `status == "Approved"` → else `409`.
3. `now() < cancellable_until` → else `409`.

---

## 7. Settlement checks

Run in `request_account_deletion` and again in the erasure job. Every check that
fails appends a blocker; **collect them all** rather than returning the first —
a partner should see everything they need to clear in one pass.

| Code | Check | Query | Blocking |
|---|---|---|---|
| `COD_OUTSTANDING` | Cash collected but not handed over | `driver_wallet.get_driver_cash_balance` | ✔ |
| `ACTIVE_TRIP` | Delivery in progress | `External Delivery Trip` where `driver = X` and status not in the terminal set | ✔ |
| ~~`UNPAID_EARNINGS`~~ | Money owed to the partner | **Dropped** — see Status §deviations | — |
| ~~`OPEN_DISPUTE`~~ | Unresolved complaint either way | **Dropped** — see Status §deviations | — |
| `LEGAL_HOLD` | Fraud investigation or statutory hold | Flag on Driver, or an open hold record | ✔ |

Notes:

- `UNPAID_EARNINGS` blocks deletion because erasing bank details before paying
  someone is both a support disaster and hard to defend. If ops would rather pay
  out and proceed, make it a warning — but decide deliberately, not by omission.
### Rate limiting — do not use `@frappe.rate_limit` with a `key`

Limit `request_account_deletion` to **5 calls per Driver per hour**, `429`
beyond that. The `already_requested` path is cheap but the checks are not.

**This must be done inside the function, after the Driver is resolved.**

Frappe's decorator reads its `key` out of `frappe.form_dict`. The app does not
send `driver` — §2 forbids trusting a client-supplied one — so a decorator like

```python
@frappe.rate_limit(key="driver", limit=5, seconds=3600, ip_based=False)   # ✗
```

finds nothing in `form_dict`, and every request dies before the function body
with `Either key or IP flag is required.` That was the live failure on
2026-08-03: `get_account_deletion_status` (undecorated) worked and returned
`{"status": "none"}`, while every POST threw. It is a contradiction in this
spec's own requirements — §2 removes the identity from the request, §7 asked to
rate-limit by it — not a backend mistake.

Do it against the resolved Driver instead:

```python
@frappe.whitelist(methods=["POST"])
def request_account_deletion(driver=None, confirmed=None, **kwargs):
    driver = _resolve_own_driver(driver)          # §2 — session-derived, 403 on mismatch

    cache_key = f"account_deletion_req:{driver}"
    hits = cint(frappe.cache().get_value(cache_key))
    if hits >= 5:
        frappe.throw(_("Too many requests. Please try again later."),
                     frappe.ValidationError, http_status_code=429)
    # Set the TTL on first hit so the window is a fixed hour, not a rolling one
    # that a persistent caller can keep pushing forward.
    frappe.cache().set_value(cache_key, hits + 1, expires_in_sec=3600)
    ...
```

`ip_based=True` also unblocks it with a one-word change, but it buckets every
driver behind a shared NAT or office wifi into one counter — acceptable as a
stopgap, not as the answer.
- Every blocker `message` must be actionable — say the amount and what to do, not
  "you cannot delete your account".

---

## 8. Data retention & deletion policy

This must match the Privacy Policy's *Deleting Your Account* section
(`lib/features/legal/legal_content.dart`, mirrored in
`docs/web/privacy-policy.html#delete-account`). **If this table changes, that
copy changes with it** — the policy is a public commitment.

### 8.1 Erased

| Data | DocType / store | Action |
|---|---|---|
| Name, email, address, photo | `Driver`, `Employee`, `File` | Hard delete the files; blank the fields |
| Mobile number | `Driver`, `User` | Replace with a non-routable placeholder (§8.4) |
| Aadhaar, PAN, driving licence — numbers and scans | `Driver` fields + attached `File` | **Hard delete.** Remove from disk/S3, not just the Frappe row |
| Vehicle details | `Vehicle` | Delete if owned solely by this partner; unlink otherwise |
| Bank account, UPI | `Bank Account` | Hard delete |
| Location history | `Driver Location Log` (**name to confirm**) | Hard delete all rows |
| Device / FCM tokens | wherever push tokens live | Hard delete — a deleted account must stop receiving push |
| Sessions and OAuth tokens | `Sessions`, `OAuth Bearer Token` | Revoke all, immediately, at the start of the job |
| Timing logs | `Partner Timing Log` | Hard delete |

### 8.2 Retained

| Data | Why | Treatment |
|---|---|---|
| Order records (`External Delivery`, `External Delivery Trip`) | Merchant and customer records; accounting | Keep the row, replace the driver link with the tombstone Driver (§8.4) |
| Payout and tax records | Statutory retention | Keep, linked to the tombstone |
| `COD Handover` history | Cash reconciliation and audit | Keep, linked to the tombstone |
| `Delivery Partner Consent` | Proof of what was agreed, and of the withdrawal | Keep. Set `withdrawn_on` and link to the deletion request |
| `Account Deletion Request` itself | Proof the request was honoured, and when | Keep indefinitely |

Retained records must not be usable to contact or re-identify the partner:
after erasure, no retained row may hold the name, mobile, email or any document
number.

### 8.3 Erasure report

The job writes `erasure_report` as JSON — counts per DocType, files removed, what
was skipped and why:

```json
{
  "completed_on": "2026-08-10 02:14:31",
  "erased": { "Driver Location Log": 18422, "Bank Account": 1, "File": 7, "Vehicle": 1 },
  "anonymised": { "External Delivery": 214, "COD Handover": 31 },
  "retained": { "Delivery Partner Consent": 1 },
  "skipped": []
}
```

This is what you show a regulator. Without it, "we deleted it" is an assertion.

### 8.4 Tombstone and placeholders

- One shared **tombstone Driver** — `DELETED-PARTNER` — carries every retained
  order's driver link. Do not leave dangling links, and do not delete the Driver
  row outright: that breaks foreign keys across orders, trips and COD records.
- Mobile placeholder: `+00000000000` + the request name, so it is unique,
  non-routable, and traceable back to the request. Never reuse a real format.
- The freed mobile number must be re-registrable. A partner who deletes and later
  returns signs up cleanly, as a new Driver, verifying from scratch.

### 8.5 Job characteristics

- Runs nightly (`scheduler_events.daily`) over `Approved` requests whose
  `scheduled_deletion_on` has passed.
- **Idempotent and resumable.** Erasing hundreds of thousands of location rows
  will time out at least once. Batch it, commit per batch, and make a re-run
  safe.
- On unrecoverable failure: leave the request `Approved`, log the error, alert
  ops. Never mark `Completed` on a partial erasure.

---

## 9. Notifications

| Event | To partner | To ops |
|---|---|---|
| `Approved` | "We received your request. Your account and data will be deleted on {date}. Cancel any time before then in the app." | Digest |
| `Blocked` | The blocker messages, verbatim | Immediate, if `COD_OUTSTANDING` |
| `Cancelled` | "Your account will not be deleted." | — |
| `Rejected` | The reason, in plain language | — |
| `Completed` | Final confirmation, sent **before** the contact details are erased | Digest |

Send to the registered email and, if there is a template, WhatsApp — the same
channel the OTP uses. The `Completed` notice must go out before erasure or there
is nowhere to send it.

---

## 10. Acceptance criteria

**API**

- [ ] `request_account_deletion` with a valid session and `confirmed=1` creates
      an `Account Deletion Request` and returns `status: "success"` with
      `request_name` and `scheduled_deletion_on`.
- [ ] Calling it twice returns `already_requested` with the same `request_name`.
      Exactly one open request exists per Driver.
- [ ] Without a session → `401`. With a `driver` belonging to someone else →
      `403`, and no row is created.
- [ ] Without `confirmed=1` → `417`.
- [ ] Sixth call within an hour → `429` — and the **first five succeed**. A
      rate limiter that rejects call one is the failure mode this spec already
      caused once (§7).
- [ ] `get_account_deletion_status` returns `{"status": "none"}` for a clean
      account and the full object for a pending one.
- [ ] `cancel_account_deletion` inside the window sets `Cancelled`; after the
      window → `409`; on someone else's request → `403`.

**Settlement**

- [ ] A driver holding unsubmitted COD gets `status: "blocked"` with
      `COD_OUTSTANDING` and the correct amount, and no deletion is scheduled.
- [ ] A driver with an in-progress trip gets `ACTIVE_TRIP`.
- [ ] A driver with two problems gets **both** blockers in one response.
- [ ] Clearing the blockers and re-posting moves the request to `Approved`.
- [ ] A blocker that appears during the grace period sends the request back to
      `Blocked` instead of erasing.

**Erasure**

- [ ] After the job runs: Aadhaar, PAN, licence numbers and their files are gone
      from the database **and** from disk/object storage.
- [ ] Bank Account and location history rows are gone.
- [ ] Every `External Delivery` the partner served still exists and still
      reconciles, now pointing at the tombstone Driver.
- [ ] No retained row anywhere contains the partner's name, mobile, email or any
      document number. Verify by grepping the DB for the test partner's details —
      zero hits.
- [ ] All sessions and bearer tokens are revoked; the app is logged out and
      cannot refresh.
- [ ] Push notifications stop.
- [ ] The mobile number can be used to register a brand-new account.
- [ ] `erasure_report` is populated with per-DocType counts.
- [ ] Re-running the job on a `Completed` request changes nothing and raises
      nothing.

**Transition guards (§5.1, §5.2)**

- [ ] Editing `status` to `Completed` in Desk is refused, with a message
      pointing at *Run Erasure Now*.
- [ ] The same edit via `/api/resource` and via `db_set` in the console is also
      refused — the guard is in `validate()`, not a client script.
- [ ] Setting `completed_on` or `erasure_report` by hand is refused.
- [ ] After a refused edit, the partner's data is **still fully present** — the
      point of the guard is that a status flip never implied erasure.
- [ ] *Run Erasure Now* on an `Approved` request past its grace period erases,
      stamps `Completed`, writes `erasure_report`, and records `handled_by`.
- [ ] *Run Erasure Now* on a request still inside its grace period is refused,
      naming the date the partner can no longer cancel.
- [ ] *Run Erasure Now* on a request with outstanding COD moves it to `Blocked`
      and erases nothing — manual invocation is not an override.
- [ ] The button is absent on `Requested`, `Blocked`, `Cancelled`, `Rejected`
      and `Completed` requests.
- [ ] `run_nightly_erasure()` and *Run Erasure Now* call the same
      `_erase_one()`. Verified by reading the code, not by both appearing to
      work.
- [ ] Interrupting the job mid-run and restarting completes cleanly.

**Records**

- [ ] The `Delivery Partner Consent` row survives, marked withdrawn and linked to
      the request.
- [ ] The `Account Deletion Request` survives with `requested_on`,
      `completed_on`, `request_ip` and `app_version`.
- [ ] A partner cannot read another partner's request through any API path,
      including `/api/resource`.

**End to end**

- [ ] From the app: More → Delete Account → tick → submit → confirmation
      showing the deletion date. Reopening the screen shows the pending state,
      not a fresh form.
- [ ] Cancel from the app → account fully usable, orders and earnings intact.
- [ ] The 30-day commitment in the Privacy Policy holds: worst case is 7 days
      grace + one nightly run.

---

## 11. App side — done

- `ApiConstants.requestAccountDeletion` / `.accountDeletionStatus` /
  `.cancelAccountDeletion`.
- `AppController.requestAccountDeletion()`, `.fetchAccountDeletionStatus()`,
  `.cancelAccountDeletion()` — all returning
  `({AccountDeletionStatus? data, String? error})`. A `blocked` response comes
  back as **data, not an error**, because it is a normal outcome.
- `AccountDeletionStatus` / `AccountDeletionBlocker` in `app_models.dart`.
- `DeleteAccountScreen` has three states: the form, the blocked list, and a
  scheduled request with a Cancel button. It reads the status on open, so a
  partner with a live request sees it instead of a form.
- **No email fallback.** The API is the only deletion path. A failed call shows
  the server's own message and leaves the form to retry from — routing around a
  broken endpoint would make a request that never landed look like one that
  did, and would hide the failure from us.
- **No reason field yet.** `reason` / `reason_code` stay reserved on the
  contract (§3.1); the screen does not collect them. `AppController
  .requestAccountDeletion()` still accepts both as optional named parameters so
  adding the UI later needs no API change — nothing sends them today.

**Correction to an earlier draft of this spec:** it said to sign the partner out
on success. That was wrong. With a 7-day grace period the session must stay
alive — they need the app to cancel, and they can keep working until the job
runs. The app does not log them out.

If `account_deletion_grace_days` changes, or the retention table in §8 changes,
the *Deleting Your Account* copy in `legal_content.dart` and
`docs/web/privacy-policy.html` must change with it.
