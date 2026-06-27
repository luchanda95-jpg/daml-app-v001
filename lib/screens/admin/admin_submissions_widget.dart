// lib/screens/admin/admin_submissions_widget.dart
// Simple admin UI to view client submissions — all storage/back-end logic removed.

// ignore_for_file: use_build_context_synchronously

import 'dart:convert';

import 'package:flutter/material.dart';

/// Display a list of admin submissions provided by the parent widget.
///
/// - No SharedPreferences or network calls are performed in this widget.
/// - Provide `submissions` when creating the widget. The widget keeps an
///   in-memory copy and allows marking items as handled.
/// - Optionally provide `onMarkHandled` to let the parent persist or process
///   removals. If omitted, removal is in-memory only.
class AdminSubmissionsWidget extends StatefulWidget {
  final List<Map<String, dynamic>> submissions;
  final Future<void> Function(String id, Map<String, dynamic> item)? onMarkHandled;

  const AdminSubmissionsWidget({
    super.key,
    this.submissions = const [],
    this.onMarkHandled,
  });

  @override
  State<AdminSubmissionsWidget> createState() => _AdminSubmissionsWidgetState();
}

class _AdminSubmissionsWidgetState extends State<AdminSubmissionsWidget> {
  late List<Map<String, dynamic>> _items;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Use an in-memory copy of provided submissions
    _items = List<Map<String, dynamic>>.from(widget.submissions);
    _loading = false;
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    // Re-copy from parent-provided list (no storage access)
    await Future.delayed(const Duration(milliseconds: 150));
    setState(() {
      _items = List<Map<String, dynamic>>.from(widget.submissions);
      _loading = false;
    });
  }

  Future<void> _markHandledLocal(String id) async {
    _items.removeWhere((e) => e['id']?.toString() == id);
    setState(() {});
  }

  void _showDetails(Map<String, dynamic> item) {
    final pretty = const JsonEncoder.withIndent('  ').convert(item['data'] ?? item);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Submission from ${item['from'] ?? 'unknown'}'),
        content: SingleChildScrollView(child: Text(pretty)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close')),
          TextButton(
            onPressed: () async {
              Navigator.of(c).pop();
              final id = item['id']?.toString() ?? '';

              if (widget.onMarkHandled != null) {
                try {
                  await widget.onMarkHandled!(id, item);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as handled')));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Handler failed: $e')));
                }
              } else {
                await _markHandledLocal(id);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked as handled (in-memory)')));
              }
            },
            child: const Text('Mark handled'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Submissions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
            tooltip: 'Refresh',
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No submissions'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final it = _items[i];
                    final from = it['from'] ?? 'unknown';
                    final ts = it['ts'] ?? '';
                    final preview = (() {
                      final d = it['data'];
                      if (d is Map) {
                        if (d['name'] != null) return d['name'].toString();
                        if (d['loanAmount'] != null) return 'Loan: ${d['loanAmount']}';
                      }
                      return 'Tap to view';
                    })();

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        title: Text(from.toString()),
                        subtitle: Text(preview),
                        trailing: Text(
                          ts.toString().split('T').first,
                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                        onTap: () => _showDetails(it),
                      ),
                    );
                  },
                ),
    );
  }
}
