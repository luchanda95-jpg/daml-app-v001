// lib/screens/client/widgets/profile_screen.dart
// UI-only Profile screen — removed LocalStorage side-effects.

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:daml/screens/sign_in_screen.dart';

class ProfileScreen extends StatelessWidget {
  final String username;

  const ProfileScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          _buildProfileHeader(theme),
          const SizedBox(height: 20),
          _buildSettingsCard(theme),
          const SizedBox(height: 18),
          _buildLogoutButton(context),
          const SizedBox(height: 12),
          Text(
            'Signed in as $username',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: Column(
            children: [
              Text(
                username,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Administrator',
                  style: TextStyle(
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Manage account settings and view help resources.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
        const Positioned(
          top: -40,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blueAccent,
              child: Icon(Icons.person, size: 42, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsCard(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Sync History'),
            subtitle: const Text('View recent sync events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          Divider(height: 1, color: theme.dividerColor),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Help & Support'),
            subtitle: const Text('Report an issue or get help'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        onPressed: () async {
          // UI-only: do not clear persistent session here. Just navigate to sign-in.
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logged out (UI-only)')));
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const SignInScreen()),
            (Route<dynamic> route) => false,
          );
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Colors.redAccent),
          foregroundColor: Colors.redAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
