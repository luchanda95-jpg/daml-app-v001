import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:daml/theme/app_colors.dart';
import 'package:daml/services/auth_service.dart';
import 'package:daml/services/sync_service.dart';

class ConnectivityBanner extends StatefulWidget {
  final Widget child;

  const ConnectivityBanner({super.key, required this.child});

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<dynamic>? _subscription;
  bool _offline = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkNow();
    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      _applyResult(result);
    });
  }

  Future<void> _checkNow() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _applyResult(result);
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  bool _isOfflineResult(dynamic result) {
    if (result is Iterable) {
      return result.isEmpty || result.every((e) => e == ConnectivityResult.none);
    }
    return result == ConnectivityResult.none;
  }

  void _applyResult(dynamic result) {
    if (!mounted) return;
    final wasOffline = _offline;
    final nowOffline = _isOfflineResult(result);
    setState(() {
      _offline = nowOffline;
      _checking = false;
    });
    if (wasOffline && !nowOffline) {
      _syncAfterReconnect();
    }
  }

  Future<void> _syncAfterReconnect() async {
    try {
      final role = (await AuthService.getRole() ?? '').toLowerCase();
      final shouldSyncReports = role.contains('branch') || role.contains('overall') || role.contains('ovadmin');
      if (!shouldSyncReports) return;
      await SyncService().fullSync();
    } catch (_) {
      // The user is back online; any remaining pending item will retry on the next
      // manual refresh or connectivity change. Avoid showing technical/proxy errors.
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!_checking && _offline)
          Material(
            color: AppColors.INK,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: AppColors.GREEN, size: 18),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        "You're currently offline. Reports are saved on this device and will sync automatically when you're back online.",
                        style: const TextStyle(
                          color: AppColors.WHITE,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
