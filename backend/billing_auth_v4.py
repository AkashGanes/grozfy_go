import time
import random
from urllib.parse import parse_qs, urlparse

from frappe.utils import random_string, get_url

import frappe

import json

import requests

from google.oauth2 import id_token as google_id_token

from google.auth.transport import requests as grequests

config = frappe.get_conf()

api_key = config.get("oxifix_api_key")

api_secret = config.get("oxifix_api_secret")

grozfy_url = "http://178.236.185.133:8001/api/method/frappe.core"


# =====================
# Helper functions
# =====================

def normalize_mobile(mobile_no):
    """Normalize mobile number - remove formatting, ensure country code"""
    if mobile_no is None:
        return ""

    mobile_str = str(mobile_no).strip()
    mobile_no = "".join(ch for ch in mobile_str if ch.isdigit())

    # Common local-format prefix
    if len(mobile_no) == 11 and mobile_no.startswith("0"):
        mobile_no = mobile_no[1:]

    if len(mobile_no) == 10:
        mobile_no = "91" + mobile_no

    return mobile_no


def mask_mobile(mobile_no):
    """Mask mobile for display: 91******1234"""
    if len(mobile_no) > 6:
        return mobile_no[:2] + "*" * (len(mobile_no) - 6) + mobile_no[-4:]
    return mobile_no


def authenticate_with_retry(email, password, max_retries=3):
    """Retry authentication with exponential backoff for lock timeout errors"""
    start_time = frappe.utils.now_datetime()

    for attempt in range(max_retries):
        try:
            attempt_time = frappe.utils.now_datetime()

            frappe.log_error(
                f"Login Attempt #{attempt + 1}/{max_retries}\n"
                f"Email: {email}\n"
                f"Attempt Time: {attempt_time}\n"
                f"Started At: {start_time}",
                "Login Attempt"
            )

            login_manager = frappe.auth.LoginManager()
            login_manager.authenticate(user=email, pwd=password)
            login_manager.post_login()

            success_time = frappe.utils.now_datetime()
            time_taken = (success_time - start_time).total_seconds()

            frappe.log_error(
                f"Login Successful\n"
                f"Email: {email}\n"
                f"Attempt: {attempt + 1}/{max_retries}\n"
                f"Success Time: {success_time}\n"
                f"Total Time Taken: {time_taken:.2f} seconds\n"
                f"Retries: {attempt}",
                "Login Success"
            )

            return email

        except Exception as e:
            error_msg = str(e)
            error_time = frappe.utils.now_datetime()

            if "Lock wait timeout" in error_msg and attempt < max_retries - 1:
                wait_time = (2 ** attempt) * 0.5

                frappe.log_error(
                    f"Lock Timeout - Retrying\n"
                    f"Email: {email}\n"
                    f"Attempt: {attempt + 1}/{max_retries}\n"
                    f"Error Time: {error_time}\n"
                    f"Wait Time: {wait_time}s\n"
                    f"Next Retry: Attempt #{attempt + 2}\n"
                    f"Error: {error_msg}",
                    "Login Retry"
                )

                time.sleep(wait_time)
                frappe.db.rollback()
            else:
                time_taken = (error_time - start_time).total_seconds()

                frappe.log_error(
                    f"Login Failed\n"
                    f"Email: {email}\n"
                    f"Attempt: {attempt + 1}/{max_retries}\n"
                    f"Failure Time: {error_time}\n"
                    f"Total Time Taken: {time_taken:.2f} seconds\n"
                    f"Total Retries: {attempt}\n"
                    f"Error Type: {'Lock Timeout' if 'Lock wait timeout' in error_msg else 'Authentication Error'}\n"
                    f"Error: {error_msg}",
                    "Login Failed"
                )

                raise


