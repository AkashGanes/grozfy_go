# Backend spec: `get_cod_limit_status` / `accept_delivery`

Cash-in-hand (COD) exposure limit for the driver app. Caps how much uncollected +
unsettled cash a driver may be holding, blocks new **COD** order acceptance once
the cap would be breached, and leaves **prepaid/online** orders acceptable so the
driver keeps earning while carrying cash.

The app renders the status on the dashboard and the Daily Settlement screen, and
performs a fast-fail pre-check before accepting. That check is a UX convenience
only — the Flutter client is not a trust boundary, so the server must enforce the
rule independently (see [Enforcement](#enforcement)).

## Exposure formula

```
cash_in_hand = settled_balance   # unsettled cash already collected from delivered COD orders
             + in_flight_cod     # SUM(cod_amount_to_collect) of accepted-but-undelivered COD orders

accept allowed if:  cash_in_hand + this_order.cod_amount <= max_limit
```

`settled_balance` is the same quantity the existing
`cod_settlement.get_driver_settlement_today` reports as `remaining_balance`
(`carried_forward_balance + total_collected_today - amount_transferred`). Reuse
that computation rather than re-deriving it, so the two screens can never
disagree.

Counting `in_flight_cod` is what makes the limit meaningful. Without it a driver
holding zero cash could accept ten large COD orders at once and only breach the
cap hours later at delivery time, when refusing the cash is no longer an option.

## Configuration

Follows the `custom_delivery_radius_*` precedent — the backend owns every value
and the app never persists its own copy.

| Where | Field | Notes |
|---|---|---|
| Settings doctype (global) | `cod_limit_enabled` | Check. Master switch; when off the feature is invisible in the app. |
| Settings doctype (global) | `cod_cash_limit` | Currency. Default ceiling for all drivers. |
| Settings doctype (global) | `cod_limit_warning_percent` | Int, default `80`. Percentage of the limit at which the app warns. |
| Driver DocType | `custom_cod_cash_limit` | Currency, optional. Per-driver override. |

Resolution order: `custom_cod_cash_limit` (when > 0) → `cod_cash_limit`. If
neither resolves to a positive number, treat the feature as disabled for that
driver rather than blocking everything.

---

## Endpoint 1 — read status

```
GET /api/method/grozfy_go.grozfy_go.api.cod_settlement.get_cod_limit_status
```

> If the method lands in a different module, update
> `ApiConstants.getCodLimitStatus` in the app to match.

### Request (query params)

| Param    | Required | Notes |
|----------|----------|-------|
| `driver` | yes      | Driver docname (e.g. `HR-DRI-2026-00009`). Same convention as every other grozfy custom method — the OAuth user is a shared API user, so the driver is passed explicitly. |

### Response

Standard Frappe `message` envelope:

```json
{
  "message": {
    "enabled": true,
    "settled_balance": 3000.0,      // unsettled cash already collected
    "in_flight_cod": 1200.0,        // accepted-but-undelivered COD exposure
    "cash_in_hand": 4200.0,         // settled_balance + in_flight_cod
    "max_limit": 5000.0,
    "available_limit": 800.0,       // max(0, max_limit - cash_in_hand)
    "warning_threshold_percent": 80.0,
    "state": "warning",             // "ok" | "warning" | "blocked"
    "in_flight_orders": 2,
    "currency": "INR"
  }
}
```

### Field notes

- **`state` is computed server-side** so the app and server can never disagree
  about where the warning/block thresholds sit. `blocked` when
  `cash_in_hand >= max_limit`; `warning` when
  `cash_in_hand >= max_limit * warning_threshold_percent / 100`; else `ok`.
- `enabled: false` is a complete opt-out — the app hides the card, hides the
  settlement row, and skips its accept pre-check. Every other field may be `0`.
- All amounts are plain numbers (not formatted strings). `currency` is advisory;
  the app currently hardcodes `₹`.
- `available_limit` is floored at `0` — never return a negative number. A driver
  already over the cap reports `0`, not a negative headroom.
- `in_flight_orders` is a count, used only for the card's subtitle.

### Server obligations

- Derive `in_flight_cod` from **order status on the server**. Do not accept an
  order list from the client — the app's active-order cache is not authoritative
  and survives logout/login via SharedPreferences.
- When a COD order's `cod_amount_to_collect` is null or `0`, fall back to
  `grand_total`. The app already has this gap (`delivery_tracking_screen.dart:822`
  and `navigation_screen.dart:81` skip COD capture when the amount is `0`), so a
  server-side fallback prevents an order silently contributing zero exposure.
- Treat an order as COD using the same predicate as the app
  (`ExternalDeliveryDetail.isCod`): `payment_method == 'COD'` or
  `payment_mode == 'COD'`, case-insensitive.

---

## Endpoint 2 — atomic accept

```
POST /api/method/grozfy_go.grozfy_go.api.driver.accept_delivery
```

### Request (JSON body)

| Param               | Required | Notes |
|---------------------|----------|-------|
| `driver`            | yes      | Driver docname. |
| `external_delivery` | yes      | External Delivery docname being accepted. |

### Response

```json
{
  "message": {
    "success": true,
    "external_delivery": "EXT-DEL-2026-03076",
    "trip": "EDT-2026-00412",
    "status": "Added to Trip"
  }
}
```

On rejection, `frappe.throw` with a driver-facing message, e.g.

> Cash limit reached. You are holding ₹4,200 of your ₹5,000 limit. Settle cash to accept more COD orders.

The app surfaces `_server_messages` verbatim (`_extractErrorMessage` reads it
first), so the thrown string is what the driver reads — write it for them, not
for a developer.

### Server obligations

In one transaction:

1. Re-check the order is still `Pending` (guards the race where another partner
   accepted it first).
2. Resolve the driver's limit; if the order is COD and
   `cash_in_hand + cod_amount > max_limit`, throw. Skip the check entirely for
   non-COD orders — prepaid must stay acceptable while blocked.
3. Set `status = 'Added to Trip'` **and** `driver` on the order.
4. Create and submit the External Delivery Trip.

---

## Enforcement

The app has **three** accept paths and they do not share a choke point:

| Path | What it writes | `driver` visible? |
|---|---|---|
| `AppController.acceptOrder` (`app_controller.dart:3761`) | `frappe.client.set_value` for `status` only, then trip creation, then a separate `driver` set_value | **No** at status-write time |
| `_createBatchTrip` (`order_listing_screen.dart:637`) | POST `/api/resource/External Delivery Trip` `{driver, docstatus: 1, stops[]}` | Yes |
| `_acceptDelivery` (`delivery_list_screen.dart:494`) | same Trip POST | Yes |

**Why a single hook is not enough.** In `acceptOrder`, both the trip-creation and
the driver-stamp calls are wrapped in swallowing `catch (_) {}`
(`app_controller.dart:3810-3825`). Enforcing only on the Trip doctype would let
the order flip to `Added to Trip` while the trip silently fails — the driver sees
success and the cap is bypassed. Enforcing only on the External Delivery
`validate` hook also fails, because at status-write time the doc has no `driver`
on it yet, so there is nobody to check the limit against.

**Enforce in both places:**

1. **`accept_delivery` (primary).** Endpoint 2 above. Atomic, sees the driver,
   and becomes the single choke point once the app migrates to it.
2. **`validate` hook on External Delivery Trip (defense-in-depth).** Sums COD
   exposure across the trip's stops and throws if the driver would exceed. This
   is **required, not optional** — the two batch paths never call `acceptOrder`,
   so without it they are an open bypass regardless of what the app does.

Both surface through the app's existing `_extractErrorMessage` →
`_server_messages` chain, so no new error plumbing is needed client-side.

---

## App wiring (already done)

- `ApiConstants.getCodLimitStatus`, `ApiConstants.acceptDelivery`
- `CodLimitStatus` model (`lib/features/cod_settlement/model/cod_limit_status.dart`)
  parsing every key above, with a pure
  `blockReasonFor({required bool isCod, required double amount})` decision method
- `CodSettlementRepository.getCodLimitStatus()` and
  `getCodLimitStatusOrNull()` (the latter swallows method-unavailable errors)
- `codLimitStatusProvider` (`lib/features/cod_settlement/providers/settlement_provider.dart`),
  invalidated alongside `settlementProvider` and after bank transfer / COD handover
- COD pre-check in `AppController.acceptOrder`, reusing the fresh
  `ExternalDeliveryDetail` it already fetches; **fails open** on any error
- `CashInHandCard` on the dashboard; cash-in-hand chip on `DailySettlementScreen`

Until the backend ships, `getCodLimitStatusOrNull()` returns null on `404` /
`has no attribute` / `failed to get method`, so the card is hidden and acceptance
behaves exactly as it does today. Same rollout discipline as `fc91f71`
(`list_available_deliveries`).

## Out of scope / follow-ups

- The Available Orders list is **not** limit-aware. `ExternalDelivery` (the list
  model) carries no payment fields, so per-card COD lock states would need
  `payment_method` / `cod_amount_to_collect` added to the
  `list_available_deliveries` feed. Deferred deliberately — the block happens at
  accept time, where the app already fetches full order detail.
- The app does not yet call `accept_delivery`; `acceptOrder` still runs its legacy
  set_value → trip → stamp sequence. Migrating it is a follow-up that also fixes
  the swallowed trip/driver-stamp failures. **Until then the Trip `validate` hook
  is the only real enforcement**, so it must ship with this feature.
- No partial-settlement flow: the limit only frees up via the existing bank
  transfer and COD handover paths.
