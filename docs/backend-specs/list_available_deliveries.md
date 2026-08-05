# Backend spec: `list_available_deliveries`

Radius-aware feed for the driver app's **Available Orders** screen
(`orders_by_location_screen.dart`). The app now calls this instead of the
generic `/api/resource/External Delivery` list, which was radius-blind.

## Endpoint

```
GET /api/method/grozfy_go.grozfy_go.api.delivery_radius.list_available_deliveries
```

> If the method actually lives in a different module (e.g. `...api.driver.`),
> update `ApiConstants.listAvailableDeliveries` in the app to match.

## Request (query params)

| Param        | Required | Notes                                                                 |
|--------------|----------|-----------------------------------------------------------------------|
| `driver`     | yes      | Driver docname (e.g. `HR-DRI-2026-00009`). Same convention as every other grozfy custom method — the OAuth user is a shared API user, so the driver is passed explicitly. Used to resolve the driver's location + selected radius. |
| `store_name` | no       | When present, restrict to that store.                                 |
| `filters`    | no       | JSON-encoded Frappe filter clauses for status/date/customer, exactly as the app builds them, e.g. `[["External Delivery","status","in",["Pending"]],["External Delivery","creation",">=","2026-07-01 00:00:00"]]`. |

The server must additionally constrain results to deliveries whose distance from
the driver's current location is `<= selected_radius_km` (falling back to
`default_km` when the driver hasn't chosen one — see the delivery-radius
contract).

## Response

Standard Frappe `message` envelope — the **full** radius-filtered set in one
call (no pagination; the app treats it as a single page):

```json
{
  "message": [
    {
      "name": "EXT-DEL-2026-03076",
      "store_name": "Sunrise Mart",
      "store_url": "https://...",
      "customer_name": "A. Kumar",
      "status": "Pending",
      "creation": "2026-07-23 10:12:00",
      "modified": "2026-07-23 10:40:00",
      "delivery_address": "ADDR-...",   // address docname or resolved text
      "latitude": 8.135,
      "longitude": 77.350,
      "distance_km": 1.8               // server-computed driver→delivery distance
    }
  ]
}
```

### Field notes
- Keys must match the generic list (`ExternalDelivery.fromJson`): `name`,
  `store_url`, `store_name`, `customer_name`, `status`, `creation`, `modified`,
  `delivery_address`, `latitude`, `longitude`.
- `distance_km` (number) is new and app-consumed. The app **parses and stores**
  it on the model but does not yet sort or display by it — keep it present so a
  later UI/sort change needs no backend work.
- Ordering is not relied upon: the app re-sorts by `store_name asc, modified
  desc` client-side to preserve store-header grouping.

## App wiring (already done)
- `ApiConstants.listAvailableDeliveries`
- `ExternalDeliveryRepository.fetchAvailableDeliveries({storeName, filters})`
- `ExternalDelivery.distanceKm` / `ExternalDeliveryDetail.distanceKm` (`distance_km`)
- `AppController._deliveryOrderFromDetail` prefers `detail.distanceKm` (server)
  over the client-side Haversine estimate, so the existing "Distance" row shows
  the server value with no UI change.
- `OrderListingScreen` (the available/Pending order pool) — `_fetchOrdersEnriched`
  now calls `fetchAvailableDeliveries`; `_fetchPage` treats it as a single page.

Only the available-orders list was switched. The generic `fetchPage` /
`fetchPageEnriched` methods are unchanged and still used by the in-screen
**search** (query by name/store/customer), `fetchActiveSummaries`, and the
`orders_by_location` screen — none of which are radius-limited. If search should
also be radius-filtered, that's a follow-up.