@frappe.whitelist(allow_guest=True)
def send_whatsapp_otp(mobile_no, store_id=None):
    """Send OTP via WhatsApp"""
    if not mobile_no:
        frappe.throw("Mobile number is required")

    if not store_id:
        frappe.throw("Store ID is required")

    mobile_no = normalize_mobile(mobile_no)
    if not mobile_no:
        frappe.throw("Mobile number is required")

    # Rate limiting
    rate_key = f"otp_rate_{mobile_no}"
    rate_data = frappe.cache().get_value(rate_key) or {"count": 0}
    if rate_data["count"] >= 3:
        frappe.throw("Too many OTP requests. Please try again in 10 minutes.")

    # Generate OTP
    otp = str(random.randint(100000, 999999))

    # Send via WhatsApp
    config = frappe.get_conf()
    phone_number_id = config.get("whatsapp_phone_number_id")
    access_token = config.get("whatsapp_access_token")

    if phone_number_id and access_token:
        try:
            response = requests.post(
                f"https://graph.facebook.com/v22.0/{phone_number_id}/messages",
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": "application/json"
                },
                json={
                    "messaging_product": "whatsapp",
                    "to": mobile_no,
                    "type": "template",
                    "template": {
                        "name": "hello_world",
                        "language": {"code": "en_US"}
                    }
                },
                timeout=30
            )

            if response.status_code != 200:
                frappe.log_error(f"WhatsApp API Error: {response.text}", "WhatsApp OTP Failed")
                frappe.throw("Failed to send OTP. Please try again.")

        except requests.exceptions.RequestException as e:
            frappe.log_error(f"WhatsApp Request Failed: {str(e)}", "WhatsApp OTP Error")
            frappe.throw("Failed to send OTP. Please try again.")
    else:
        # Dev mode - no WhatsApp configured
        otp = "123456"

    # Store OTP
    frappe.cache().set_value(f"whatsapp_otp_{mobile_no}", {
        "otp": otp,
        "store_id": store_id,
        "attempts": 0
    }, expires_in_sec=300)

    # Update rate limit
    rate_data["count"] += 1
    frappe.cache().set_value(rate_key, rate_data, expires_in_sec=600)

    return {
        "status": "success",
        "message": "OTP sent",
        "mobile_no": mask_mobile(mobile_no)
    }


