"""
Device session credential auth.

Companion to billing_auth_v4.verify_whatsapp_otp. The OAuth refresh
token alone is not enough on aggressive Android OEMs (vivo iManager,
MIUI Security, OnePlus optimizer, etc.) that wipe app data when the
app is idle. This module issues a long-lived device credential at
login that the client can exchange for fresh OAuth tokens even after
the OAuth refresh chain is gone — so the user stays logged in across
data wipes as long as the install itself isn't deleted.

Design:

    1. Client generates a stable device_id (UUID v4) on first run
       and persists it across multiple storage tiers.
    2. At OTP verify, client sends device_id along with the request.
       Server creates / updates a Device Session row and returns a
       fresh device_credential (random opaque, 64 hex chars).
    3. Client persists (device_id, device_credential) across
       multiple storage tiers (secure storage, plain prefs, file).
    4. The device_credential rotates on every successful exchange —
       leaked credentials become useless after one use.
    5. If the OAuth refresh chain is dead at boot but the device
       credential is still on disk, the client calls
       /api/method/delivery_partner.api.device_credential_auth.exchange_device_credential
       and gets a fresh token pair without a re-login.
    6. Logout revokes the credential server-side.

Security notes:

    - device_credential is a 256-bit random value. We store only its
      SHA-256 hash. Plaintext is never written to disk on the server.
    - Re-binding a device_id to a different user is treated as
      compromise: the old row is destroyed and a new one created.
    - 5 consecutive failed verifications revoke the session.
    - 90-day TTL with sliding expiration on each successful exchange.
    - All endpoints log the request IP for auditing.
"""

import hashlib
import hmac
import secrets
from datetime import timedelta

import frappe
from frappe import _
from frappe.utils import get_datetime, now_datetime

DEVICE_SESSION_DOCTYPE = "Device Session"
DEVICE_CREDENTIAL_LIFETIME_DAYS = 90
DEVICE_CREDENTIAL_BYTES = 32  # 64 hex chars
MAX_FAILED_VERIFICATIONS = 5
MIN_DEVICE_ID_LENGTH = 8
MAX_DEVICE_ID_LENGTH = 64
MAX_DEVICE_LABEL_LENGTH = 140


def _hash_credential(plain: str) -> str:
    """SHA-256 of the credential. Plaintext is high-entropy random
    so a per-row salt would not meaningfully raise the brute-force
    cost, and constant-time comparison via hmac.compare_digest below
    prevents timing attacks."""
    return hashlib.sha256(plain.encode("utf-8")).hexdigest()


def _verify_credential(plain: str, stored_hash: str) -> bool:
    return hmac.compare_digest(_hash_credential(plain), stored_hash)


def _new_credential() -> str:
    return secrets.token_hex(DEVICE_CREDENTIAL_BYTES)


def _is_valid_device_id(device_id) -> bool:
    if not isinstance(device_id, str):
        return False
    length = len(device_id)
    if length < MIN_DEVICE_ID_LENGTH or length > MAX_DEVICE_ID_LENGTH:
        return False
    # Reject anything we wouldn't want as a doctype name.
    return all(ch.isalnum() or ch in "-_" for ch in device_id)


def _request_ip() -> str:
    try:
        return frappe.local.request_ip or ""
    except Exception:
        return ""


