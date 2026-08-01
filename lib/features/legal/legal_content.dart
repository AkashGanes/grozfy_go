import 'package:flutter/material.dart';

import '../../core/constants/legal_constants.dart';

/// ---------------------------------------------------------------------------
/// Content model for the Privacy & Legal module.
///
/// The copy lives here rather than inside the screens so the same text can be
/// reused (a section appears both in the collapsed policy list and the detail
/// page), and so a legal reviewer can read the whole document in one file.
///
/// Every disclosure below reflects what the app actually does. If the app
/// starts collecting something new, update this file, the hosted web copy, and
/// the Play Data Safety form together.
/// ---------------------------------------------------------------------------

/// A section of a long-form legal document.
class LegalSection {
  const LegalSection({
    required this.title,
    required this.icon,
    required this.summary,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
    this.closing,
  });

  final String title;
  final IconData icon;

  /// One-line preview shown while the section is collapsed.
  final String summary;
  final List<String> paragraphs;
  final List<String> bullets;

  /// Emphasised line closing the section.
  final String? closing;
}

/// A category of collected data, rendered as a card of chips.
class DataGroup {
  const DataGroup({
    required this.title,
    required this.icon,
    required this.purpose,
    required this.items,
    this.note,
  });

  final String title;
  final IconData icon;

  /// Why we hold this category — shown under the title.
  final String purpose;
  final List<String> items;

  /// Optional reassurance or limitation.
  final String? note;
}

/// A runtime permission the app requests.
class PermissionInfo {
  const PermissionInfo({
    required this.title,
    required this.icon,
    required this.why,
    required this.scope,
    required this.required_,
  });

  final String title;
  final IconData icon;

  /// What the app does with it.
  final String why;

  /// When it applies / when it stops.
  final String scope;

  /// Whether deliveries are possible without it.
  final bool required_;
}

/// A support channel.
class ContactChannel {
  const ContactChannel({
    required this.title,
    required this.icon,
    required this.value,
    required this.subtitle,
    this.uri,
    this.multiline = false,
  });

  final String title;
  final IconData icon;
  final String value;
  final String subtitle;

  /// Launched on tap — `mailto:` or `tel:`. Null for non-actionable cards.
  final String? uri;
  final bool multiline;
}

// ===========================================================================
// PRIVACY POLICY
// ===========================================================================

