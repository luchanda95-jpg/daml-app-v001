// lib/screens/admin/admin.dart
// ignore_for_file: use_build_context_synchronously, deprecated_member_use, unnecessary_type_check

import 'dart:convert';

import 'package:daml/screens/admin/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:daml/theme/app_theme.dart';
import 'package:daml/services/sync_service.dart';
import 'package:daml/services/api_service.dart';
import 'package:daml/services/auth_service.dart';
import 'package:daml/models/report_model.dart';

// Screens used by the dashboard
import 'overview_screen.dart';
import 'branches_screen.dart';
import 'monthly_screen.dart';
import 'admin_profile_screen.dart';
import 'edit_client_balances.dart';
import 'package:daml/screens/client/widgets/home_widget.dart';
import 'package:daml/screens/client/widgets/settings_screen.dart';

class OverallAdminDashboard extends StatefulWidget {
  const OverallAdminDashboard({super.key});

  @override
  State<OverallAdminDashboard> createState() => _OverallAdminDashboardState();
}

class _OverallAdminDashboardState extends State<OverallAdminDashboard> {
  int _currentIndex = 0;
  String username = 'Admin';

  // Pending deletions state
  static const String _pendingKey = 'pending_deletions';
  int _pendingCount = 0;
  List<Map<String, String>> _pendingList = [];
  final SyncService _syncService = SyncService();

  // Client list state
  bool _loadingClients = true;
  List<Map<String, String>> _clients = [];