@frappe.whitelist(allow_guest=True)
def verify_whatsapp_otp(mobile_no, otp, store_id=None, user_data=None, device_id=None, device_label=None):
    """Verify OTP and return OAuth tokens - returns registration_token if user not found.

    If device_id is provided, also issues a long-lived device_credential
    that the client can later trade for fresh OAuth tokens via
    device_credential_auth.exchange_device_credential. This is the
    safety net for clients that lose their refresh_token to OEM data
    cleaners (vivo iManager, MIUI, etc.).
    """
    if isinstance(user_data, str):
        user_data = json.loads(user_data)

    if not mobile_no or not otp:
        frappe.throw("Mobile number and OTP are required")

    otp = "".join(ch for ch in str(otp).strip() if ch.isdigit())
    if not otp:
        frappe.throw("Mobile number and OTP are required")

    if not store_id:
        frappe.throw("Store ID is required")

    mobile_no = normalize_mobile(mobile_no)
    if not mobile_no:
        frappe.throw("Mobile number is required")
    cache_key = f"whatsapp_otp_{mobile_no}"

    otp_data = frappe.cache().get_value(cache_key)

    if not otp_data:
        frappe.throw("OTP expired. Please request a new one.")

    if otp_data.get("attempts", 0) >= 3:
        frappe.cache().delete_value(cache_key)
        frappe.throw("Too many failed attempts. Please request a new OTP.")

    if otp_data.get("otp") != otp:
        otp_data["attempts"] = otp_data.get("attempts", 0) + 1
        frappe.cache().set_value(cache_key, otp_data, expires_in_sec=300)
        frappe.throw(f"Invalid OTP. {3 - otp_data['attempts']} attempts remaining.")

    if otp_data.get("store_id") != store_id:
        frappe.throw("Store ID mismatch")

    frappe.cache().delete_value(cache_key)

    # ============================================
    # Look up existing user by mobile
    # ============================================
    user_email = frappe.db.get_value("User", {"mobile_no": mobile_no}, "name")

    if not user_email:
        # Try without country code
        user_email = frappe.db.get_value("User", {"mobile_no": mobile_no[2:]}, "name")

    if not user_email:
        # ============================================
        # ACCOUNT NOT FOUND - return registration token
        # instead of throwing, so the app can redirect
        # to the registration screen.
        # ============================================
        reg_token = random_string(20)
        frappe.cache().set_value(f"reg_token_{mobile_no}", {
            "token": reg_token,
            "store_id": store_id,
            "verified": True
        }, expires_in_sec=600)  # 10 minutes to complete registration

        return {
            "status": "not_found",
            "message": "Account not found. Please register.",
            "mobile_no": mask_mobile(mobile_no),
            "registration_token": reg_token
        }

    user = frappe.get_doc("User", user_email)

    if not user.enabled:
        frappe.throw("Your account is disabled. Please contact admin.")

    # Look up linked Driver record
    driver_name = frappe.db.get_value("Driver", {"cell_number": mobile_no}, "name")
    if not driver_name:
        driver_name = frappe.db.get_value("Driver", {"cell_number": mobile_no[2:]}, "name")

    profile_completed = 1 if driver_name else 0
    kyc_completed = 0

    if driver_name:
        driver_doc = frappe.get_doc("Driver", driver_name)
        kyc_completed = 1 if (driver_doc.custom_aadhar_no and driver_doc.custom_aadhar_attachment) else 0

    # Login
    login_manager = frappe.auth.LoginManager()
    login_manager.login_as(user.name)
    login_manager.post_login()

    # Get OAuth client
    cache_key = f"oauth_client_{store_id}"
    client_data = frappe.cache().get_value(cache_key)

    if not client_data:
        try:
            client_doc = frappe.get_doc("OAuth Client", {"app_name": f"Billing Partner - {store_id}"})
            client_data = {
                "client_id": client_doc.client_id,
                "client_secret": client_doc.get_password("client_secret"),
                "redirect_uri": client_doc.redirect_uris.split(",")[0].strip()
            }
            frappe.cache().set_value(cache_key, client_data, expires_in_sec=3600)
        except frappe.DoesNotExistError:
            frappe.throw(f"No OAuth Client configured for store {store_id}")

    # Generate tokens
    token_response = generate_oauth_tokens_autoapprove(user, client_data)

    # Issue a device credential for OEM-cleaner recovery if the client
    # supplied a device_id. Empty string is returned for malformed IDs;
    # we pass that through unchanged so legacy clients keep working.
    device_credential = ""
    if device_id:
        try:
            from .device_credential_auth import issue_device_credential
            device_credential = issue_device_credential(
                user_email=user.name,
                device_id=device_id,
                device_label=device_label,
            )
        except Exception as e:
            frappe.log_error(
                title="issue_device_credential failed",
                message=f"user={user.name} device_id={device_id} err={e}",
            )

    return {
        "status": "success",
        "message": "Login successful",
        "email": user.name,
        "mobile_no": mobile_no,
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
        "kyc_completed": kyc_completed
    }


