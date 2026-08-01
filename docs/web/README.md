# Hosted legal pages

Static web copies of the in-app Privacy & Legal module. No build step, no
dependencies — three files that can be dropped on any static host.

```
docs/web/
├── privacy-policy.html     ← REQUIRED by Play (store listing)
├── terms.html              ← optional; not required by Play
└── assets/legal.css
```

## Source of truth

The copy on these pages is generated from
`lib/features/legal/legal_content.dart` — `kPrivacySections`, `kTermsSections`,
`kDataGroups`, `kPermissions`. **If that file changes, change these pages in the
same commit.** A mismatch between the hosted policy and the Play Data Safety
form is the most common cause of a store rejection.

Version and contact details come from `lib/core/constants/legal_constants.dart`
(`documentVersion`, `lastUpdated`, `privacyEmail`, `supportEmail`,
`supportPhone`, `supportHours`, `grievanceOfficer`, `officeAddress`). Those are
inlined here rather than templated, so they must be updated in both places.

## Publishing

Serve the folder at these paths, matching `LegalConstants`:

| File | URL |
|---|---|
| `privacy-policy.html` | `https://grozfy.com/partner/privacy-policy` |
| `terms.html` | `https://grozfy.com/partner/terms` |

The relative links between the pages assume they stay in the same directory. If
you publish at extensionless URLs, either configure the host to serve
`privacy-policy.html` for `/partner/privacy-policy`, or update the cross-links
in each file.

Play's requirements for these URLs:

- **HTTPS.** `http://` policy links are rejected.
- **Publicly reachable with no login.**
- **Not user-editable.** Google Docs and Drive links are rejected.
- **Stable.** The URL is checked again at every app review.

## Where each URL goes in Play Console

- **Privacy policy** → Play Console → *App content* → *Privacy policy*. Also
  appears on the store listing.

## Known gaps before submission

1. **Placeholder details.** `grozfy.com`, the phone number and the office
   address in `legal_constants.dart` and in these pages are placeholders.
   Replace with the real published values.
2. **There is no account deletion path, in-app or on the web.** It was removed
   on request. Google Play requires apps that allow account creation to also
   offer in-app deletion plus a web-accessible deletion URL (*Data safety* →
   *Data deletion*), so this is an open blocker for a Play release — not an
   oversight in this folder. Restoring it means bringing back
   `lib/features/legal/delete_account_screen.dart`, its route, and a deletion
   page here.
3. **Backend is still plain HTTP.** `ApiConstants.erpBaseUrl` points at
   `http://209.182.232.35:8004`, which carries Aadhaar, PAN, driving licence,
   bank details and GPS. The Data Safety form would have to declare data as
   *not encrypted in transit*, and iOS cannot reach the backend at all because
   `ios/Runner/Info.plist` has no ATS exception. Neither of these is fixed by
   this folder.
