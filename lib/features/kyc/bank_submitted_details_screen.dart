import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/kyc_form_widgets.dart';

class BankSubmittedDetailsScreen extends StatelessWidget {
  const BankSubmittedDetailsScreen({super.key, required this.bankData});

  final Map<String, dynamic> bankData;

  String _val(String key) => (bankData[key] ?? '').toString().trim();
  bool _has(String key) => _val(key).isNotEmpty;

  String _maskedAccountNo(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return digits;
    final visible = digits.substring(digits.length - 4);
    return '${'●' * (digits.length - 4)} $visible';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final holderName = _val('account_name');
    final bankName = _val('bank');
    final accountNo = _val('bank_account_no');
    final accountType = _val('account_type');
    final ifsc = _val('branch_code');
    final branchName = _val('branch_name');

    return Scaffold(
      backgroundColor: KycColors.pageBg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Banner ──────────────────────────────────────────────────────
            _BankBanner(
              isDark: isDark,
              holderName: holderName,
              bankName: bankName,
              maskedAccountNo:
                  accountNo.isNotEmpty ? _maskedAccountNo(accountNo) : '',
              onBack: () => Navigator.of(context).maybePop(),
            ).animate().fadeIn(duration: 350.ms),

            // ── Scrollable body ─────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                children: [
                  // Quick stats strip
                  if (accountType.isNotEmpty ||
                      ifsc.isNotEmpty ||
                      branchName.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _QuickStatsRow(
                      chips: [
                        if (accountType.isNotEmpty)
                          _StatChip(
                            icon: Icons.account_balance_wallet_rounded,
                            label: 'Type',
                            value: accountType,
                            color: AppTheme.oceanBlue,
                          ),
                        if (ifsc.isNotEmpty)
                          _StatChip(
                            icon: Icons.tag_rounded,
                            label: 'IFSC',
                            value: ifsc,
                            color: AppTheme.mint,
                          ),
                        if (branchName.isNotEmpty)
                          _StatChip(
                            icon: Icons.store_rounded,
                            label: 'Branch',
                            value: branchName,
                            color: AppTheme.mango,
                          ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 80.ms)
                        .slideY(
                          begin: 0.1,
                          end: 0,
                          duration: 400.ms,
                          delay: 80.ms,
                        ),
                  ],

                  const SizedBox(height: 16),

                  // ── Bank Details section ───────────────────────────────────
                  _InfoSection(
                    title: 'Bank Details',
                    icon: Icons.account_balance_rounded,
                    color: AppTheme.oceanBlue,
                    tiles: [
                      if (_has('account_name'))
                        _InfoTile(
                          icon: Icons.person_rounded,
                          label: 'Account Holder',
                          value: _val('account_name'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('bank'))
                        _InfoTile(
                          icon: Icons.account_balance_rounded,
                          label: 'Bank',
                          value: _val('bank'),
                          color: AppTheme.oceanBlue,
                          full: true,
                        ),
                      if (_has('account_type') || _has('bank_account_no'))
                        _TileRow(children: [
                          if (_has('account_type'))
                            _InfoTile(
                              icon: Icons.account_balance_wallet_rounded,
                              label: 'Account Type',
                              value: _val('account_type'),
                              color: AppTheme.oceanBlue,
                            ),
                          if (_has('bank_account_no'))
                            _InfoTile(
                              icon: Icons.credit_card_rounded,
                              label: 'Account No.',
                              value: _maskedAccountNo(_val('bank_account_no')),
                              color: AppTheme.oceanBlue,
                            ),
                        ]),
                      if (_has('branch_code') || _has('branch_name'))
                        _TileRow(children: [
                          if (_has('branch_code'))
                            _InfoTile(
                              icon: Icons.tag_rounded,
                              label: 'IFSC Code',
                              value: _val('branch_code'),
                              color: AppTheme.mint,
                            ),
                          if (_has('branch_name'))
                            _InfoTile(
                              icon: Icons.store_rounded,
                              label: 'Branch',
                              value: _val('branch_name'),
                              color: AppTheme.mint,
                            ),
                        ]),
                      if (_has('iban'))
                        _InfoTile(
                          icon: Icons.numbers_rounded,
                          label: 'IBAN',
                          value: _val('iban'),
                          color: AppTheme.mint,
                          full: true,
                        ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 160.ms)
                      .slideY(
                        begin: 0.1,
                        end: 0,
                        duration: 400.ms,
                        delay: 160.ms,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Pinned buttons ─────────────────────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushReplacementNamed(
                    AppRoutes.bankSetup,
                    arguments: <String, dynamic>{'force_edit': true},
                  ),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Edit Bank'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.permission),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Continue'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ).animate()
              .fadeIn(duration: 400.ms, delay: 320.ms)
              .slideY(begin: 0.2, end: 0, duration: 400.ms, delay: 320.ms),
        ),
      ),
    );
  }
}

// ── Banner ────────────────────────────────────────────────────────────────────

class _BankBanner extends StatelessWidget {
  const _BankBanner({
    required this.isDark,
    required this.holderName,
    required this.bankName,
    required this.maskedAccountNo,
    required this.onBack,
  });

  final bool isDark;
  final String holderName;
  final String bankName;
  final String maskedAccountNo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const Color primary = AppTheme.oceanBlue;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primary,
            primary.withValues(alpha: 0.80),
            AppTheme.mint.withValues(alpha: 0.70),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back + verified row
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 5),
                    Text(
                      'Verified',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Bank icon + identity
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (bankName.isNotEmpty)
                      Text(
                        bankName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                    if (holderName.isNotEmpty)
                      Text(
                        holderName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (maskedAccountNo.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          maskedAccountNo,
                          style: const TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick stats row ───────────────────────────────────────────────────────────

class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.chips});
  final List<_StatChip> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(
      children: chips
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Padding(
                padding:
                    EdgeInsets.only(right: e.key < chips.length - 1 ? 8 : 0),
                child: e.value,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? KycColors.cardBg(context) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KycColors.cardBorder(context)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: KycColors.textSecondary(context)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: KycColors.textPrimary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Info section ──────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.tiles,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final nonEmpty =
        tiles.where((w) => w is _InfoTile || w is _TileRow).toList();
    if (nonEmpty.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? KycColors.cardBg(context) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KycColors.cardBorder(context)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: KycColors.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: KycColors.cardBorder(context)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: tiles
                  .asMap()
                  .entries
                  .map(
                    (e) => Padding(
                      padding: EdgeInsets.only(
                          bottom: e.key < tiles.length - 1 ? 8 : 0),
                      child: e.value,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tile row ──────────────────────────────────────────────────────────────────

class _TileRow extends StatelessWidget {
  const _TileRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: children
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: e.key < children.length - 1 ? 8 : 0),
                child: e.value,
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Info tile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.full = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.06)
            : color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.15 : 0.10)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: KycColors.textSecondary(context),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: KycColors.textPrimary(context),
                  ),
                  maxLines: full ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