const List<LegalSection> kPrivacySections = <LegalSection>[
  LegalSection(
    title: 'Introduction',
    icon: Icons.article_outlined,
    summary: 'Who we are and what this policy covers',
    paragraphs: [
      'This policy explains what information the Grozfy Delivery Partner app '
          'collects from you, why we collect it, who we share it with, and the '
          'control you have over it.',
      'It applies only to delivery partners. Customers using the Grozfy '
          'shopping app are covered by a separate policy — you give us '
          'information, such as verification documents and live location, that '
          'customers never do, so the two documents are deliberately different.',
      'By using the app you accept the practices described here. If you do not '
          'agree with them, please do not continue as a delivery partner.',
    ],
  ),
  LegalSection(
    title: 'Information We Collect',
    icon: Icons.inventory_2_outlined,
    summary: 'Six categories, listed in full',
    paragraphs: [
      'We collect only what is needed to onboard you, assign you deliveries and '
          'pay you. The categories are:',
    ],
    bullets: [
      'Personal information — your name, mobile number, email, address and '
          'profile photo.',
      'Identity verification — the documents you upload to prove eligibility.',
      'Vehicle information — registration number and vehicle type.',
      'Location information — GPS position while you are on a delivery.',
      'Device information — model, OS and app version, IP address, crash logs.',
      'Financial information — bank or UPI details needed to pay you.',
    ],
    closing: 'Tap "View collected data" for the exact fields in each category.',
  ),
  LegalSection(
    title: 'Location Information',
    icon: Icons.my_location_rounded,
    summary: 'Collected during active deliveries, background included',
    paragraphs: [
      'Location is the most significant information we collect, so it is worth '
          'reading in full.',
      'We collect your precise GPS position, and collection continues while the '
          'app is in the background or closed. Android requires a visible '
          'notification while this happens, so you can always tell when '
          'tracking is running.',
    ],
    bullets: [
      'Collection starts when you accept a delivery and stops once you have no '
          'active deliveries. It does not run continuously merely because the '
          'app is installed.',
      'We use it to let customers follow their order, to offer you orders '
          'within your chosen delivery radius, and to confirm pickups and drops.',
      'We use it to calculate the distance that determines your payout.',
    ],
    closing:
        'You can revoke location access at any time in your device settings. '
        'Without it you cannot be assigned deliveries.',
  ),
  LegalSection(
    title: 'Device Information',
    icon: Icons.smartphone_rounded,
    summary: 'Diagnostics and push delivery',
    paragraphs: [
      'We record your device model, Android version, app version and IP '
          'address, together with crash and performance diagnostics. This tells '
          'us which devices the app misbehaves on and helps us fix it.',
      'We also store a push notification token so we can alert you to new '
          'orders. It identifies your app installation, not you personally.',
    ],
  ),
  LegalSection(
    title: 'Identity Verification',
    icon: Icons.badge_outlined,
    summary: 'KYC documents and how they are handled',
    paragraphs: [
      'Before you can accept deliveries we must confirm who you are and that '
          'you are entitled to work. We collect the identity, address and '
          'licence documents you upload during onboarding.',
      'These documents are used for verification, fraud prevention and to meet '
          'our legal obligations. They are visible only to the staff who '
          'process verification.',
    ],
    closing:
        'If you enable biometric unlock, that check happens entirely on your '
        'device. We never receive your fingerprint or face data.',
  ),
  LegalSection(
    title: 'Vehicle Information',
    icon: Icons.two_wheeler_rounded,
    summary: 'Registration, type and insurance',
    paragraphs: [
      'We record your vehicle registration number, vehicle type, fuel type and '
          'insurance policy number. This confirms the vehicle is roadworthy and '
          'insured, and lets us match you to orders your vehicle can carry.',
      'Merchants and customers see only your vehicle type — never your '
          'registration number.',
    ],
  ),
  LegalSection(
    title: 'Financial Information',
    icon: Icons.account_balance_outlined,
    summary: 'Bank and UPI details, used only to pay you',
    paragraphs: [
      'We collect the bank account number, IFSC code and account holder name, '
          'or the UPI ID, that we pay your earnings into, along with a record '
          'of payouts, incentives and cash-on-delivery settlements.',
      'When you type an IFSC code we look it up through a public IFSC directory '
          'to show you the branch name. Only the IFSC code is sent — never your '
          'account number.',
    ],
    closing: 'We never sell your financial information and never use it for '
        'anything other than paying you.',
  ),
  LegalSection(
    title: 'How We Use Your Information',
    icon: Icons.tune_rounded,
    summary: 'Onboarding, assignment, payment, safety',
    bullets: [
      'Verifying your eligibility to work as a delivery partner.',
      'Offering and assigning orders near you, within your delivery radius.',
      'Letting customers and merchants track an order in progress.',
      'Calculating distance, earnings, incentives and settlements.',
      'Investigating disputes, losses, accidents and suspected fraud.',
      'Sending you operational alerts — new orders, payouts, policy changes.',
      'Improving the app through crash and performance diagnostics.',
      'Meeting tax, accounting and other legal obligations.',
    ],
    closing:
        'We do not use your information to build advertising profiles, and we '
        'do not sell it.',
  ),
  LegalSection(
    title: 'Information Sharing',
    icon: Icons.share_outlined,
    summary: 'Limited, purpose-bound, never sold',
    paragraphs: [
      'We share the minimum necessary, and only with:',
    ],
    bullets: [
      'Customers — your first name, photo, vehicle type and live location for '
          'the duration of their delivery. Never your phone number, address or '
          'documents.',
      'Merchants — your name and vehicle details for the order being collected.',
      'Payment and banking partners — the details needed to transfer earnings.',
      'Verification providers — where a document must be checked against an '
          'official source.',
      'Infrastructure providers — cloud hosting, push notifications and crash '
          'reporting.',
      'Authorities — where we are legally required to disclose, or to protect '
          'someone\'s safety.',
    ],
    closing:
        'Every provider is contractually bound to use your data only for the '
        'service they perform for us.',
  ),
  LegalSection(
    title: 'Data Security',
    icon: Icons.lock_outline_rounded,
    summary: 'How your information is protected',
    paragraphs: [
      'Your login credentials are held in your device\'s encrypted secure '
          'storage — the Android Keystore or iOS Keychain — not in ordinary app '
          'storage.',
      'Access to verification documents and payout details is restricted to '
          'staff whose role requires it, and that access is logged.',
    ],
    closing:
        'No system is perfectly secure. If we become aware of a breach '
        'affecting you, we will notify you and the Data Protection Board as '
        'the law requires.',
  ),
  LegalSection(
    title: 'Data Retention',
    icon: Icons.schedule_rounded,
    summary: 'How long each category is kept',
    bullets: [
      'Verification documents — while you are an active partner, plus the '
          'period the law requires afterwards.',
      'Location history — retained for the period needed to resolve delivery '
          'and payout disputes, then deleted.',
      'Payout and order records — for the period tax and accounting law '
          'requires, regardless of account deletion.',
      'Profile and contact details — until you delete your account.',
      'Crash diagnostics — a rolling short-term window.',
    ],
  ),
  LegalSection(
    title: 'Your Rights',
    icon: Icons.verified_user_outlined,
    summary: 'Access, correct, delete, withdraw, complain',
    paragraphs: [
      'Under the Digital Personal Data Protection Act, 2023 you may:',
    ],
    bullets: [
      'Access the personal data we hold about you.',
      'Correct anything inaccurate or incomplete.',
      'Delete your account and associated data.',
      'Withdraw consent — including revoking permissions in device settings.',
      'Nominate someone to exercise these rights on your behalf.',
      'Complain to the Data Protection Board of India if we fail to resolve '
          'your grievance.',
    ],
    closing: 'To exercise any of these, contact our Grievance Officer through '
        'the Contact & Support page.',
  ),
  LegalSection(
    title: 'Contact Us',
    icon: Icons.support_agent_rounded,
    summary: 'Reach our privacy team or Grievance Officer',
    paragraphs: [
      'For any question about this policy, or to exercise a right described '
          'above, contact our privacy team. We respond within the period '
          'required by law.',
      '${LegalConstants.privacyEmail}\n${LegalConstants.supportPhone}',
    ],
  ),
];

