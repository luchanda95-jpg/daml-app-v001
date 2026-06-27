// lib/services/client_data_notifier.dart
// ChangeNotifier that exposes balances, profile and next-payment for UI reactivity.
// Also delivers pending stored notifications into the in-app NotificationService stream.

// ignore_for_file: prefer_const_declarations, curly_braces_in_flow_control_structures

import 'dart:convert';

import 'package:daml/screens/client/widgets/in_app_notification.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

class ClientDataNotifier with ChangeNotifier {
  Map<String, double> _balances = {
    'amountBorrowed': 0.0,
    'amountPaid': 0.0,
    'actualBalance': 0.0,
    'interestRate': 0.0,
  };
  Map<String, String> _profile = {};
  bool _isLoading = false;

  // NEW: next payment data (nullable)
  double? _nextPaymentAmount;
  DateTime? _nextPaymentDate;

  Map<String, double> get balances => _balances;
  Map<String, String> get profile => _profile;
  bool get isLoading => _isLoading;

  double? get nextPaymentAmount => _nextPaymentAmount;
  DateTime? get nextPaymentDate => _nextPaymentDate;

  ClientDataNotifier() {
    // Load initial data upon creation
    loadClientData();
  }

  double _toDoubleSafe(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  /// Fetches profile and balance data for the current user and delivers pending notifications.
  Future<void> loadClientData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final fetchedBalances = await AuthService.getBalancesForCurrentUser();
      final fetchedProfile = await AuthService.getLocalProfile();

      _balances = {
        'amountBorrowed': _toDoubleSafe(fetchedBalances['amountBorrowed']),
        'amountPaid': _toDoubleSafe(fetchedBalances['amountPaid']),
        'actualBalance': _toDoubleSafe(fetchedBalances['actualBalance']),
        'interestRate': _toDoubleSafe(fetchedBalances['interestRate']),
      };

      // profile is Map<String, String>
      _profile = Map<String, String>.from(fetchedProfile);

      // next payment (if present)
      _nextPaymentAmount = null;
      _nextPaymentDate = null;
      final np = await AuthService.getNextPaymentForCurrentUser();
      if (np != null) {
        if (np.containsKey('amount')) {
          _nextPaymentAmount = _toDoubleSafe(np['amount']);
        }
        if (np.containsKey('date')) {
          final d = np['date'];
          if (d is DateTime) {
            _nextPaymentDate = d;
          } else if (d is String) _nextPaymentDate = DateTime.tryParse(d);
        }
      }

      // --- NEW: fetch pending notifications and deliver them to NotificationService ---
      try {
        final pending = await AuthService.getNotificationsForCurrentUser();
        if (pending.isNotEmpty) {
          for (final n in pending) {
            final title = n['title']?.toString() ?? 'Update';
            final message = n['message']?.toString() ?? '';
            final typeStr = n['type']?.toString() ?? 'info';
            InAppNotificationType mappedType = InAppNotificationType.info;
            if (typeStr == 'success') mappedType = InAppNotificationType.success;
            if (typeStr == 'error') mappedType = InAppNotificationType.error;
            if (typeStr == 'warning') mappedType = InAppNotificationType.warning;

            // Post to in-app stream so UI can show it immediately
            try {
              NotificationService.instance.postQuick(
                title: title,
                message: message,
                type: mappedType,
                onTap: () {
                  // Optional: implement navigation callback
                },
              );
            } catch (e) {
              if (kDebugMode) print('NotificationService.postQuick failed: $e');
            }
          }

          // Clear after delivering so they are not delivered again
          await AuthService.clearNotificationsForCurrentUser();
        }
      } catch (e) {
        if (kDebugMode) print('Error delivering pending notifications: $e');
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('Error loading client data: $e');
      }
      // keep previous data on error
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Submit the agreement/form data to admin:
  /// - persist into a central 'admin_submissions' list in SharedPreferences
  /// - create a persisted notification for the overall admin (so admin UI can fetch it)
  /// - post an in-app quick notification (for any admin UI currently open)
  Future<void> submitAgreement(Map<String, dynamic> formData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profile = await AuthService.getLocalProfile();
      final fromEmail = profile['email'] ?? 'unknown';

      final now = DateTime.now();
      final submission = <String, dynamic>{
        'id': now.millisecondsSinceEpoch.toString(),
        'from': fromEmail,
        'ts': now.toIso8601String(),
        'data': formData,
      };

      // read existing submissions
      final raw = prefs.getString('admin_submissions') ?? '[]';
      List<dynamic> list;
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          list = decoded;
        } else {
          list = <dynamic>[];
        }
      } catch (_) {
        list = <dynamic>[];
      }
      list.insert(0, submission); // newest first
      await prefs.setString('admin_submissions', json.encode(list));

      // Also add a persisted notification for the overallAdminEmail (so admin can be alerted)
      try {
        final title = 'New client submission';
        final message = 'Submission from ${fromEmail.isNotEmpty ? fromEmail : 'a client'}';
        await AuthService.addNotificationForUser(
          AuthService.overallAdminEmail,
          title: title,
          message: message,
          type: 'info',
        );

        // And try to post quick in-app notification
        try {
          NotificationService.instance.postQuick(
            title: title,
            message: message,
            type: InAppNotificationType.info,
            onTap: () {
              // optional: admin navigation callback
            },
          );
        } catch (e) {
          if (kDebugMode) print('Failed to post quick notification: $e');
        }
      } catch (e) {
        if (kDebugMode) print('Failed to notify admin: $e');
      }

      // Finished — notify listeners in case UI cares
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('submitAgreement error: $e');
      rethrow;
    }
  }

  /// Helper for admin UI to clear a submission by id (mark as handled)
  Future<void> removeSubmissionById(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('admin_submissions') ?? '[]';
      List<dynamic> list;
      try {
        final decoded = json.decode(raw);
        if (decoded is List) {
          list = decoded;
        } else {
          list = <dynamic>[];
        }
      } catch (_) {
        list = <dynamic>[];
      }
      list.removeWhere((e) => e is Map && e['id'] == id);
      await prefs.setString('admin_submissions', json.encode(list));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('removeSubmissionById error: $e');
    }
  }
}
