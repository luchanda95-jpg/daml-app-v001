// lib/screens/branch/widgets/branch_summery.dart
// Branch summary widget (Supabase data via ApiService compatibility facade)
//
// Robust Zanaco totals fetcher using direct Supabase-backed methods.

// ignore_for_file: deprecated_member_use, curly_braces_in_flow_structures

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:daml/services/api_service.dart';
import 'package:daml/services/auth_service.dart';

class BranchSummaryWidget extends StatefulWidget {
  final String name;
  final String email;
  final double zanacoAllocation;
  final double mtnAllocation;
  final double airtelAllocation;
  final bool maskAmount;
  final VoidCallback onToggleVisibility;
  final DateTime? dateForZanacoLookup;
  final bool includeTodayAllocations;
  final String? initialResolvedBranch;
  final Map<String, double>? initialTodayAllocations;

  const BranchSummaryWidget({
    super.key,
    required this.name,
    required this.email,
    this.zanacoAllocation = 0.0,
    this.mtnAllocation = 0.0,
    this.airtelAllocation = 0.0,
    required this.maskAmount,
    required this.onToggleVisibility,
    this.dateForZanacoLookup,
    required this.includeTodayAllocations,
    this.initialResolvedBranch,
    this.initialTodayAllocations,
  });

  @override
  State<BranchSummaryWidget> createState() => _BranchSummaryWidgetState();
}

class _BranchSummaryWidgetState extends State<BranchSummaryWidget> {
  final NumberFormat _fmt = NumberFormat.decimalPattern()..maximumFractionDigits = 2;

  double _airtelAddedToday = 0.0;
  double _mtnAddedToday = 0.0;
  bool _loading = false;
  DateTime? _lastUpdated;
  dynamic _lastRawResponse;

  // Keep last-known totals so we avoid flipping UI to zero on transient errors.
  double _lastKnownAirtel = 0.0;
  double _lastKnownMtn = 0.0;

  // Known small mapping from email/branch -> canonical branch slug (optional)
  static const Map<String, String> _branchEmailMap = {
    'monze': 'monze',
    'mazabuka': 'mazabuka',
    'lusaka': 'lusaka',
    'solwezi': 'solwezi',
    'lumezi': 'lumezi',
    'nakonde': 'nakonde',
    'directaccess': 'directaccess',
  };

  @override
  void initState() {
    super.initState();
    _fetchAllocations();
  }