// ===========================================================================
// INFORMATION WE COLLECT — detail page
// ===========================================================================

const List<DataGroup> kDataGroups = <DataGroup>[
  DataGroup(
    title: 'Personal Information',
    icon: Icons.person_outline_rounded,
    purpose: 'To create your partner account and contact you',
    items: [
      'Full Name',
      'Mobile Number',
      'Email Address',
      'Residential Address',
      'Profile Photo',
    ],
    note: 'Customers see only your first name and profile photo.',
  ),
  DataGroup(
    title: 'Identity Verification',
    icon: Icons.badge_outlined,
    purpose: 'To confirm you are eligible to deliver',
    items: ['Aadhaar', 'PAN', 'Driving Licence'],
    note: 'Visible only to verification staff. Never shared with customers or '
        'merchants.',
  ),
  DataGroup(
    title: 'Vehicle Information',
    icon: Icons.two_wheeler_rounded,
    purpose: 'To match you with orders your vehicle can carry',
    items: [
      'Vehicle Registration Number',
      'Vehicle Type',
      'Fuel Type',
      'Insurance Policy Number',
    ],
    note: 'Only vehicle type is shared with customers.',
  ),
  DataGroup(
    title: 'Location Information',
    icon: Icons.my_location_rounded,
    purpose: 'To assign and track deliveries',
    items: [
      'Live GPS location during an active delivery',
      'Delivery route tracking',
      'Distance calculation',
      'Nearby order assignment',
    ],
    note: 'Collection starts when you accept a delivery and stops when you '
        'have none active — including in the background.',
  ),
  DataGroup(
    title: 'Device Information',
    icon: Icons.smartphone_rounded,
    purpose: 'To keep the app stable and deliver order alerts',
    items: [
      'Device Model',
      'Android Version',
      'App Version',
      'IP Address',
      'Crash Logs',
    ],
    note: 'Diagnostics only. We cannot read your other apps, messages or '
        'contacts.',
  ),
  DataGroup(
    title: 'Financial Information',
    icon: Icons.account_balance_wallet_outlined,
    purpose: 'To pay your earnings and settle cash collections',
    items: [
      'Bank Account Details',
      'UPI Details',
      'Incentive & Payout Information',
    ],
    note: 'Used only to pay you. Never sold or shared for marketing.',
  ),
];

// ===========================================================================
// TERMS & CONDITIONS
// ===========================================================================