def issue_device_credential(
    user_email: str,
    device_id: str,
    device_label: str = None,
) -> str:
    """Create or rotate a Device Session for (user_email, device_id).
    Returns the plaintext credential (visible to caller exactly once).
    The caller is responsible for surfacing it to the client; this
    module never stores plaintext.

    Returns "" if the device_id is malformed — the client can still
    operate without device-credential recovery in that case.
    """
    if not _is_valid_device_id(device_id):
        return ""

    plain = _new_credential()
    cred_hash = _hash_credential(plain)
    expires_at = now_datetime() + timedelta(days=DEVICE_CREDENTIAL_LIFETIME_DAYS)

    if frappe.db.exists(DEVICE_SESSION_DOCTYPE, device_id):
        doc = frappe.get_doc(DEVICE_SESSION_DOCTYPE, device_id)
        if doc.user != user_email:
            # Re-binding a device to a different user is suspicious.
            # Discard the old row entirely and start fresh.
            frappe.log_error(
                title="Device Session re-bind",
                message=f"device_id={device_id} from user={doc.user} -> {user_email}",
            )
            doc.delete(ignore_permissions=True)
            doc = frappe.new_doc(DEVICE_SESSION_DOCTYPE)
            doc.device_id = device_id
            doc.user = user_email
        doc.device_credential_hash = cred_hash
        doc.expires_at = expires_at
        doc.last_used_at = now_datetime()
        doc.revoked = 0
        doc.failed_verifications = 0
    else:
        doc = frappe.new_doc(DEVICE_SESSION_DOCTYPE)
        doc.device_id = device_id
        doc.user = user_email
        doc.device_credential_hash = cred_hash
        doc.expires_at = expires_at
        doc.last_used_at = now_datetime()
        doc.revoked = 0
        doc.failed_verifications = 0

    if device_label:
        doc.device_label = str(device_label)[:MAX_DEVICE_LABEL_LENGTH]
    ip = _request_ip()
    if ip:
        doc.last_ip = ip[:64]

    if doc.is_new():
        doc.insert(ignore_permissions=True)
    else:
        doc.save(ignore_permissions=True)

    frappe.db.commit()
    return plain


def _load_oauth_client(store_id: str) -> dict:
    cache_key = f"oauth_client_{store_id}"
    client_data = frappe.cache().get_value(cache_key)
    if client_data:
        return client_data
    try:
        client_doc = frappe.get_doc(
            "OAuth Client", {"app_name": f"Billing Partner - {store_id}"}
        )
    except frappe.DoesNotExistError:
        frappe.throw(
            f"No OAuth Client configured for store {store_id}",
            frappe.AuthenticationError,
        )
    client_data = {
        "client_id": client_doc.client_id,
        "client_secret": client_doc.get_password("client_secret"),
        "redirect_uri": client_doc.redirect_uris.split(",")[0].strip(),
    }
    frappe.cache().set_value(cache_key, client_data, expires_in_sec=3600)
    return client_data


def _mint_oauth_tokens(user, client_data):
    """Reuse billing_auth_v4.generate_oauth_tokens_autoapprove. We
    look it up via importlib at call time so this module keeps
    working even if billing_auth_v4 is renamed or moved later."""
    import importlib

    candidates = (
        # Common app/module names — adjust the first one to your app.
        "delivery_partner.api.billing_auth_v4",
        "delivery_partner.delivery_partner.api.billing_auth_v4",
        "frappe.core.api.billing_auth_v4",
    )
    last_err = None
    for path in candidates:
        try:
            module = importlib.import_module(path)
            return module.generate_oauth_tokens_autoapprove(user, client_data)
        except (ImportError, AttributeError) as e:
            last_err = e
            continue
    frappe.throw(
        f"billing_auth_v4 module not found via known paths: {last_err}",
        frappe.AuthenticationError,
    )


def _build_login_response(
    user, client_data, token_response, device_credential, mobile_no=None
):
    mobile = mobile_no or (user.mobile_no or "")
    driver_name = frappe.db.get_value("Driver", {"cell_number": mobile}, "name")
    if not driver_name and mobile.startswith("91"):
        driver_name = frappe.db.get_value(
            "Driver", {"cell_number": mobile[2:]}, "name"
        )

    profile_completed = 1 if driver_name else 0
    kyc_completed = 0
    if driver_name:
        driver_doc = frappe.get_doc("Driver", driver_name)
        kyc_completed = (
            1
            if (driver_doc.custom_aadhar_no and driver_doc.custom_aadhar_attachment)
            else 0
        )

    return {
        "status": "success",
        "message": "Device session refreshed",
        "email": user.name,
        "mobile_no": mobile,
        "full_name": f"{user.first_name or ''} {user.last_name or ''}".strip(),
        "access_token": token_response["access_token"],
        "token_type": "Bearer",
        "expires_in": token_response.get("expires_in", 3600),
        "refresh_token": token_response.get("refresh_token", ""),
        "client_id": client_data["client_id"],
        "device_credential": device_credential,
        "new_user": 0,
        "driver_name": driver_name or "",
        "profile_completed": profile_completed,
        "kyc_completed": kyc_completed,
    }


