// lib/debug/zanaco_inspector.dart
// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:daml/services/local_storage.dart';

class ZanacoInspectorScreen extends StatefulWidget {
  const ZanacoInspectorScreen({super.key});

  @override
  State<ZanacoInspectorScreen> createState() => _ZanacoInspectorScreenState();
}

class _ZanacoInspectorScreenState extends State<ZanacoInspectorScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  DateTime _selectedDate = DateTime.now();
  String _testBranch = '';
  String _testChannel = 'Airtel';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; });
    await LocalStorage.ensureInitialized();
    final raw = LocalStorage.getAllZanacoDistributions();
    setState(() {
      _items = raw;
      _loading = false;
    });
  }

  Widget _buildItem(Map<String, dynamic> item, int index) {
    final dateRaw = item['date'];
    DateTime parsed;
    try {
      if (dateRaw is DateTime) {
        parsed = dateRaw;
      } else if (dateRaw is String) parsed = DateTime.tryParse(dateRaw) ?? DateTime.now();
      else parsed = DateTime.now();
    } catch (_) {
      parsed = DateTime.now();
    }

    final created = item['createdAt']?.toString() ?? '';
    final fromBranch = item['fromBranch']?.toString() ?? '';
    final allocations = item['allocations'] is Map ? item['allocations'] as Map : <String, dynamic>{};

    // Build readable allocations list
    final allocLines = <String>[];
    try {
      allocations.forEach((b, inner) {
        try {
          final innerMap = inner is Map ? inner : {};
          innerMap.forEach((ch, amt) {
            allocLines.add('${b.toString()} -> ${ch.toString()} : ${amt.toString()}');
          });
        } catch (_) {}
      });
    } catch (_) {}

    return ExpansionTile(
      key: Key('zanaco_$index'),
      title: Text('From: $fromBranch  — ${DateFormat.yMMMd().format(parsed)}'),
      subtitle: Text('Created: ${created.toString()} • ${allocLines.length} allocations'),
      children: [
        if (allocLines.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('allocations: (empty)')),
        for (final l in allocLines) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Text(l)),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Test this record for branch'),
                onPressed: () {
                  setState(() {
                    _selectedDate = parsed;
                    _testBranch = fromBranch;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Test branch/date set to: $_testBranch / ${DateFormat.yMMMd().format(_selectedDate)}')));
                },
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete record (debug)'),
                onPressed: () async {
                  // ask for confirmation
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Zanaco record?'),
                      content: const Text('This deletes only the local stored distribution (debug).'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    try {
                      await LocalStorage.deleteZanacoDistribution(index);
                      await _refresh();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted (by index)')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runLookup() async {
    await LocalStorage.ensureInitialized();
    if (_testBranch.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a test branch first (use "Test this record for branch")')));
      return;
    }
    final normDate = DateTime.utc(_selectedDate.toUtc().year, _selectedDate.toUtc().month, _selectedDate.toUtc().day);
    final res = LocalStorage.getZanacoAllocForBranchOnDate(normDate, _testChannel, _testBranch);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Lookup result'),
      content: Text('branch: $_testBranch\nchannel: $_testChannel\ndate: ${DateFormat.yMMMd().format(_selectedDate)}\n\nvalue: $res'),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zanaco Inspector (debug)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Selected branch: ${_testBranch.isEmpty ? '(none)' : _testBranch}')),
                  const SizedBox(width: 8),
                  Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  DropdownButton<String>(
                    value: _testChannel,
                    items: const ['Airtel', 'MTN'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _testChannel = v ?? 'Airtel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.search), label: const Text('Run lookup'), onPressed: _runLookup),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.clear), label: const Text('Clear selection'), onPressed: () => setState(() { _testBranch=''; })),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: _items.isEmpty
                      ? const Center(child: Text('No zanaco_distributions found'))
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (_, i) => _buildItem(_items[i], i),
                        ),
                )
              ]),
            ),
    );
  }
}
