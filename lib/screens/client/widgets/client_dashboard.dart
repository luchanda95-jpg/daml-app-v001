// lib/screens/client/client_dashboard_screen.dart
// Complete Client Dashboard with server integration
// Fetches client details and loan balance from Supabase via ApiService.fetchMyClient
//
// Updates you requested:
// ✅ Removed Quick Actions section
// ✅ Removed "Manage" button from the dashboard card
// ✅ Updated Contact Support details:
//    WhatsApp: 0972276257
//    Email: mpangecreativerts@gmail.com
//
// ignore_for_file: unused_element, unnecessary_null_comparison, control_flow_in_finally, deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:daml/widgets/app_skeleton.dart';
import 'package:intl/intl.dart';
import 'package:daml/models/client.dart';
import 'package:daml/models/loan.dart';
import 'package:daml/services/api_service.dart';
import 'package:daml/services/auth_service.dart';
import 'package:daml/theme/app_colors.dart';

// Navigation imports
import 'package:daml/screens/client/widgets/loan_calculator.dart';
import 'package:daml/screens/client/widgets/agreement_form.dart';
import 'package:daml/screens/client/widgets/profile_screen.dart';
import 'package:daml/screens/client/widgets/home_widget.dart';
import 'package:daml/screens/client/widgets/settings_screen.dart';

class ClientDashboardScreen extends StatefulWidget {
  const ClientDashboardScreen({super.key});

  @override
  State<ClientDashboardScreen> createState() => _ClientDashboardScreenState();
}

class _ClientDashboardScreenState extends State<ClientDashboardScreen> with WidgetsBindingObserver {
  // UI State
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  bool _hasNetworkError = false;

  // User Profile
  String _name = '';
  String _email = '';
  String _phone = '';

  // Client Data
  Client? _client;
  bool _clientLoading = true;
  String _clientError = '';

  // Loans Data
  List<Loan> _loans = [];
  Map<String, dynamic> _loansSummary = {};