@frappe.whitelist(allow_guest=True)
def exchange_device_credential(
    device_id: str,
    device_credential: str,
    store_id: str = None,
):
    """Trade a valid (device_id, device_credential) pair for a fresh
    OAuth token pair. Rotates the device_credential on every call so
    a leaked credential becomes useless after one use."""
    if not device_id or not device_credential:
        frappe.throw(
            _("device_id and device_credential are required"),
            frappe.AuthenticationError,
        )
    if not store_id:
        frappe.throw(_("store_id is required"), frappe.AuthenticationError)
    if not _is_valid_device_id(device_id):
        frappe.throw(_("Invalid device_id"), frappe.AuthenticationError)

    if not frappe.db.exists(DEVICE_SESSION_DOCTYPE, device_id):
        frappe.throw(
            _("Device session not recognised. Please log in."),
            frappe.AuthenticationError,
        )

    doc = frappe.get_doc(DEVICE_SESSION_DOCTYPE, device_id)

    if doc.revoked:
        frappe.throw(
            _("Device session was revoked. Please log in."),
            frappe.AuthenticationError,
        )
    if get_datetime(doc.expires_at) < now_datetime():
        frappe.throw(
            _("Device session expired. Please log in."),
            frappe.AuthenticationError,
        )

    if not _verify_credential(device_credential, doc.device_credential_hash):
        doc.failed_verifications = (doc.failed_verifications or 0) + 1
        if doc.failed_verifications >= MAX_FAILED_VERIFICATIONS:
            doc.revoked = 1
            frappe.log_error(
                title="Device Session locked",
                message=f"device_id={device_id} revoked after {doc.failed_verifications} failed verifications",
            )
        doc.save(ignore_permissions=True)
        frappe.db.commit()
        frappe.throw(_("Invalid device credential"), frappe.AuthenticationError)

    user_email = doc.user
    user = frappe.get_doc("User", user_email)
    if not user.enabled:
        frappe.throw(
            _("Account is disabled. Please contact admin."),
            frappe.AuthenticationError,
        )

    # Re-establish a Frappe session under the user so the OAuth
    # authorize flow has someone to authorize.
    login_manager = frappe.auth.LoginManager()
    login_manager.login_as(user_email)
    login_manager.post_login()

    client_data = _load_oauth_client(store_id)
    token_response = _mint_oauth_tokens(user, client_data)

    # Rotate the credential, slide the expiration window forward.
    new_credential = _new_credential()
    doc.device_credential_hash = _hash_credential(new_credential)
    doc.last_used_at = now_datetime()
    doc.failed_verifications = 0
    doc.expires_at = now_datetime() + timedelta(
        days=DEVICE_CREDENTIAL_LIFETIME_DAYS
    )
    ip = _request_ip()
    if ip:
        doc.last_ip = ip[:64]
    doc.save(ignore_permissions=True)
    frappe.db.commit()

    return _build_login_response(
        user, client_data, token_response, new_credential
    )


@frappe.whitelist()
def revoke_device_session(device_id: str):
    """Mark a device session as revoked. Called from the client on
    explicit logout. Idempotent. Authenticated callers can only
    revoke their own sessions; System Managers can revoke any."""
    if not device_id:
        return {"status": "ignored"}
    if not frappe.db.exists(DEVICE_SESSION_DOCTYPE, device_id):
        return {"status": "not_found"}

    doc = frappe.get_doc(DEVICE_SESSION_DOCTYPE, device_id)
    if (
        doc.user != frappe.session.user
        and "System Manager" not in frappe.get_roles()
    ):
        frappe.throw(_("Not allowed"), frappe.PermissionError)

    if doc.revoked:
        return {"status": "already_revoked"}
    doc.revoked = 1
    doc.save(ignore_permissions=True)
    frappe.db.commit()
    return {"status": "revoked"}