const List<LegalSection> kTermsSections = <LegalSection>[
  LegalSection(
    title: 'Acceptance of Terms',
    icon: Icons.handshake_outlined,
    summary: 'What accepting these terms means',
    paragraphs: [
      'By creating a partner account and using the app you enter into an '
          'agreement with Grozfy on these terms. If you do not accept them, do '
          'not use the app.',
      'You are an independent contractor. Nothing in these terms creates an '
          'employment relationship, and you are free to work with other '
          'platforms.',
    ],
  ),
  LegalSection(
    title: 'Eligibility',
    icon: Icons.how_to_reg_outlined,
    summary: 'Who can be a delivery partner',
    bullets: [
      'You must be at least 18 years old.',
      'You must hold a valid driving licence for the vehicle you use.',
      'Your vehicle must be legally registered and insured.',
      'You must have the right to work in India.',
      'The documents you submit must be genuine and belong to you.',
    ],
    closing:
        'Submitting a document that is not yours, or letting someone else use '
        'your account, ends the agreement immediately.',
  ),
  LegalSection(
    title: 'Partner Responsibilities',
    icon: Icons.assignment_turned_in_outlined,
    summary: 'What we expect on every delivery',
    bullets: [
      'Keep your account details, documents and vehicle records current.',
      'Follow all traffic laws. Never use the app while riding.',
      'Handle orders carefully and keep food and goods at a safe temperature.',
      'Treat customers, merchants and support staff with respect.',
      'Never open, consume, substitute or tamper with an order.',
      'Do not sub-contract deliveries or share your login.',
    ],
  ),
  LegalSection(
    title: 'Order Handling',
    icon: Icons.inventory_outlined,
    summary: 'Accepting, delivering and failing an order',
    paragraphs: [
      'You choose which orders to accept. Once you accept one, you are '
          'responsible for collecting it and delivering it to the address shown.',
    ],
    bullets: [
      'Mark each stage in the app accurately and at the time it happens.',
      'Capture proof of delivery where the order requires it.',
      'If a customer is unreachable, follow the in-app process before marking '
          'the order failed.',
      'Report damage, shortfall or an accident through support straight away.',
      'Repeatedly accepting and then cancelling orders may affect the orders '
          'offered to you.',
    ],
  ),
  LegalSection(
    title: 'Payments & Incentives',
    icon: Icons.payments_outlined,
    summary: 'How and when you are paid',
    paragraphs: [
      'Earnings are calculated per completed delivery using the distance, order '
          'type and any incentive in effect when you accepted the order.',
    ],
    bullets: [
      'Payouts are made to the verified bank or UPI account on your profile.',
      'Cash collected on delivery belongs to Grozfy and must be settled '
          'through the app.',
      'Incentive schemes are time-bound; the terms shown when you accept an '
          'order are the terms that apply.',
      'We may withhold a payout while we investigate suspected fraud, and will '
          'tell you when we do.',
      'Deductions for verified loss, damage or shortfall will be itemised.',
    ],
    closing:
        'Raise any earnings dispute within 30 days of the payout it relates to.',
  ),
  LegalSection(
    title: 'Code of Conduct',
    icon: Icons.diversity_3_outlined,
    summary: 'Behaviour that ends the agreement',
    bullets: [
      'Harassment, threats or discrimination of any kind.',
      'Delivering under the influence of alcohol or drugs.',
      'Asking a customer for money outside the app.',
      'Falsifying a delivery, location or proof of delivery.',
      'Misusing customer information, including contacting them after a '
          'delivery.',
      'Any conduct that endangers road users.',
    ],
  ),
  LegalSection(
    title: 'Suspension & Termination',
    icon: Icons.gpp_maybe_outlined,
    summary: 'When access can be paused or ended',
    paragraphs: [
      'We may suspend or end your access if you breach these terms, if your '
          'documents lapse or fail verification, or if we must act to protect '
          'customers, merchants or other partners.',
      'Except where immediate action is necessary, we will tell you the reason '
          'and give you a chance to respond. You may appeal through support.',
    ],
    closing:
        'You may stop working with us at any time. Earnings already due are '
        'still paid. To close your account, contact us through the Contact & '
        'Support page.',
  ),
  LegalSection(
    title: 'Limitation of Liability',
    icon: Icons.balance_outlined,
    summary: 'The limits of our responsibility',
    paragraphs: [
      'The app is provided as-is. We cannot guarantee uninterrupted service, a '
          'particular volume of orders, or a particular level of earnings.',
      'To the extent the law allows, we are not liable for indirect or '
          'consequential loss, or for loss caused by a third party such as a '
          'merchant, customer or payment provider.',
    ],
    closing:
        'Nothing here limits any liability that cannot lawfully be limited.',
  ),
  LegalSection(
    title: 'Policy Updates',
    icon: Icons.update_rounded,
    summary: 'How changes are communicated',
    paragraphs: [
      'We may update these terms as our service or the law changes. The '
          'version and date at the foot of this document always show what is in '
          'force.',
      'For material changes we will give notice in the app before they take '
          'effect. Continuing to accept orders afterwards means you accept the '
          'updated terms.',
    ],
  ),
  LegalSection(
    title: 'Contact Information',
    icon: Icons.contact_support_outlined,
    summary: 'Who to contact about these terms',
    paragraphs: [
      'Questions about these terms, or a dispute you want reviewed, should go '
          'to partner support.',
      '${LegalConstants.supportEmail}\n${LegalConstants.supportPhone}',
      'These terms are governed by the laws of India, and the courts of '
          'Bengaluru, Karnataka have jurisdiction.',
    ],
  ),
];

