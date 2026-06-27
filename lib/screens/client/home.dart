// lib/screens/client/home.dart
// Patched: fetch signed user from AuthService on startup (no "Guest User" fallback).
// ignore_for_file: unnecessary_cast, unused_element, curly_braces_in_flow_control_structures, deprecated_member_use, unused_import

import 'dart:async';

import 'package:daml/screens/client/widgets/balance.dart';
import 'package:daml/screens/client/widgets/client_dashboard.dart';
import 'package:daml/screens/client/widgets/loan_calculator.dart';
import 'package:daml/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'widgets/home_widget.dart';
import 'widgets/profile_screen.dart';
import 'widgets/settings_screen.dart';

// agreement form (client)
import 'widgets/agreement_form.dart';

import '../../services/auth_service.dart';
import '../../services/client_data_notifier.dart';

enum ReportsViewMode { both, daily, monthly }

class ClientHomeScreen extends StatefulWidget {
  // optional branchName so callers that don't pass still work
  final String branchName;
  const ClientHomeScreen({super.key, this.branchName = 'Main Branch'});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  bool _loading = true;

  // local cached fields for display (kept for quick access)
  String _name = 'Guest User';
  String _email = 'you@example.com';
  bool _isBalanceHidden = true;

  @override
  void initState() {
    super.initState();
    // If ClientDataNotifier exists in the provider tree, ensure it loads data now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = _maybeNotifier();
      notifier?.loadClientData();
      _syncLocalProfileFromNotifier();

      // Fetch the signed user (from persisted auth) so we don't show "Guest User".
      _fetchSignedUser();
    });
  }

  ClientDataNotifier? _maybeNotifier() {
    try {
      return Provider.of<ClientDataNotifier>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  // Fetch signed user from AuthService (SharedPreferences) and update local display fields.
  Future<void> _fetchSignedUser() async {
    try {
      final profile = await AuthService.getLocalProfile();
      if (!mounted) return;
      final name = (profile['name'] ?? '') as String;
      final email = (profile['email'] ?? '') as String;
      setState(() {
        if (name.isNotEmpty) _name = name;
        if (email.isNotEmpty) _email = email;
      });
    } catch (_) {
      // ignore errors: keep existing fallback values
    }
  }

  // Sync local name/email state from notifier so header shows immediately.
  void _syncLocalProfileFromNotifier() {
    final notifier = _maybeNotifier();
    if (notifier == null) return;
    final profile = notifier.profile;
    final name = (profile['name'] ?? '') as String;
    final email = (profile['email'] ?? '') as String;
    setState(() {
      _name = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Guest User');
      _email = email.isNotEmpty ? email : 'you@example.com';
      _loading = notifier.isLoading;
    });
  }

  // UI actions
  void _onManageAccount() {}

  void _onTopUp() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientAgreementForm()));
  }

  void _onBorrow() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientAgreementForm()));
  }

  void _openProfile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _toggleBalanceVisibility() {
    setState(() => _isBalanceHidden = !_isBalanceHidden);
  }

  void _onPayNow() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open payment flow (not implemented)')));
  }

  void _onViewSchedule() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open payment schedule (not implemented)')));
  }

  void _openLoanCalculator() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoanCalculatorScreen()));
  }

  // Pull-to-refresh handler that forces ClientDataNotifier to reload (and deliver notifications)
  Future<void> _onRefresh() async {
    final notifier = _maybeNotifier();
    if (notifier != null) {
      await notifier.loadClientData();
      // sync local cached profile for header
      _syncLocalProfileFromNotifier();
    } else {
      // fallback to older behavior if notifier not available
      await _loadProfileBalancesAndNextPaymentLegacy();
    }

    // Also refresh persisted signed user info (in case it changed)
    await _fetchSignedUser();
  }

  // Legacy fallback — keeps your previous behavior if notifier isn't registered.
  Future<void> _loadProfileBalancesAndNextPaymentLegacy() async {
    if (_name == 'Guest User' && mounted) setState(() => _loading = true);

    try {
      final profile = await AuthService.getLocalProfile();

      if (!mounted) return;

      setState(() {
        final name = (profile['name'] ?? '') as String;
        final email = (profile['email'] ?? '') as String;

        _name = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Guest User');
        _email = email.isNotEmpty ? email : 'you@example.com';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to load profile or balances')));
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _formattedActualBalance {
    // Formatter used only when needed locally; ClientDashboardCard will do formatting as well.
    final fmt = NumberFormat.decimalPattern()..maximumFractionDigits = 2;
    return fmt.format(0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the notifier if available — use Consumer so UI updates reactively when notifier notifies.
    final notifierAvailable = Provider.of<ClientDataNotifier?>(context, listen: false) != null;

    if (!_loading && !notifierAvailable) {
      // ok to proceed; notifier missing (legacy path) — UI will still attempt legacy loads
    }

    return Consumer<ClientDataNotifier?>(builder: (context, notifier, _) {
      // If notifier exists, read reactive fields from it; otherwise fallback to AuthService snapshot
      double amountBorrowed = 0.0;
      double actualBalance = 0.0;
      double interestRate = 0.0;
      double? nextPaymentAmount;
      DateTime? nextPaymentDate;
      Map<String, String> profile = {'email': _email, 'name': _name};

      final isLoading = notifier?.isLoading ?? false;

      if (notifier != null) {
        final balances = notifier.balances;
        amountBorrowed = balances['amountBorrowed'] ?? 0.0;
        actualBalance = balances['actualBalance'] ?? 0.0;
        interestRate = balances['interestRate'] ?? 0.0;
        nextPaymentAmount = notifier.nextPaymentAmount;
        nextPaymentDate = notifier.nextPaymentDate;
        profile = notifier.profile;
      }

      // Keep header name/email in sync (now prefers persisted signed user via _fetchSignedUser())
      final displayName = (profile['name']?.isNotEmpty == true)
          ? profile['name']!
          : (_name.isNotEmpty && _name != 'Guest User' ? _name : (profile['email']?.isNotEmpty == true ? profile['email']! : 'Guest User'));
      final displayEmail = profile['email']?.isNotEmpty == true ? profile['email']! : (_email.isNotEmpty && _email != 'you@example.com' ? _email : 'you@example.com');

      // show loading indicator while initial load happening
      if (isLoading && (displayName == 'Guest User' || displayEmail == 'you@example.com')) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      return Scaffold(
        body: Column(
          children: [
            // Client header. HomeWidget subscribes to NotificationService and will show notifications posted
            // by ClientDataNotifier.loadClientData(). We pass callbacks for profile/settings.
            HomeWidget(
              title: 'Welcome, ${displayName.split(' ').first}',
              onSettingsPressed: _openSettings, onProfilePressed: () {  },
            ),

            // Scrollable area with dashboard first then client details below
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: Theme.of(context).colorScheme.primary,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // Use the non-recursive card (ClientDashboardCard) here:
                    ClientDashboardCard(
                      name: displayName,
                      email: displayEmail,
                      amountBorrowed: amountBorrowed,
                      nextDueAmount: nextPaymentAmount ?? 0.0,
                      nextDueDate: nextPaymentDate,
                      amountDue: actualBalance,
                      onManageAccount: _onManageAccount,
                      onTopUp: _onTopUp,
                      onBorrow: _onBorrow,
                      maskAmount: _isBalanceHidden,
                      interestRate: interestRate,
                      currency: '', loanCount: 0, actualBalance: null, isCleared: null,
                    ),

                    const SizedBox(height: 12),

                    BalanceV2(
                      balanceAmount: actualBalance,
                      isBalanceHidden: _isBalanceHidden,
                      onToggleVisibility: _toggleBalanceVisibility,
                      nextPaymentAmount: nextPaymentAmount ?? 0.0,
                      nextPaymentDate: nextPaymentDate,
                      onPayNow: _onPayNow,
                      onViewSchedule: _onViewSchedule,
                      billingCycleDays: 30,
                    ),

                    const SizedBox(height: 24),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),

        floatingActionButton: FloatingActionButton(
          onPressed: _openLoanCalculator,
          tooltip: 'Loan Calculator',
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: const Icon(Icons.calculate),
        ),
      );
    });
  }
}
