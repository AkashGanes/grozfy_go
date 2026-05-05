from frappe.model.document import Document


class DeviceSession(Document):
    """Long-lived device-bound credential used to recover the OAuth
    session when client-side token storage has been wiped (OEM data
    cleaners, encrypted-prefs corruption, etc.). All authentication
    logic lives in delivery_partner.api.device_credential_auth — this
    controller exists only to satisfy Frappe's doctype contract."""

    pass
