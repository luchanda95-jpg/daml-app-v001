// lib/screens/branch/branch_home_loader.dart
import 'package:flutter/material.dart';
import 'package:daml/widgets/app_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auth_service.dart';
import 'home.dart'; // BranchAdminHomeScreen(branchName: ...)

class BranchHomeLoader extends StatefulWidget {
  const BranchHomeLoader({super.key});

  @override
  State<BranchHomeLoader> createState() => _BranchHomeLoaderState();
}

class _BranchHomeLoaderState extends State<BranchHomeLoader> {
  String? _branchName;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranch();
  }

  Future<void> _loadBranch() async {
    try {
      final b = await _resolveBranchName();
      if (!mounted) return;

      final cleaned = (b ?? '').trim();
      if (cleaned.isEmpty) {
        setState(() => _error = "Branch name not found. Please sign in again.");
        return;
      }

      setState(() => _branchName = cleaned);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<String?> _resolveBranchName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // 1) Try common preference keys
    const keys = [
      'branchName',
      'branch_name',
      'branch',
      'branchId',
      'branch_id',
    ];

    for (final k in keys) {
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }

    // 2) Try local profile saved by AuthService
    final profile = await AuthService.getLocalProfile();
    final possible = [
      profile['branchName'],
      profile['branch_name'],
      profile['branch'],
      profile['branchId'],
      profile['branch_id'],
    ];

    for (final v in possible) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }

    // 3) Fallback: derive from branch admin email (monze@directaccess.com -> Monze)
    final email = (profile['email'] ?? '').toString().trim().toLowerCase();
    if (email.contains('@')) {
      final local = email.split('@').first.trim();
      if (local.isNotEmpty) {
        // map known branches nicely
        const map = {
          'monze': 'Monze',
          'mazabuka': 'Mazabuka',
          'lusaka': 'Lusaka',
          'solwezi': 'Solwezi',
          'lumezi': 'Lumezi',
          'nakonde': 'Nakonde',
          'mbala': 'Mbala',   // ✅ added
          'kitwe': 'Kitwe',   // ✅ added
        };

        return map[local] ?? _titleCase(local);
      }
    }

    return null;
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Branch")),
        body: Center(child: Text("Branch load error: $_error")),
      );
    }

    if (_branchName == null) {
      return const Scaffold(body: AppPageSkeleton());
    }

    return BranchAdminHomeScreen(branchName: _branchName!);
  }
}