  // Reports state (loaded from ApiService)
  bool _loadingReports = true;
  String? _reportsError;
  List<DailyReport> _reports = [];

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadPendingCount();
    _loadClients();
    _loadReports(); // <-- load reports from API
  }

  @override
  void dispose() {
    try {
      _syncService.dispose();
    } catch (_) {}
    super.dispose();
  }

  // ---------------- helpers ----------------
  bool _sameUtcDay(DateTime a, DateTime b) {
    final ua = a.toUtc();
    final ub = b.toUtc();
    return ua.year == ub.year && ua.month == ub.month && ua.day == ub.day;
  }

  // ---------------- user ----------------
  Future<void> _loadUser() async {
    try {
      final profile = await AuthService.getLocalProfile();
      final nm = (profile['name'] ?? '').toString();
      if (!mounted) return;
      if (nm.isNotEmpty) setState(() => username = nm);
    } catch (_) {}
  }

  // ---------------- pending deletions ----------------
  Future<void> _loadPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);

    if (raw == null || raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _pendingCount = 0;
        _pendingList = [];
      });
      return;
    }

    try {
      final list = (jsonDecode(raw) as List).cast<Map>().map((m) {
        final map = Map<String, dynamic>.from(m);
        return <String, String>{
          'branch': map['branch']?.toString() ?? '',
          'date': map['date']?.toString() ?? '',
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _pendingList = list;
        _pendingCount = list.length;
      });
    } catch (_) {
      await prefs.remove(_pendingKey);
      if (!mounted) return;
      setState(() {
        _pendingCount = 0;
        _pendingList = [];
      });
    }
  }

  Future<void> _savePendingList() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(_pendingList));
    if (!mounted) return;
    setState(() => _pendingCount = _pendingList.length);
  }

  Future<void> _addPendingDeletion(DailyReport report) async {
    final item = {
      'branch': report.branch,
      'date': report.date.toUtc().toIso8601String(),
    };

    final exists = _pendingList.any((p) =>
        (p['branch'] ?? '').toLowerCase().trim() == item['branch']!.toLowerCase().trim() &&
        (p['date'] ?? '') == item['date']);

    if (!exists) {
      _pendingList.add(item);
      await _savePendingList();
    }
  }

  Future<void> _removePendingDeletion(Map<String, String> item) async {
    _pendingList.removeWhere((p) =>
        (p['branch'] ?? '') == item['branch'] && (p['date'] ?? '') == item['date']);
    await _savePendingList();
  }

  Future<void> _processPendingDeletions() async {
    if (_pendingList.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pending deletions to process')),
      );
      return;
    }

    // Ensure we have latest reports
    await _ensureReportsLoaded();

    int success = 0, failed = 0;

    for (final p in List<Map<String, String>>.from(_pendingList)) {
      try {
        final branch = (p['branch'] ?? '').toString();
        final dateIso = (p['date'] ?? '').toString();
        final parsed = DateTime.parse(dateIso);

        final match = _reports.firstWhere(
          (r) =>
              r.branch.toLowerCase().trim() == branch.toLowerCase().trim() &&
              _sameUtcDay(r.date, parsed),
          orElse: () => DailyReport(branch: branch, date: parsed, totalLoans: null),
        );

        await _syncService.deleteReport(match);
        await _removePendingDeletion(p);

        _reports.removeWhere((r) =>
            r.branch.toLowerCase().trim() == branch.toLowerCase().trim() &&
            _sameUtcDay(r.date, parsed));

        success++;
      } catch (_) {
        failed++;
      }
    }

    await _loadPendingCount();

    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Processed pending deletions — success: $success, failed: $failed')),
    );
  }

  void _showPendingActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                const Text('Pending deletions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_pendingCount > 0) Text('$_pendingCount queued', style: TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 12),
            if (_pendingList.isEmpty) ...[
              Center(child: Text('No pending deletions', style: TextStyle(color: Colors.grey[400]))),
            ] else ...[
              SizedBox(
                height: 180,
                child: ListView.separated(
                  itemCount: _pendingList.length,
                  separatorBuilder: (_, __) => const Divider(height: 8),
                  itemBuilder: (context, i) {
                    final p = _pendingList[i];
                    final branch = p['branch'] ?? '';
                    final date = p['date'] ?? '';
                    return ListTile(
                      title: Text(branch, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat.yMMMd().format(DateTime.parse(date).toLocal())),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever),
                        tooltip: 'Remove from pending (won\'t try to delete remote)',
                        onPressed: () async {
                          await _removePendingDeletion(p);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Removed pending deletion for $branch')),
                          );
                          Navigator.of(context).pop();
                          _showPendingActions();
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.sync),
                      label: const Text('Process pending deletions'),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _processPendingDeletions();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ]),
        );
      },
    );
  }

  // ---------------- clients list ----------------
  Future<void> _loadClients() async {
    if (mounted) setState(() => _loadingClients = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('auth_users');

      if (raw == null || raw.isEmpty) {
        _clients = [];
      } else {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        final list = <Map<String, String>>[];
        decoded.forEach((email, data) {
          final entry = data as Map<String, dynamic>;
          final name = (entry['name'] as String?) ?? '';
          list.add({'email': email, 'name': name});
        });

        list.sort((a, b) =>
            (a['name']?.toLowerCase() ?? a['email']!).compareTo((b['name']?.toLowerCase() ?? b['email']!)));

        _clients = list;
      }
    } catch (e) {
      _clients = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load clients: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingClients = false);
    }
  }

  // ---------------- reports (API-backed) ----------------
  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _loadingReports = true;
        _reportsError = null;
      });
    }

    try {
      // Ensure ApiService has Authorization header if token exists
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        ApiService.setAuthToken(token);
      }

      final raw = await ApiService.fetchAllReports();
      final list = (raw is List) ? raw : <dynamic>[];

      final parsed = <DailyReport>[];

      for (final item in list) {
        if (item is Map) {
          try {
            // ✅ USE YOUR ROBUST PARSER (supports mongo wrappers + full fields)
            final m = Map<dynamic, dynamic>.from(item);
            final rep = DailyReport.fromJson(m);

            // drop totally broken items
            if (rep.branch.trim().isEmpty) continue;

            parsed.add(rep);
          } catch (_) {
            // ignore individual item parse errors
          }
        }
      }

      // Sort newest first
      parsed.sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _reports = parsed;
        _loadingReports = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reportsError = e.toString();
        _loadingReports = false;
      });
    }
  }

  Future<void> _ensureReportsLoaded() async {
    if (_loadingReports) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (_reports.isEmpty && !_loadingReports) {
      await _loadReports();
    }
  }

  Future<void> _onDeleteReport(DailyReport rep) async {
    try {
      // Try remote delete first
      await _syncService.deleteReport(rep);

      // Remove locally in-memory
      _reports.removeWhere((r) =>
          r.branch.toLowerCase().trim() == rep.branch.toLowerCase().trim() &&
          _sameUtcDay(r.date, rep.date));

      await _loadPendingCount();

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report deleted (remote)')),
      );
    } catch (_) {
      // If remote delete failed, queue it for later
      await _addPendingDeletion(rep);
      await _loadPendingCount();

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline: deletion queued')),
      );
    }
  }

  void _openEdit(String email) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditClientBalancesScreen(initialEmail: email)),
    );

    if (result == true) {
      await _loadClients();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Balances updated')),
      );
    }
  }

  void _openBlankEditor() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EditClientBalancesScreen(initialEmail: '',)),
    );

    if (result == true) {
      await _loadClients();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferredHeader = PreferredSize(
      preferredSize: const Size.fromHeight(100),
      child: HomeWidget(
        title: 'Admin Dashboard',
        onProfilePressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const AdminProfileScreen()),
          );
        },
        onSettingsPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (ctx) => const SettingsScreen()),
          );
        },
      ),
    );

    final pages = [
      OverviewScreen(
        username: username,
        pendingCount: _pendingCount,
        showPendingActions: _showPendingActions,
        reports: _reports,
        loading: _loadingReports,
        error: _reportsError,
        refreshReports: _loadReports,
      ),
      BranchesScreen(
        pendingCount: _pendingCount,
        showPendingActions: _showPendingActions,
        reports: _reports,
        loading: _loadingReports,
        error: _reportsError,
        refreshReports: _loadReports,
      ),
      MonthlyScreen(
        pendingCount: _pendingCount,
        showPendingActions: _showPendingActions,
        reports: const [], // keep existing behavior for now
      ),
      ReportsScreen(
        pendingCount: _pendingCount,
        showPendingActions: _showPendingActions,
        addPendingDeletion: _addPendingDeletion,
        removePendingDeletion: _removePendingDeletion,
        loadPendingCount: _loadPendingCount,
        onDelete: _onDeleteReport,
        reports: _reports,
        loading: _loadingReports,
        error: _reportsError,
        refreshReports: _loadReports,
      ),
      _buildClientsPage(),
    ];

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        appBar: preferredHeader,
        body: SafeArea(child: pages[_currentIndex]),
        bottomNavigationBar: _buildBottomNavBar(),
        floatingActionButton: _currentIndex == 4
            ? FloatingActionButton.extended(
                onPressed: _openBlankEditor,
                icon: const Icon(Icons.edit),
                label: const Text('Edit balances'),
              )
            : null,
      ),
    );
  }

  Widget _buildClientsPage() {
    if (_loadingClients) return const Center(child: CircularProgressIndicator());

    if (_clients.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No registered clients'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add / Edit manually'),
              onPressed: _openBlankEditor,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadClients,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (c, i) {
          final client = _clients[i];
          final name = (client['name']?.isNotEmpty == true) ? client['name'] : client['email'];
          final email = client['email']!;

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              title: Text(name!),
              subtitle: Text(email),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit balances',
                onPressed: () => _openEdit(email),
              ),
              onTap: () => _openEdit(email),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey[600],
        showUnselectedLabels: true,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Overview"),
          BottomNavigationBarItem(icon: Icon(Icons.account_tree), label: "Branches"),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_view_month), label: "Monthly"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Reports"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Clients"),
        ],
      ),
    );
  }
}
