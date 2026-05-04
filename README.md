# Grozfy Go

A stylish Flutter delivery-partner app scaffold covering complete onboarding,
KYC, permissions, order flow, and operational dashboard.

## Implemented Scope

### Phase 1: App Entry & Authentication
- Splash screen with animation, session restore check, and config bootstrap.
- Language selection with local persistence.
- Partner registration form with OTP flow and basic validation.
- Login with `Mobile + OTP` and `Mobile + Password` modes.
- WhatsApp OTP integration:
  - `POST https://grozfy.com/api/method/frappe.core.api.billing_auth_v4.send_whatsapp_otp`
  - `POST https://grozfy.com/api/method/frappe.core.api.billing_auth_v4.verify_whatsapp_otp`
  - Request params include `mobile_no` and `store_id` (`GROZFY`), and verify also sends `otp`.
  - Access token is cached locally for auto-login.

### Phase 2: KYC & Profile Verification
- KYC document upload states for ID, driving license, selfie.
- Vehicle details form with format validation and RC upload step.
- Bank account setup form with account and IFSC validation.

### Phase 3: Permissions & Location Setup
- Foreground/background location + notification permission UI.
- Tracking setup with configurable interval and live coordinate updates.

### Phase 4: Order Flow System
- Incoming order request card with accept/reject and countdown timeout.
- Order details page with customer/store info and quick actions.
- Navigation page (Google Maps / in-app placeholders) with ETA and distance.
- Order status lifecycle progression up to delivered.

### Phase 5: Dashboard (Main Screen)
- Online/offline toggle with KYC and permission gating.
- Earnings summary and performance metrics.
- Active order card with quick navigation actions.
- Notification center and quick access menu.

## Architecture

- `lib/core/models/app_models.dart`: domain models and enums.
- `lib/core/state/app_controller.dart`: app state + backend-ready logic stubs.
- `lib/core/state/app_scope.dart`: app-wide state access.
- `lib/core/navigation/app_routes.dart`: route constants.
- `lib/core/widgets/app_shell.dart`: reusable stylish layout components.
- `lib/features/*`: feature-based screen modules.

## Run

```bash
flutter pub get
flutter run
```

## Validation

```bash
flutter analyze
flutter test
```

## Notes for Production Integration

Current implementation still uses placeholders for config fetch, tracking,
and order assignment. Next production steps:

- Move token storage from shared preferences to secure storage for production.
- KYC file storage + admin approval APIs.
- Real Google Maps/location plugins + websocket/location backend.
- Secure payout and banking compliance workflow.
