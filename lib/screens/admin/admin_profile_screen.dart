// ignore_for_file: unintended_html_in_doc_comment

import 'package:flutter/material.dart';

class AdminProfileScreen extends StatefulWidget {
  /// Optional initial profile provided by the parent.
  /// Example: {'name': 'Alice', 'email': 'a@x.com', 'phone': '+260...', 'role': 'admin'}
  final Map<String, String>? profile;

  /// Optional callback the parent can provide to refresh/fetch a profile.
  /// If provided, the widget will call it when the user taps the refresh button.
  /// The callback must return a Map<String,String> representing the profile.
  final Future<Map<String, String>> Function()? onRefresh;

  const AdminProfileScreen({
    super.key,
    this.profile,
    this.onRefresh,
  });

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  Map<String, String> _profile = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Use provided profile (no backend access here)
    _profile = widget.profile ?? {};
    _isLoading = false;
  }

  Future<void> _refreshProfile() async {
    if (widget.onRefresh == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No refresh handler provided — profile is local only.')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fetched = await widget.onRefresh!();
      setState(() {
        _profile = fetched;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to refresh profile: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Admin Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProfile,
            tooltip: 'Refresh profile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Center(
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Admin Role: ${_profile['role']?.toUpperCase() ?? 'N/A'}',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.person),
                          title: const Text('Name'),
                          subtitle: Text(_profile['name'] ?? 'Not set'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.email),
                          title: const Text('Email'),
                          subtitle: Text(_profile['email'] ?? 'N/A'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.phone),
                          title: const Text('Phone'),
                          subtitle: Text(_profile['phone'] ?? 'Not set'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