@frappe.whitelist(allow_guest=True)
def register_delivery_partner(mobile_no, registration_token, full_name, store_id, email=None, device_id=None, device_label=None):
    """Register a new delivery partner after OTP verification.

    Called when verify_whatsapp_otp returns status='not_found'.
    The registration_token proves the mobile was already OTP-verified.

    If device_id is provided, also issues a device_credential — same
    OEM-cleaner safety net as verify_whatsapp_otp.
    """
    if not mobile_no or not registration_token or not full_name or not store_id:
        frappe.throw("All required fields must be provided")

    mobile_no = normalize_mobile(mobile_no)
    if not mobile_no:
        frappe.throw("Invalid mobile number")

    # ---- Validate registration token ----
    cache_key = f"reg_token_{mobile_no}"
    reg_data = frappe.cache().get_value(cache_key)

    if not reg_data:
        frappe.throw("Registration session expired. Please verify OTP again.")

    if reg_data.get("token") != registration_token:
        frappe.throw("Invalid registration token")

    if reg_data.get("store_id") != store_id:
        frappe.throw("Store ID mismatch")

    # Clear the registration token (one-time use)
    frappe.cache().delete_value(cache_key)

    # ---- Check if user already exists ----
    existing = frappe.db.get_value("User", {"mobile_no": mobile_no}, "name")
    if not existing:
        existing = frappe.db.get_value("User", {"mobile_no": mobile_no[2:]}, "name")
    if existing:
        frappe.throw("Account already exists. Please login instead.")

    # ---- Determine email ----
    user_email = email.strip() if email and email.strip() else f"{mobile_no}@delivery.grozfy.com"

    # Check email uniqueness
    if frappe.db.exists("User", user_email):
        frappe.throw("An account with this email already exists.")

    # ---- Split name ----
    name_parts = full_name.strip().split(" ", 1)
    first_name = name_parts[0]
    last_name = name_parts[1] if len(name_parts) > 1 else ""

    # ---- Create Frappe User ----
    try:
        user = frappe.get_doc({
            "doctype": "User",
            "email": user_email,
            "first_name": first_name,
            "last_name": last_name,
            "mobile_no": mobile_no,
            "send_welcome_email": 0,
            "new_password": frappe.generate_hash(length=12),
            "user_type": "System User",
            "enabled": 1,
            "roles": [
                {"role": "Delivery Partner"}
            ]
        })
        user.insert(ignore_permissions=True)
        frappe.db.commit()
    except Exception as e:
        frappe.log_error(
            f"Error creating delivery partner {mobile_no}: {str(e)}",
            "Registration Error"
        )
        frappe.db.rollback()
        frappe.throw(f"Registration failed: {str(e)}")

    # Driver record is created later during KYC submission
    # (Aadhar fields are mandatory on Driver DocType)

    # ---- Login the new user ----
    login_manager = frappe.auth.LoginManager()
    login_manager.login_as(user.name)
    login_manager.post_login()

    # ---- Get OAuth client ----
    oauth_cache_key = f"oauth_client_{store_id}"
    client_data = frappe.cache().get_value(oauth_cache_key)

    if not client_data:
        try:
            client_doc = frappe.get_doc(
                "OAuth Client",
                {"app_name": f"Billing Partner - {store_id}"}
            )
            client_data = {
                "client_id": client_doc.client_id,
                "client_secret": client_doc.get_password("client_secret"),
                "redirect_uri": client_doc.redirect_uris.split(",")[0].strip()
            }
            frappe.cache().set_value(oauth_cache_key, client_data, expires_in_sec=3600)
        except frappe.DoesNotExistError:
            frappe.throw(f"No OAuth Client configured for store {store_id}")

    # ---- Generate OAuth tokens ----
    token_response = generate_oauth_tokens_autoapprove(user, client_data)

    # Issue a device credential for OEM-cleaner recovery (same as
    # verify_whatsapp_otp). Empty string for malformed device_id is
    # passed through unchanged so legacy clients keep working.
    device_credential = ""
    if device_id:
        try:
            from .device_credential_auth import issue_device_credential
            device_credential = issue_device_credential(
                user_email=user.name,
                device_id=device_id,
                device_label=device_label,
            )
        except Exception as e:
            frappe.log_error(
                title="issue_device_credential failed (register)",
                message=f"user={user.name} device_id={device_id} err={e}",
            )

    return {
        "status": "success",
        "message": "Registration successful",
        "email": user.name,
        "mobile_no": mobile_no,
        "full_name": full_name.strip(),
        "access_token": token_response["access_token"],
        "token_type": "Bearer",
        "expires_in": token_response.get("expires_in", 3600),
        "refresh_token": token_response.get("refresh_token", ""),
        "client_id": client_data["client_id"],
        "device_credential": device_credential,
        "new_user": 1,
        "driver_name": ""
    }