  // Timer for auto-refresh
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadClientData();
    // Keep live balances fresh while the client dashboard is open.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_refreshing) {
        _loadClientData(forceRefresh: true, showSnackbar: false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_refreshing) {
      _loadClientData(forceRefresh: true, showSnackbar: false);
    }
  }

  // ============================================================
  // Main Data Loading
  // ============================================================
  Future<void> _loadClientData({bool forceRefresh = false, bool showSnackbar = true}) async {
    if (!forceRefresh && _refreshing) return;

    if (showSnackbar && !_loading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing data...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    setState(() {
      if (forceRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = '';
      _clientError = '';
      _hasNetworkError = false;
    });

    try {
      // 1. Load local user profile
      await _loadUserProfile();

      // 2. Fetch client data from server
      await _fetchClientData(includeLoans: true);
    } catch (e) {
      _debugLog('loadClientData', 'Error: $e');
      if (!mounted) return;

      String friendlyError = 'Failed to load dashboard';
      final s = e.toString();

      if (s.contains('SocketException') || s.contains('HttpException') || s.contains('Network is unreachable')) {
        friendlyError = 'Network error. Please check your internet connection.';
        _hasNetworkError = true;
      } else if (s.contains('401') ||
          s.toLowerCase().contains('unauthorized') ||
          s.toLowerCase().contains('authentication')) {
        friendlyError = 'Session expired. Please sign in again.';
        await _handleSessionExpired();
        return;
      } else if (s.toLowerCase().contains('profile incomplete')) {
        friendlyError = s.replaceAll('Exception: ', '');
      } else if (s.contains('TimeoutException')) {
        friendlyError = 'Request timeout. Please try again.';
        _hasNetworkError = true;
      } else if (s.contains('Client not found')) {
        friendlyError = 'Account not found. Please contact support.';
      }

      setState(() => _error = friendlyError);
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await AuthService.getLocalProfile();
      _name = (profile['name'] ?? '').trim();
      _email = (profile['email'] ?? '').trim().toLowerCase();
      _phone = (profile['phone'] ?? '').trim();

      // Validate profile has at least email or phone
      if (_email.isEmpty && _phone.isEmpty) {
        throw Exception('Profile incomplete. Please update your contact information in account settings.');
      }

      // Set auth token
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        ApiService.setAuthToken(token);
      } else {
        throw Exception('Authentication required. Please sign in again.');
      }
    } catch (e) {
      _debugLog('loadUserProfile', 'Error: $e');
      rethrow;
    }
  }

  // ============================================================
  // Fetch Client Data from Server
  // ============================================================
  Future<void> _fetchClientData({bool includeLoans = false}) async {
    setState(() {
      _clientLoading = true;
      _clientError = '';
    });

    try {
      // Call the unified dashboard loader. When Supabase is configured,
      // ApiService.fetchMyClient reads directly from Supabase instead of the old Node /clients/me route.
      final response = await ApiService.fetchMyClient(includeLoans: includeLoans);

      if (response['success'] == true) {
        // Parse client data
        if (response['client'] != null) {
          final clientData = Map<String, dynamic>.from(response['client']);
          _client = Client.fromJson(clientData);

          // Update profile info from client data if available
          if (_client!.fullName.isNotEmpty) _name = _client!.fullName;
          if (_client!.email != null && _client!.email!.isNotEmpty) _email = _client!.email!;
          if (_client!.phone != null && _client!.phone!.isNotEmpty) _phone = _client!.phone!;
        }

        // Parse loans summary
        if (response['loansSummary'] != null) {
          _loansSummary = Map<String, dynamic>.from(response['loansSummary']);
        }

        // Parse loans list if included
        if (includeLoans && response['loans'] != null) {
          final loansData = response['loans'] as List;
          _loans = loansData.map((loan) => Loan.fromJson(Map<String, dynamic>.from(loan))).toList();
        }

        setState(() {});
      } else {
        // ignore: unnecessary_type_check
        final errorMsg = (response is Map) ? (response['message'] ?? 'Failed to fetch client data') : 'Failed to fetch client data';
        throw Exception(errorMsg);
      }
    } catch (e) {
      _debugLog('fetchClientData', 'Error: $e');

      final s = e.toString();
      if (s.contains('401') || s.toLowerCase().contains('unauthorized') || s.toLowerCase().contains('authentication')) {
        await _handleSessionExpired();
        return;
      }

      _clientError = s.replaceAll('Exception: ', '');
      setState(() {
        _client = null;
        _loansSummary = {};
        _loans = [];
      });
    } finally {
      if (!mounted) return;
      setState(() => _clientLoading = false);
    }
  }

  // ============================================================
  // Helper Methods
  // ============================================================
  void _debugLog(String tag, String message) {
    if (kDebugMode) debugPrint('[Dashboard::$tag] $message');
  }

  Future<void> _handleSessionExpired() async {
    await AuthService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/signin');
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showContactSupport() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contact Support'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'If you believe there should be loans associated with your account, '
                'please contact support with your registered email and phone number.',
              ),
              SizedBox(height: 16),
              Text(
                'Support Hours:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Monday - Friday: 8:00 AM - 5:00 PM'),
              Text('Saturday: 9:00 AM - 1:00 PM'),
              Text('Sunday: Closed'),
              SizedBox(height: 16),
              Text(
                'Contact Information:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('Email: mpangecreativerts@gmail.com'),
              Text('WhatsApp: 0972276257'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: null, // set in builder below
            child: Text('Close'),
          ),
          FilledButton(
            onPressed: null, // set in builder below
            child: Text('Chat Now'),
          ),
        ],
      ),
    ).then((_) {});
  }

  // Format currency for display
  String _formatCurrency(double amount, {String symbol = 'ZMW'}) {
    final formatter = NumberFormat.currency(
      symbol: symbol,
      decimalDigits: 2,
      locale: 'en_ZM',
    );
    return formatter.format(amount);
  }

  // Format date for display
  String _formatDate(DateTime? date, {String format = 'MMM d, yyyy'}) {
    if (date == null) return 'Not set';
    return DateFormat(format).format(date);
  }

  // Get status color
  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('fully paid') || lowerStatus.contains('cleared')) {
      return AppColors.SUCCESS;
    } else if (lowerStatus.contains('default') || lowerStatus.contains('past maturity') || lowerStatus.contains('write-off')) {
      return AppColors.ERROR;
    } else if (lowerStatus.contains('missed') || lowerStatus.contains('overdue')) {
      return AppColors.WARNING;
    } else if (lowerStatus.contains('active') || lowerStatus.contains('current')) {
      return Theme.of(context).colorScheme.primary;
    } else if (lowerStatus.contains('extended') || lowerStatus.contains('restructured')) {
      return AppColors.WARNING;
    }
    return AppColors.SECONDARY;
  }

  // ============================================================
  // UI Build Methods
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              HomeWidget(
                title: 'Direct Access Money',
                onBellPressed: () {
                  _showSnackbar('Notifications feature coming soon');
                },
                onProfilePressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                onSettingsPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                height: 100.0,
                topPadding: 28.0,
                titleFontSize: 18.0,
              ),
              Positioned(
                right: 8,
                top: 12,
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: _refreshing ? Colors.grey : Colors.white,
                    ),
                    onPressed: _refreshing ? null : () => _loadClientData(forceRefresh: true),
                    tooltip: 'Refresh Data',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadClientData(forceRefresh: true),
        color: Theme.of(context).colorScheme.primary,
        child: _loading && _client == null
            ? _buildLoadingState()
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error.isNotEmpty) _buildErrorState(),
                    if (_refreshing)
                      LinearProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),

                    // Clean client summary: only Borrowed and Current Balance.
                    _buildClientSummary(),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LoanCalculatorScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.calculate_outlined, size: 20),
                        label: const Text(
                          'Loan Calculator',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const AppPageSkeleton(cards: 4);
  }

  Widget _buildErrorState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Something went wrong',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _error,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.error.withOpacity(0.8),
                ),
          ),
          const SizedBox(height: 12),
          if (_hasNetworkError)
            ElevatedButton.icon(
              onPressed: () => _loadClientData(forceRefresh: true),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClientSummary() {
    if (_clientLoading && _client == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: AppSkeleton(height: 128, radius: 18),
      );
    }

    if (_client == null) {
      final msg = _clientError.isNotEmpty
          ? _clientError
          : "We couldn't find your client record. Please ensure your registered email or phone matches our records, or contact support for assistance.";

      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_off, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    "Account Not Found",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                msg,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.SECONDARY,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _loadClientData(forceRefresh: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text("Retry"),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showContactSupport,
                    icon: const Icon(Icons.support_agent, size: 18),
                    label: const Text("Contact Support"),
                  ),
                  if (_email.isNotEmpty || _phone.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Your Profile Info'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_name.isNotEmpty) Text('Name: $_name'),
                                if (_email.isNotEmpty) Text('Email: $_email'),
                                if (_phone.isNotEmpty) Text('Phone: $_phone'),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.info, size: 18),
                      label: const Text("View Profile"),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final c = _client!;

    // Extract data from loans summary
    final rawBalance = (_loansSummary['totalBalance'] ?? c.balance).toDouble();
    final totalBalance = rawBalance > 0.01 ? rawBalance : 0.0;

    // A cleared/no-loan account must show a clean zero state.
    // We intentionally do not carry historical principal into the live dashboard.
    final rawBorrowed = (_loansSummary['totalBorrowed'] ?? 0.0).toDouble();
    final totalBorrowed = totalBalance > 0.0 ? rawBorrowed : 0.0;
    final loanCount = totalBalance > 0.0 ? (_loansSummary['loanCount'] ?? _loans.length) : 0;

    // Parse next due date
    DateTime? nextDueDate;
    if (_loansSummary['nextDueDate'] != null) {
      try {
        nextDueDate = DateTime.parse(_loansSummary['nextDueDate']);
      } catch (_) {
        nextDueDate = null;
      }
    }
    final nextDueAmount = (_loansSummary['nextDueAmount'] ?? 0.0).toDouble();

    // Get display details
    final displayName = c.fullName.isNotEmpty ? c.fullName : (_name.isNotEmpty ? _name : 'Client');
    final displayEmail = (c.email ?? _email).trim();
    final displayPhone = (c.phone ?? _phone).trim();
    final displayEmailOrPhone = displayEmail.isNotEmpty ? displayEmail : displayPhone;

    return ClientDashboardCard(
      name: displayName,
      email: displayEmailOrPhone,
      amountBorrowed: totalBorrowed,
      nextDueAmount: nextDueAmount,
      nextDueDate: nextDueDate,
      amountDue: totalBalance,
      onTopUp: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientAgreementForm()));
      },
      onBorrow: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientAgreementForm()));
      },
      currency: 'ZMW',
      maskAmount: false,
      interestRate: 0.0,
      loanCount: loanCount,
      clientStatus: c.loanStatus,
      clientBucket: c.statusBucket,
      clientBalance: c.balance,
      statementDate: c.statementDate,
      isExtended: c.isExtended,
      actualBalance: null,
      isCleared: null, onManageAccount: () {  },
    );
  }

  double _summaryAmount(String key, {double fallback = 0.0}) {
    final value = _loansSummary[key];
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
  }

  int _summaryInt(String key, {int fallback = 0}) {
    final value = _loansSummary[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  Widget _buildLoansSection() {
    if (_client == null) return const SizedBox();

    final colorScheme = Theme.of(context).colorScheme;
    final currentBalance = _summaryAmount('totalBalance', fallback: _client!.balance);
    final totalBorrowed = _summaryAmount('totalBorrowed');
    final nextDueAmount = _summaryAmount('nextDueAmount');
    final activeLoanCount = _summaryInt('loanCount');
    final pastLoanCount = _summaryInt('pastLoanCount');
    final source = (_loansSummary['source'] ?? '').toString();

    DateTime? nextDueDate;
    final rawNextDue = _loansSummary['nextDueDate'];
    if (rawNextDue != null) {
      nextDueDate = DateTime.tryParse(rawNextDue.toString());
    }

    final isCleared = currentBalance <= 0.01;
    final statusText = isCleared ? 'Cleared' : 'Active Balance';
    final statusColor = isCleared ? AppColors.SUCCESS : colorScheme.primary;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Icon(
                    isCleared ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Loan Balance',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCleared
                            ? 'This client account is currently cleared. Past loans are not counted as active debt.'
                            : 'This is the current outstanding balance only. Past cleared loans are hidden from the dashboard.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.SECONDARY),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _formatCurrency(currentBalance, symbol: 'ZMW '),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: isCleared ? AppColors.SUCCESS : colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 560;
                final tiles = [
                  _balanceInfoTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Active loans',
                    value: activeLoanCount.toString(),
                  ),
                  _balanceInfoTile(
                    icon: Icons.credit_card_outlined,
                    label: 'Current principal',
                    value: _formatCurrency(totalBorrowed, symbol: 'ZMW '),
                  ),
                  _balanceInfoTile(
                    icon: Icons.event_available_outlined,
                    label: 'Next due',
                    value: nextDueDate == null
                        ? 'Not set'
                        : '${_formatCurrency(nextDueAmount, symbol: 'ZMW ')} • ${_formatDate(nextDueDate)}',
                  ),
                ];

                if (narrow) {
                  return Column(
                    children: tiles.map((tile) => Padding(padding: const EdgeInsets.only(bottom: 8), child: tile)).toList(),
                  );
                }
                return Row(
                  children: tiles
                      .map((tile) => Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: tile)))
                      .toList(),
                );
              },
            ),
            if (pastLoanCount > 0 || source.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                pastLoanCount > 0
                    ? '$pastLoanCount past loan record${pastLoanCount == 1 ? '' : 's'} found but excluded from the current balance.'
                    : 'Balance source: $source',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.SECONDARY),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ClientAgreementForm()),
                );
              },
              icon: const Icon(Icons.add_circle_outline),
              label: Text(isCleared ? 'Apply for a Loan' : 'Apply / Top Up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceInfoTile({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.SECONDARY),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.SECONDARY)),
                const SizedBox(height: 4),
                Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanTile(Loan loan, {bool expanded = false}) {
    final isActive = loan.loanStatus != 'Fully Paid' && loan.loanStatus != 'Write-Off';
    final colorScheme = Theme.of(context).colorScheme;

    // Calculate amount due
    final amountDue = loan.amortizationDue + loan.totalInterestBalance + loan.penaltyAmount;

    return Card(
      margin: expanded ? const EdgeInsets.only(bottom: 12) : const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _showLoanDetails(loan),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive ? colorScheme.primary.withOpacity(0.1) : AppColors.SECONDARY.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  isActive ? Icons.credit_card : Icons.credit_card_off,
                  color: isActive ? colorScheme.primary : AppColors.SECONDARY,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.fullName.isNotEmpty ? loan.fullName : (loan.borrowerEmail ?? 'Unnamed Loan'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: expanded ? 16 : 14,
                        color: isActive ? null : AppColors.SECONDARY,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(loan.loanStatus).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            loan.loanStatus,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(loan.loanStatus),
                            ),
                          ),
                        ),
                        if (loan.branchId != null && loan.branchId.isNotEmpty)
                          Text(
                            'Branch: ${loan.branchId}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.SECONDARY,
                            ),
                          ),
                      ],
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 8),
                      if (loan.borrowerMobile != null && loan.borrowerMobile!.isNotEmpty)
                        Text(
                          'Phone: ${loan.borrowerMobile}',
                          style: const TextStyle(fontSize: 12, color: AppColors.SECONDARY),
                        ),
                      if (loan.borrowerEmail != null && loan.borrowerEmail!.isNotEmpty)
                        Text(
                          'Email: ${loan.borrowerEmail}',
                          style: const TextStyle(fontSize: 12, color: AppColors.SECONDARY),
                        ),
                      if (loan.nextDueDate != null)
                        Text(
                          'Next Due: ${_formatDate(loan.nextDueDate)}',
                          style: const TextStyle(fontSize: 12, color: AppColors.SECONDARY),
                        ),
                    ] else if (loan.nextDueDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Next due: ${_formatDate(loan.nextDueDate)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.SECONDARY),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatCurrency(loan.principalAmount, symbol: 'ZMW '),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: expanded ? 16 : 14,
                      color: isActive ? null : AppColors.SECONDARY,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Due: ${_formatCurrency(amountDue, symbol: 'ZMW ')}',
                    style: TextStyle(
                      fontSize: expanded ? 14 : 12,
                      fontWeight: FontWeight.w600,
                      color: amountDue > 0 ? Theme.of(context).colorScheme.error : AppColors.SUCCESS,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLastUpdatedInfo() {
    if (_client == null) return const SizedBox();

    final lastUpdated = _client!.updatedAt ?? _client!.createdAt;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.info_outline,
            size: 14,
            color: AppColors.SECONDARY,
          ),
          const SizedBox(width: 4),
          Text(
            lastUpdated != null ? 'Last updated: ${_formatDate(lastUpdated, format: 'MMM d, yyyy HH:mm')}' : 'Data loaded',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.SECONDARY,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _showLoanDetails(Loan loan) async {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => LoanDetailsDialog(loan: loan),
    );
  }
}

// ============================================================
// Client Dashboard Card Widget
// ============================================================
class ClientDashboardCard extends StatelessWidget {
  final String name;
  final String email;
  final double amountBorrowed;
  final double nextDueAmount;
  final DateTime? nextDueDate;
  final double amountDue;

  final VoidCallback onTopUp;
  final VoidCallback onBorrow;

  final bool maskAmount;
  final double interestRate;
  final String currency;
  final int loanCount;

  final String? clientStatus;
  final String? clientBucket;
  final double? clientBalance;
  final DateTime? statementDate;
  final bool? isExtended;
  final double? actualBalance;
  final bool? isCleared;

  const ClientDashboardCard({
    super.key,
    required this.name,
    required this.email,
    required this.amountBorrowed,
    required this.nextDueAmount,
    required this.nextDueDate,
    required this.amountDue,
    required this.onTopUp,
    required this.onBorrow,
    required this.maskAmount,
    required this.interestRate,
    required this.currency,
    required this.loanCount,
    this.clientStatus,
    this.clientBucket,
    this.clientBalance,
    this.statementDate,
    this.isExtended,
    this.actualBalance,
    this.isCleared, required void Function() onManageAccount,
  });

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(
      symbol: currency.isNotEmpty ? '$currency ' : '',
      decimalDigits: 2,
      locale: 'en_ZM',
    );
    return maskAmount ? '••••' : formatter.format(amount);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // The dashboard is a live account view, not loan history.
    // Once the outstanding balance is cleared, both figures reset to zero.
    final hasOutstandingBalance = amountDue > 0.01;
    final displayBalance = hasOutstandingBalance ? amountDue : 0.0;
    final displayBorrowed = hasOutstandingBalance ? amountBorrowed : 0.0;

    final borrowedText = _formatCurrency(displayBorrowed);
    final balanceText = _formatCurrency(displayBalance);

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: colorScheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (email.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          email,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.SECONDARY,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(height: 1, color: Theme.of(context).dividerColor.withOpacity(0.7)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _simpleBalanceTile(
                    context,
                    label: 'Borrowed',
                    value: borrowedText,
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _simpleBalanceTile(
                    context,
                    label: 'Current Balance',
                    value: balanceText,
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: FilledButton.icon(
                onPressed: hasOutstandingBalance ? onTopUp : onBorrow,
                icon: Icon(
                  hasOutstandingBalance ? Icons.add_circle_outline : Icons.add,
                  size: 18,
                ),
                label: Text(
                  hasOutstandingBalance ? 'Apply / Top Up' : 'Apply for a Loan',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _simpleBalanceTile(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.SECONDARY),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.SECONDARY,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill(BuildContext context, {required String label, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildWideMetrics(
    BuildContext context,
    String borrowedText,
    String nextDueText,
    String amountDueText,
    int? daysUntilDue,
    bool isOverdue,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _metricColumn(context, 'Total Borrowed', borrowedText, Icons.credit_card),
        _metricColumnWithDate(
          context,
          'Next Due',
          nextDueText,
          nextDueDate,
          daysUntilDue,
          isOverdue,
          Icons.calendar_today,
        ),
        _metricColumn(context, 'Current Balance', amountDueText, Icons.payment),
      ],
    );
  }

  Widget _buildNarrowMetrics(
    BuildContext context,
    String borrowedText,
    String nextDueText,
    String amountDueText,
    int? daysUntilDue,
    bool isOverdue,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _metricColumn(context, 'Borrowed', borrowedText, Icons.credit_card),
            _metricColumn(context, 'Balance', amountDueText, Icons.payment),
          ],
        ),
        const SizedBox(height: 20),
        _metricColumnWithDate(
          context,
          'Next Due',
          nextDueText,
          nextDueDate,
          daysUntilDue,
          isOverdue,
          Icons.calendar_today,
        ),
      ],
    );
  }

  Widget _metricColumn(BuildContext context, String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.SECONDARY),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.SECONDARY,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _metricColumnWithDate(
    BuildContext context,
    String label,
    String value,
    DateTime? date,
    int? daysUntilDue,
    bool isOverdue,
    IconData icon,
  ) {
    String subtitle = 'No due date';
    Color? subtitleColor = AppColors.SECONDARY;

    if (date != null) {
      if (isOverdue) {
        subtitle = 'Overdue!';
        subtitleColor = AppColors.ERROR;
      } else if (daysUntilDue == 0) {
        subtitle = 'Due today';
        subtitleColor = AppColors.WARNING;
      } else if (daysUntilDue == 1) {
        subtitle = 'Due tomorrow';
        subtitleColor = AppColors.WARNING;
      } else if (daysUntilDue != null && daysUntilDue <= 7) {
        subtitle = 'In $daysUntilDue days';
        subtitleColor = AppColors.WARNING;
      } else {
        subtitle = DateFormat('MMM d, yyyy').format(date);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.SECONDARY),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.SECONDARY,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isOverdue ? AppColors.ERROR : null,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: subtitleColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Loan Details Dialog
// ============================================================
class LoanDetailsDialog extends StatelessWidget {
  final Loan loan;

  const LoanDetailsDialog({super.key, required this.loan});

  String _formatCurrency(double amount, {String symbol = 'ZMW'}) {
    final formatter = NumberFormat.currency(
      symbol: '$symbol ',
      decimalDigits: 2,
      locale: 'en_ZM',
    );
    return formatter.format(amount);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat('MMM d, yyyy').format(date);
  }

  Color _getStatusColor(BuildContext context, String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('fully paid') || lowerStatus.contains('cleared')) {
      return AppColors.SUCCESS;
    } else if (lowerStatus.contains('default') || lowerStatus.contains('past maturity')) {
      return AppColors.ERROR;
    } else if (lowerStatus.contains('missed')) {
      return AppColors.WARNING;
    } else if (lowerStatus.contains('restructured')) {
      return Theme.of(context).colorScheme.primary;
    } else if (lowerStatus.contains('write-off')) {
      return AppColors.SECONDARY;
    }
    return AppColors.SECONDARY;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalDue = loan.amortizationDue + loan.totalInterestBalance + loan.penaltyAmount;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.credit_card,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Loan Details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(context, loan.loanStatus).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: _getStatusColor(context, loan.loanStatus),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      loan.loanStatus,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(context, loan.loanStatus),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Loan Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),

              const SizedBox(height: 12),

              _buildDetailRow(context, 'Loan Name', loan.fullName.isNotEmpty ? loan.fullName : 'Unnamed Loan'),
              _buildDetailRow(context, 'Principal Amount', _formatCurrency(loan.principalAmount)),
              _buildDetailRow(context, 'Interest Balance', _formatCurrency(loan.totalInterestBalance)),
              _buildDetailRow(context, 'Amortization Due', _formatCurrency(loan.amortizationDue)),
              _buildDetailRow(context, 'Penalty Amount', _formatCurrency(loan.penaltyAmount)),

              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Amount Due',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      _formatCurrency(totalDue),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'Additional Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),

              const SizedBox(height: 12),

              if (loan.nextDueDate != null) _buildDetailRow(context, 'Next Due Date', _formatDate(loan.nextDueDate!)),
              if (loan.borrowerMobile != null && loan.borrowerMobile!.isNotEmpty)
                _buildDetailRow(context, 'Mobile Number', loan.borrowerMobile!),
              if (loan.borrowerEmail != null && loan.borrowerEmail!.isNotEmpty)
                _buildDetailRow(context, 'Email Address', loan.borrowerEmail!),
              if (loan.borrowerAddress != null && loan.borrowerAddress!.isNotEmpty)
                _buildDetailRow(context, 'Address', loan.borrowerAddress!),
              _buildDetailRow(context, 'Branch ID', loan.branchId),
              if (loan.importedAt != null) _buildDetailRow(context, 'Imported On', _formatDate(loan.importedAt!)),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Payment option coming soon'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Pay Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.SECONDARY,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