// ===========================================================================
// DATA & PERMISSIONS
// ===========================================================================

const List<PermissionInfo> kPermissions = <PermissionInfo>[
  PermissionInfo(
    title: 'Location',
    icon: Icons.my_location_rounded,
    why: 'Lets customers follow their delivery, offers you orders inside your '
        'delivery radius, and measures the distance your payout is based on.',
    scope: 'Starts when you accept a delivery, continues in the background, '
        'and stops when you have no active deliveries. A notification is '
        'visible the whole time it is running.',
    required_: true,
  ),
  PermissionInfo(
    title: 'Camera',
    icon: Icons.photo_camera_outlined,
    why: 'Used to photograph your verification documents during onboarding and '
        'to capture proof of delivery.',
    scope: 'Opens only when you tap to take a photo. The app never records in '
        'the background.',
    required_: true,
  ),
  PermissionInfo(
    title: 'Notifications',
    icon: Icons.notifications_active_outlined,
    why: 'Alerts you to new orders, pickup reminders, payout confirmations and '
        'policy changes.',
    scope: 'Without it you will miss order offers, because they are '
        'time-limited.',
    required_: true,
  ),
  PermissionInfo(
    title: 'Photos & Storage',
    icon: Icons.photo_library_outlined,
    why: 'Lets you pick an existing photo for a document upload or your '
        'profile picture, and saves order receipts to your device.',
    scope: 'We read only the images you explicitly select. The app never '
        'browses your gallery on its own.',
    required_: false,
  ),
  PermissionInfo(
    title: 'Phone Number Verification',
    icon: Icons.phone_iphone_rounded,
    why: 'Your mobile number is your login. We send a one-time password to '
        'confirm the number belongs to you.',
    scope: 'Used for sign-in and account recovery only. Calls to customers are '
        'masked, so they never see your personal number.',
    required_: true,
  ),
];

// ===========================================================================
// CONTACT & SUPPORT
// ===========================================================================

const List<ContactChannel> kContactChannels = <ContactChannel>[
  ContactChannel(
    title: 'Privacy Support',
    icon: Icons.privacy_tip_outlined,
    value: LegalConstants.privacyEmail,
    subtitle: 'Data requests, deletion, and our Grievance Officer',
    uri: 'mailto:${LegalConstants.privacyEmail}',
  ),
  ContactChannel(
    title: 'Customer Support',
    icon: Icons.headset_mic_outlined,
    value: LegalConstants.supportEmail,
    subtitle: 'Orders, payouts, account and app problems',
    uri: 'mailto:${LegalConstants.supportEmail}',
  ),
  ContactChannel(
    title: 'Phone',
    icon: Icons.call_outlined,
    value: LegalConstants.supportPhone,
    subtitle: LegalConstants.supportHours,
    uri: 'tel:${LegalConstants.supportPhone}',
  ),
  ContactChannel(
    title: 'Office Address',
    icon: Icons.location_city_rounded,
    value: LegalConstants.officeAddress,
    subtitle: 'Registered office — for written correspondence',
    multiline: true,
  ),
];