@frappe.whitelist()
def submit_driver_kyc(
    aadhar_no,
    aadhar_attachment,
    driver_name=None,
    license_number=None,
    license_attachment=None,
    issuing_date=None,
    expiry_date=None,
    pan_no=None,
    pan_attachment=None,
):
    """Create or update Driver record with KYC details.

    If driver_name is provided, updates the existing record.
    Otherwise, looks up by the logged-in user's mobile or creates a new Driver.
    Aadhar fields are mandatory on the Driver DocType.
    """
    if not aadhar_no or not aadhar_attachment:
        frappe.throw("Aadhar number and attachment are required")

    user = frappe.get_doc("User", frappe.session.user)
    mobile_no = normalize_mobile(user.mobile_no)

    # ---- Find or create Driver ----
    is_new = False
    if driver_name and frappe.db.exists("Driver", driver_name):
        driver = frappe.get_doc("Driver", driver_name)
    else:
        # Look up by mobile
        existing = frappe.db.get_value("Driver", {"cell_number": mobile_no}, "name")
        if not existing:
            existing = frappe.db.get_value("Driver", {"cell_number": mobile_no[2:]}, "name")

        if existing:
            driver = frappe.get_doc("Driver", existing)
        else:
            # Create new Driver
            full_name = f"{user.first_name or ''} {user.last_name or ''}".strip() or user.name
            driver = frappe.get_doc({
                "doctype": "Driver",
                "full_name": full_name,
                "cell_number": mobile_no,
                "status": "Active",
            })
            is_new = True

    # ---- Set KYC fields ----
    driver.custom_aadhar_no = aadhar_no
    driver.custom_aadhar_attachment = aadhar_attachment

    if license_number is not None:
        driver.license_number = license_number
    if license_attachment is not None:
        driver.custom_license_attachment = license_attachment
    if issuing_date is not None:
        driver.issuing_date = issuing_date
    if expiry_date is not None:
        driver.expiry_date = expiry_date
    if pan_no is not None:
        driver.custom_pan_no = pan_no
    if pan_attachment is not None:
        driver.custom_pan_attachment = pan_attachment

    try:
        if is_new:
            driver.insert(ignore_permissions=True)
        else:
            driver.save(ignore_permissions=True)
        frappe.db.commit()
    except Exception as e:
        frappe.log_error(
            f"Error {'creating' if is_new else 'updating'} Driver KYC: {str(e)}",
            "Driver KYC Error"
        )
        frappe.db.rollback()
        frappe.throw(f"Failed to submit KYC: {str(e)}")

    return {
        "status": "success",
        "message": "KYC submitted successfully",
        "driver_name": driver.name,
        "kyc_completed": 1
    }


@frappe.whitelist()
def upload_kyc_file(driver_name=None, fieldname=None):
    """Upload a KYC file, optionally attached to a Driver record.

    If driver_name is provided and exists, attaches the file to that Driver.
    Otherwise uploads as a private file (to be linked when Driver is created).
    Returns the Frappe file_url to be passed to submit_driver_kyc.
    """
    from frappe.utils.file_manager import save_file

    files = frappe.request.files
    if "file" not in files:
        frappe.throw("No file uploaded")

    uploaded = files["file"]
    content = uploaded.stream.read()
    filename = uploaded.filename

    # Attach to Driver if it exists, otherwise just store as private file
    dt = None
    dn = None
    df = None
    if driver_name and frappe.db.exists("Driver", driver_name):
        dt = "Driver"
        dn = driver_name
        df = fieldname

    try:
        ret = save_file(
            fname=filename,
            content=content,
            dt=dt,
            dn=dn,
            df=df,
            is_private=1,
        )
        frappe.db.commit()
    except Exception as e:
        frappe.log_error(
            f"File upload failed for Driver {driver_name}: {str(e)}",
            "KYC File Upload Error",
        )
        frappe.throw(f"File upload failed: {str(e)}")

    return {
        "status": "success",
        "file_url": ret.file_url,
        "file_name": ret.file_name,
    }


# =====================
# Google / Email Login
# =====================

