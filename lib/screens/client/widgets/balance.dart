// lib/screens/client/widgets/balance_v2.dart
// Enhanced Balance card styled to match ClientDashboard theme.
// ignore_for_file: deprecated_member_use, unreachable_switch_default, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum DueStatus { onTime, dueSoon, overdue }

class BalanceV2 extends StatelessWidget {
  final double balanceAmount; // numeric value
  final bool isBalanceHidden;
  final VoidCallback onToggleVisibility;

  // Next payment details
  final double nextPaymentAmount;
  final DateTime? nextPaymentDate;

  // Callbacks
  final VoidCallback? onPayNow;
  final VoidCallback? onViewSchedule;

  // Billing cycle (days) used for progress estimation
  final int billingCycleDays;

  const BalanceV2({
    super.key,
    required this.balanceAmount,
    this.isBalanceHidden = true,
    required this.onToggleVisibility,
    required this.nextPaymentAmount,
    this.nextPaymentDate,
    this.onPayNow,
    this.onViewSchedule,
    this.billingCycleDays = 30,
  });

  String _displayAmount(BuildContext context, double value) {
    if (isBalanceHidden) return '•••';
    final nf = NumberFormat.decimalPattern()..maximumFractionDigits = 2;
    return nf.format(value);
  }

  String _currencyLabel(BuildContext context) {
    // Keep currency separate from number to match ClientDashboard style
    return 'ZMW';
  }

  DueStatus _computeStatus(DateTime? dueDate) {
    if (dueDate == null) return DueStatus.onTime;
    final days = dueDate.difference(DateTime.now()).inDays;
    if (days < 0) return DueStatus.overdue;
    if (days <= 3) return DueStatus.dueSoon;
    return DueStatus.onTime;
  }

  Color _statusColor(BuildContext ctx, DueStatus s) {
    switch (s) {
      case DueStatus.overdue:
        return Colors.redAccent;
      case DueStatus.dueSoon:
        return Colors.orange;
      case DueStatus.onTime:
      default:
        return Theme.of(ctx).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    final primary = cs.primary;
    final surface = theme.cardColor;
    final divider = theme.dividerColor;
    final onSurface = cs.onSurface;

    final dueStatus = _computeStatus(nextPaymentDate);

    // days-left text
    final String daysText;
    if (nextPaymentDate == null) {
      daysText = 'No scheduled payment';
    } else {
      final days = nextPaymentDate!.difference(DateTime.now()).inDays;
      if (days < 0) daysText = '${-days} day(s) overdue';
      else if (days == 0) daysText = 'Due today';
      else daysText = '$days day(s) left';
    }

    // compute simple cycle progress: assume cycle ends on nextPaymentDate
    double cycleProgress = 0.0;
    if (nextPaymentDate != null) {
      final now = DateTime.now();
      final cycleStart = nextPaymentDate!.subtract(Duration(days: billingCycleDays));
      final elapsed = now.difference(cycleStart).inDays.clamp(0, billingCycleDays);
      cycleProgress = (elapsed / billingCycleDays).clamp(0.0, 1.0);
    }

    final String balanceDisplay = _displayAmount(context, balanceAmount);
    final String nextPayDisplay = isBalanceHidden ? '•••' : NumberFormat.decimalPattern().format(nextPaymentAmount);
    final String dueDateDisplay = nextPaymentDate == null ? '-' : DateFormat.yMMMd().format(nextPaymentDate!);

    // Button style aligned with ClientDashboard
    final Color buttonBgColor = primary.withOpacity(0.3);
    const Color buttonFgColor = Colors.white;

    return Material(
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.10),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: icon + Manage + Balance + Eye
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manage Account',
                            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: primary)),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Allow the balance text to shrink if necessary
                            Flexible(
                              child: Text(balanceDisplay,
                                  style: textTheme.headlineSmall?.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            Text(_currencyLabel(context),
                                style: textTheme.titleSmall?.copyWith(color: primary, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Eye toggle (circular)
                  GestureDetector(
                    onTap: onToggleVisibility,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(isBalanceHidden ? Icons.visibility_off : Icons.visibility, color: Colors.white),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: divider.withOpacity(0.5)),
              const SizedBox(height: 12),

              // Next payment & CTAs
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: next payment info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Next payment', style: textTheme.bodySmall?.copyWith(color: onSurface.withOpacity(0.7))),
                        const SizedBox(height: 6),
                        Text(nextPayDisplay, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),

                        // Use Wrap here to avoid overflow when the days text is long or when screen is narrow.
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 14, color: textTheme.bodySmall?.color),
                                const SizedBox(width: 6),
                                Text(dueDateDisplay, style: textTheme.bodySmall),
                              ],
                            ),

                            // Constrain the status container so it can wrap nicely on small screens
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.45,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _statusColor(context, dueStatus).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _statusColor(context, dueStatus).withOpacity(0.2)),
                                ),
                                child: Text(
                                  daysText,
                                  style: textTheme.bodySmall?.copyWith(
                                      color: _statusColor(context, dueStatus), fontWeight: FontWeight.w700),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Right: CTAs (buttons styled same as ClientDashboard)
                  // Keep buttons constrained to avoid pushing layout
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 40,
                        width: 120,
                        child: ElevatedButton.icon(
                          onPressed: onPayNow,
                          icon: const Icon(Icons.payments, size: 18),
                          label: const Text('Pay now', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonBgColor,
                            foregroundColor: buttonFgColor,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        width: 120,
                        child: OutlinedButton(
                          onPressed: onViewSchedule,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: primary.withOpacity(0.12)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('View schedule'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Progress bar (billing cycle)
              if (nextPaymentDate != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: cycleProgressOrZero(cycleProgress: cycleProgress),
                    minHeight: 6,
                    backgroundColor: onSurface.withOpacity(0.08),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('${(cycleProgress * 100).round()}%',
                        style: textTheme.bodySmall?.copyWith(color: onSurface.withOpacity(0.7))),
                    const SizedBox(width: 12),
                    Text('Billing cycle progress',
                        style: textTheme.bodySmall?.copyWith(color: onSurface.withOpacity(0.7))),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              Divider(height: 1, color: divider.withOpacity(0.5)),
              const SizedBox(height: 8),

              // Recent transaction row
              Row(
                children: [
                  Icon(Icons.history_outlined, size: 16, color: textTheme.bodySmall?.color),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Recent transaction: ZMW 120.00 • Paid', style: textTheme.bodySmall)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      // navigate to transaction history if needed
                    },
                    child: const Text('See all'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to compute cycle progress safely (0.0 - 1.0)
  double cycleProgressOrZero({required double cycleProgress}) => cycleProgress.isFinite ? cycleProgress : 0.0;
}