  @override
  void didUpdateWidget(covariant BranchSummaryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateForZanacoLookup != widget.dateForZanacoLookup ||
        oldWidget.includeTodayAllocations != widget.includeTodayAllocations ||
        oldWidget.initialResolvedBranch != widget.initialResolvedBranch ||
        oldWidget.initialTodayAllocations != widget.initialTodayAllocations ||
        oldWidget.name.toLowerCase().trim() != widget.name.toLowerCase().trim()) {
      _fetchAllocations();
    }
  }

  Future<void> _fetchAllocations() async {
    // Respect parent's choice
    if (!widget.includeTodayAllocations) {
      if (mounted) {
        setState(() {
          _airtelAddedToday = 0.0;
          _mtnAddedToday = 0.0;
          _lastUpdated = null;
          _lastRawResponse = null;
          _loading = false;
        });
      }
      return;
    }
      
    // If parent explicitly supplied today's allocations, use them (no network)
    if (widget.initialTodayAllocations != null) {
      final a = (widget.initialTodayAllocations!['airtel'] ??
          widget.initialTodayAllocations!['Airtel'] ??
          widget.initialTodayAllocations!['AirTel'] ??
          0.0);
      final m = (widget.initialTodayAllocations!['mtn'] ??
          widget.initialTodayAllocations!['MTN'] ??
          widget.initialTodayAllocations!['Mtn'] ??
          0.0);
      if (mounted) {
        setState(() {
          _airtelAddedToday = _toDoubleDefensive(a);
          _mtnAddedToday = _toDoubleDefensive(m);
          _lastUpdated = DateTime.now();
          _lastKnownAirtel = _airtelAddedToday;
          _lastKnownMtn = _mtnAddedToday;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _lastRawResponse = null;
    });

    try {
      // Attach token if available
      try {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          ApiService.setAuthToken(token);
        } else {
          ApiService.clearAuthToken();
        }
      } catch (_) {
        ApiService.clearAuthToken();
      }

      // Resolve branch - robust: prefer initialResolvedBranch, then widget.name,
      // then try to derive from signed in profile (AuthService.getLocalProfile())
      String branchQuery = await _resolveBranchQueryRobust();

      final date = widget.dateForZanacoLookup ?? DateTime.now();

      debugPrint('[BranchSummary] requesting Supabase Zanaco data for $branchQuery on $date');

      dynamic resp;
      // Try the "getZanaco" friendly endpoint first (often present)
      try {
        resp = await ApiService.getZanaco(date: date, branch: branchQuery);
      } catch (e) {
        debugPrint('[BranchSummary] getZanaco failed, trying distributions fallback: $e');
        // fallback to older distributions endpoint
        try {
          resp = await ApiService.fetchZanacoDistributions(branch: branchQuery, date: date);
        } catch (e2) {
          debugPrint('[BranchSummary] fetchZanacoDistributions also failed: $e2');
          // On endpoint not found or network error, keep last-known values instead of zeroing
          if (mounted) {
            setState(() => _loading = false);
          }
          rethrow;
        }
      }


      // Save raw for inspect
      _lastRawResponse = resp;

      debugPrint('[BranchSummary] raw zanaco response: $resp');

      // Parse response into airtel/mtn totals
      double airtel = 0.0;
      double mtn = 0.0;
      bool parsedAny = false;

      try {
        // Case 1: resp is a Map with direct keys: { 'airtel': X, 'mtn': Y }
        if (resp is Map) {
          final mResp = Map.from(resp);
          final aCandidate = mResp['airtel'] ?? mResp['Airtel'] ?? mResp['air_tel'] ?? mResp['air_tel_amount'];
          final mCandidate = mResp['mtn'] ?? mResp['Mtn'] ?? mResp['m_t_n'] ?? mResp['mtn_amount'];

          if (aCandidate != null || mCandidate != null) {
            airtel = _toDoubleDefensive(aCandidate);
            mtn = _toDoubleDefensive(mCandidate);
            parsedAny = true;
          } else if (mResp.containsKey('distributions') && mResp['distributions'] is List) {
            // Case 2: { "distributions": [ {...}, {...} ] }
            final List list = mResp['distributions'] as List;
            for (final it in list) {
              final parsed = _parseDistributionItem(it);
              airtel += parsed['airtel'] ?? 0.0;
              mtn += parsed['mtn'] ?? 0.0;
            }
            parsedAny = list.isNotEmpty;
          } else {
            // Maybe it's a single document with channel + amount
            final parsed = _parseDistributionItem(mResp);
            airtel = parsed['airtel'] ?? 0.0;
            mtn = parsed['mtn'] ?? 0.0;
            parsedAny = !(airtel == 0.0 && mtn == 0.0);
          }
        } else if (resp is List) {
          // Case 3: a list of documents
          for (final it in resp) {
            final parsed = _parseDistributionItem(it);
            airtel += parsed['airtel'] ?? 0.0;
            mtn += parsed['mtn'] ?? 0.0;
          }
          parsedAny = resp.isNotEmpty;
        } else {
          // Primitive numeric - treat as airtel
          airtel = _toDoubleDefensive(resp);
          parsedAny = airtel != 0.0;
        }
      } catch (e) {
        debugPrint('[BranchSummary] Error parsing zanaco payload: $e');
      }

      if (mounted) {
        setState(() {
          // If we parsed some values, update them. Otherwise keep last-known values.
          if (parsedAny) {
            _airtelAddedToday = airtel;
            _mtnAddedToday = mtn;
            _lastKnownAirtel = airtel;
            _lastKnownMtn = mtn;
          } else {
            // no new parsed data — use previously known
            _airtelAddedToday = _lastKnownAirtel;
            _mtnAddedToday = _lastKnownMtn;
          }
          _lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      debugPrint('[BranchSummary] fetch error: $e');
      if (mounted) {
        // preserve last-known totals on error instead of zeroing
        setState(() {
          _airtelAddedToday = _lastKnownAirtel;
          _mtnAddedToday = _lastKnownMtn;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load Zanaco allocations: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Resolve branch query with multiple fallbacks:
  /// 1. widget.initialResolvedBranch
  /// 2. widget.name
  /// 3. AuthService.getLocalProfile() -> email -> ApiService.getBranchForEmail(email)
  Future<String> _resolveBranchQueryRobust() async {
    final supplied = widget.initialResolvedBranch?.trim();
    if (supplied != null && supplied.isNotEmpty) return supplied.toLowerCase().trim();

    final fromName = widget.name.trim();
    if (fromName.isNotEmpty && !_looksLikeGuest(fromName)) return fromName.toLowerCase().trim();

    // Try email from widget.email
    final wemail = widget.email.trim();
    if (wemail.isNotEmpty && wemail.contains('@')) {
      final local = wemail.split('@').first.toLowerCase().trim();
      if (_branchEmailMap.containsKey(local)) return _branchEmailMap[local]!;
    }

    // Try the local profile stored in AuthService
    try {
      final profile = await AuthService.getLocalProfile();
      final email = (profile['email'] ?? '').toString().trim();
      if (email.isNotEmpty) {
        // try server mapping
        try {
          final branchFromApi = await ApiService.getBranchForEmail(email);
          if (branchFromApi != null && branchFromApi.trim().isNotEmpty) return branchFromApi.trim().toLowerCase();
        } catch (_) {
          // ignore and try fallback below
        }
        final local = email.split('@').first.toLowerCase().trim();
        if (_branchEmailMap.containsKey(local)) return _branchEmailMap[local]!;
        return local;
      }
    } catch (_) {
      // ignore
    }

    // Last resort: derive from widget.name even if 'Guest' — return empty string if nothing useful
    return (widget.name.trim().isNotEmpty) ? widget.name.trim().toLowerCase() : '';
  }

  bool _looksLikeGuest(String s) {
    final sl = s.toLowerCase();
    return sl.contains('guest') || sl.contains('user') || sl.contains('anonymous');
  }

  // Return a map with keys 'airtel' and 'mtn' from one document-like item
  Map<String, double> _parseDistributionItem(dynamic item) {
    try {
      if (item == null) return {'airtel': 0.0, 'mtn': 0.0};
      if (item is Map) {
        final chRaw = (item['channel'] ?? item['channelName'] ?? item['ch'] ?? '').toString().toLowerCase();
        final channel = chRaw.trim();
        final amt = _extractAmountFromDynamic(item['amount'] ?? item['value'] ?? item['allocated'] ?? item);

        if (channel.contains('airtel')) return {'airtel': amt, 'mtn': 0.0};
        if (channel.contains('mtn')) return {'airtel': 0.0, 'mtn': amt};

        // fallback: try to infer by keys
        if (item.containsKey('airtel')) return {'airtel': _toDoubleDefensive(item['airtel']), 'mtn': 0.0};
        if (item.containsKey('mtn')) return {'airtel': 0.0, 'mtn': _toDoubleDefensive(item['mtn'])};

        // if item has branch+channel+amount but channel empty, try to inspect other fields
        return {'airtel': amt, 'mtn': 0.0};
      } else {
        // primitive numeric -> treat as airtel
        return {'airtel': _toDoubleDefensive(item), 'mtn': 0.0};
      }
    } catch (e) {
      debugPrint('[BranchSummary] _parseDistributionItem error: $e');
      return {'airtel': 0.0, 'mtn': 0.0};
    }
  }

  // tolerant conversion to double
  double _toDoubleDefensive(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  // reuse logic similar to ApiService._extractAmountForApi
  double _extractAmountFromDynamic(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(',', '').trim();
      return double.tryParse(cleaned) ?? 0.0;
    }
    if (v is Map) {
      try {
        for (final key in v.keys) {
          final lk = key.toString().toLowerCase();
          if (lk.contains('number')) {
            final inner = v[key];
            if (inner is String) return double.tryParse(inner.replaceAll(',', '').trim()) ?? 0.0;
            if (inner is num) return inner.toDouble();
          }
        }
      } catch (_) {}
      if (v.containsKey('amount')) return _extractAmountFromDynamic(v['amount']);
      if (v.values.isNotEmpty) return _extractAmountFromDynamic(v.values.first);
    }
    return 0.0;
  }

  /// Inspect raw response via public ApiService.getZanaco for debugging.
  Future<void> _inspectRaw() async {
    try {
      final branchQuery = await _resolveBranchQueryRobust();
      final date = widget.dateForZanacoLookup ?? DateTime.now();

      // try getZanaco for a pretty display
      dynamic resp;
      try {
        resp = await ApiService.getZanaco(date: date, branch: branchQuery);
      } catch (e) {
        try {
          resp = await ApiService.fetchZanacoDistributions(branch: branchQuery, date: date);
        } catch (_) {
          resp = _lastRawResponse ?? 'No raw data available';
        }
      }

      final pretty = const JsonEncoder.withIndent('  ').convert(resp);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Raw Zanaco response — $branchQuery'),
          content: SingleChildScrollView(child: Text(pretty)),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      debugPrint('[BranchSummary] inspect failed: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inspect failed: $e')));
    }
  }

  String _maskOrFormat(double v) => widget.maskAmount ? '••••' : _fmt.format(v);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    // Use last-known totals when includeTodayAllocations is true
    final displayMtn = widget.mtnAllocation + (widget.includeTodayAllocations ? _mtnAddedToday : 0.0);
    final displayAirtel = widget.airtelAllocation + (widget.includeTodayAllocations ? _airtelAddedToday : 0.0);
    final totalToday = (widget.includeTodayAllocations ? (_mtnAddedToday + _airtelAddedToday) : 0.0);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.name, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(widget.email, style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7))),
              ]),
            ),
            IconButton(
              onPressed: widget.onToggleVisibility,
              icon: Icon(widget.maskAmount ? Icons.visibility_off : Icons.visibility),
              tooltip: widget.maskAmount ? 'Show' : 'Hide',
            ),
            IconButton(onPressed: _fetchAllocations, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
            IconButton(onPressed: _inspectRaw, icon: const Icon(Icons.info_outline), tooltip: 'Inspect raw'),
          ]),
          const SizedBox(height: 12),
          Text('OPENING FROM ZANACO — ZANACO ALLOCATION',
              style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Opening Balance', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            const SizedBox(width: 12),
            if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_loading) const SizedBox(width: 8),
            Text('ZMW ${_maskOrFormat(widget.zanacoAllocation)}',
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Allocations At', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('MTN', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('AIRTEL', style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                Text('Time ${_maskOrFormat(totalToday)}', style: tt.bodyMedium),
                const SizedBox(width: 8),
                if (_lastUpdated != null) Text(DateFormat.Hm().format(_lastUpdated!.toLocal()), style: tt.bodySmall),
              ]),
              const SizedBox(height: 6),
              Text('ZMW ${_maskOrFormat(displayMtn)}', style: tt.bodyMedium),
              const SizedBox(height: 6),
              Text('ZMW ${_maskOrFormat(displayAirtel)}', style: tt.bodyMedium),
            ]),
          ]),
          const SizedBox(height: 8),
          if (_lastUpdated != null)
            Text('Last updated: ${DateFormat.yMMMd().add_jm().format(_lastUpdated!.toLocal())}',
                style: tt.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7))),
        ]),
      ),
    );
  }
}