@frappe.whitelist(allow_guest=True)
def verify_google_login_for_billing_partner(id_token_str=None, email=None, password=None, user_data=None, store_id=None):
    if isinstance(user_data, str):
        user_data = json.loads(user_data)

    if not store_id:
        frappe.throw("Store ID is required")

    # -----------------------
    # Authenticate user (Google or Email/Password)
    # -----------------------
    user_email = None
    is_google_login = False
    google_data = None

    if id_token_str:
        try:
            google_data = google_id_token.verify_oauth2_token(id_token_str, grequests.Request())
            user_email = google_data.get("email")
            if not user_email:
                frappe.throw("Email not found in Google token")
            is_google_login = True
        except Exception as e:
            frappe.log_error(f"Google token verification failed: {str(e)}", "Google Auth Error")
            frappe.throw(f"Invalid Google ID token: {str(e)}")
    elif email and password:
        try:
            user_email = authenticate_with_retry(email, password)
        except frappe.AuthenticationError as e:
            frappe.log_error(f"Email/Password authentication failed for {email}: {str(e)}", "Login Auth Error")
            frappe.throw(f"Invalid email or password: {str(e)}")
        except Exception as e:
            frappe.log_error(f"Unexpected error during email/password login: {str(e)}", "Login Error")
            frappe.throw(f"Login failed: {str(e)}")
    else:
        frappe.throw("Either Google ID token or email/password is required")

    # -----------------------
    # Check or create ERPNext user
    # -----------------------
    user_exists = frappe.db.exists("User", user_email)
    is_new_user = 0
    user = None

    if user_exists:
        try:
            user = frappe.get_doc("User", user_email)
        except Exception as e:
            frappe.log_error(f"Error loading user {user_email}: {str(e)}", "User Load Error")
            frappe.throw(f"Failed to load user data: {str(e)}")
    else:
        is_new_user = 1
        try:
            if is_google_login:
                if not google_data:
                    frappe.throw("Google data not available for user creation")

                user = frappe.get_doc({
                    "doctype": "User",
                    "email": user_email,
                    "first_name": google_data.get("given_name", ""),
                    "last_name": google_data.get("family_name", ""),
                    "send_welcome_email": 0,
                    "new_password": frappe.generate_hash(length=10),
                    "user_type": "System User",
                    "user_image": google_data.get("picture", ""),
                    "enabled": 1,
                    "roles": [
                        {"role": "Sales User"},
                        {"role": "Accounts User"},
                        {"role": "System Manager"}
                    ]
                })
            else:
                if not password:
                    frappe.throw("Password is required for user creation")

                user = frappe.get_doc({
                    "doctype": "User",
                    "email": user_email,
                    "first_name": email.split("@")[0],
                    "send_welcome_email": 0,
                    "new_password": password,
                    "user_type": "System User",
                    "enabled": 1,
                    "roles": [
                        {"role": "Sales User"},
                        {"role": "Accounts User"},
                        {"role": "System Manager"}
                    ]
                })

            user.insert(ignore_permissions=True)
            frappe.db.commit()

        except Exception as e:
            frappe.log_error(f"Error creating user {user_email}: {str(e)}", "User Creation Error")
            frappe.db.rollback()
            frappe.throw(f"Failed to create user: {str(e)}")

    if not user or not user.name:
        frappe.log_error(f"User object invalid for {user_email}", "User Load Error")
        frappe.throw("Failed to load user data")

    # -----------------------
    # Login the user (Google login only)
    # -----------------------
    if is_google_login:
        try:
            login_manager = frappe.auth.LoginManager()
            login_manager.login_as(user_email)
            login_manager.post_login()
        except Exception as e:
            frappe.log_error(f"Error during Google login_as for {user_email}: {str(e)}", "Google Login Error")
            frappe.throw(f"Failed to complete Google login: {str(e)}")

    # -----------------------
    # Fetch OAuth client per store (cached)
    # -----------------------
    cache_key = f"oauth_client_{store_id}"
    client_data = frappe.cache().get_value(cache_key)

    if not client_data:
        try:
            client_doc = frappe.get_doc("OAuth Client", {"app_name": f"Billing Partner - {store_id}"})

            if not client_doc.client_id or not client_doc.client_secret:
                frappe.throw(f"OAuth Client for store {store_id} is missing credentials")

            redirect_uris = client_doc.redirect_uris
            if not redirect_uris:
                frappe.throw(f"OAuth Client for store {store_id} is missing redirect URIs")

            client_data = {
                "client_id": client_doc.client_id,
                "client_secret": client_doc.get_password("client_secret"),
                "redirect_uri": redirect_uris.split(",")[0].strip()
            }

            frappe.cache().set_value(cache_key, client_data, expires_in_sec=3600)

        except frappe.DoesNotExistError:
            frappe.log_error(f"OAuth Client not found for store {store_id}", "OAuth Client Missing")
            frappe.throw(f"No OAuth Client configured for store {store_id}")
        except Exception as e:
            frappe.log_error(f"Error fetching OAuth Client for store {store_id}: {str(e)}", "OAuth Client Error")
            frappe.throw(f"Failed to load OAuth Client: {str(e)}")

    # -----------------------
    # Generate OAuth tokens
    # -----------------------
    try:
        token_response = generate_oauth_tokens_autoapprove(user, client_data)

        if not token_response or not isinstance(token_response, dict):
            frappe.throw("Invalid token response format")

        if "access_token" not in token_response:
            frappe.log_error(f"Token response missing access_token: {token_response}", "OAuth Token Error")
            frappe.throw("Failed to generate OAuth tokens. Check OAuth Client configuration.")

    except Exception as e:
        frappe.log_error(f"Error generating OAuth tokens for {user_email}: {str(e)}", "OAuth Token Generation Error")
        frappe.throw(f"Failed to generate authentication tokens: {str(e)}")

    # -----------------------
    # Return response
    # -----------------------
    return {
        "status": "success",
        "message": "User verified",
        "email": user_email,
        "full_name": f"{user.first_name or ''} {user.last_name or ''}".strip() or user_email,
        "access_token": token_response["access_token"],
        "token_type": "Bearer",
        "expires_in": token_response.get("expires_in", 3600),
        "refresh_token": token_response.get("refresh_token", ""),
        "id_token": token_response.get("id_token", ""),
        "client_id": client_data["client_id"],
        "new_user": is_new_user
    }


# =====================
# OAuth Token Generation (shared)
# =====================

def generate_oauth_tokens_autoapprove(user, client_data):
    """
    Authorization code flow with auto-approve (no password needed)
    """
    auth_url = f"{get_url()}/api/method/frappe.integrations.oauth2.authorize"
    cookies = {"sid": frappe.session.sid}
    session = requests.Session()

    # Step 1: Request authorization
    auth_data = {
        "response_type": "code",
        "client_id": client_data["client_id"],
        "redirect_uri": client_data["redirect_uri"],
        "scope": "all openid",
        "state": random_string(10),
        "user": user
    }
    auth_response = session.get(auth_url, params=auth_data, cookies=cookies, allow_redirects=False)
    redirect_url = auth_response.headers.get("Location")
    if not redirect_url or auth_response.status_code != 302:
        frappe.log_error(f"Authorize failed: {auth_response.status_code} - {auth_response.text}", "OAuth Authorize Error")
        raise frappe.AuthenticationError("Failed to get authorization code")

    # Step 2: Follow approve redirect (auto-approve)
    approve_response = session.get(f"{get_url()}{redirect_url}", cookies=cookies, allow_redirects=False)
    final_redirect = approve_response.headers.get("Location")
    if not final_redirect or approve_response.status_code != 302:
        frappe.log_error(f"Approve failed: {approve_response.status_code} - {approve_response.text}", "OAuth Approve Error")
        raise frappe.AuthenticationError("Failed to approve authorization code")

    # Step 3: Extract code
    parsed_url = urlparse(final_redirect)
    query_params = parse_qs(parsed_url.query)
    auth_code = query_params.get("code", [None])[0]
    if not auth_code:
        frappe.log_error(f"No code in redirect URL: {final_redirect}", "OAuth Authorize Error")
        raise frappe.AuthenticationError("Failed to get authorization code")

    # Step 4: Exchange code for tokens
    token_url = f"{get_url()}/api/method/frappe.integrations.oauth2.get_token"
    token_data = {
        "grant_type": "authorization_code",
        "client_id": client_data["client_id"],
        "code": auth_code,
        "redirect_uri": client_data["redirect_uri"]
    }
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    resp = requests.post(token_url, data=token_data, headers=headers)
    if resp.status_code != 200:
        frappe.log_error(resp.text, "OAuth Token Error")
        raise frappe.AuthenticationError("Failed to generate OAuth tokens")

    return resp.json()
