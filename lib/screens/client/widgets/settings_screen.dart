// lib/screens/client/widgets/settings_screen.dart
import 'package:daml/widgets/theme_mode_selector.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final Future<void> Function()? onSignOut;

  const SettingsScreen({super.key, this.onSignOut});

  void _showAction(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action tapped!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      // No colour overrides here — the global appBarTheme handles light/dark
      // (white bar + dark text in light mode, black bar + white text in dark).
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Appearance ---
            _sectionHeader(theme, 'Appearance'),
            const SizedBox(height: 4),
            const ThemeModeSelector(),
            const SizedBox(height: 12),
            const Divider(),

            // --- Account Summary Section ---
            _sectionHeader(theme, 'Self-Care Information'),
            ListTile(
              leading: Icon(Icons.account_balance_wallet_outlined,
                  color: cs.onSurface),
              title: const Text('Loan Usage Guide'),
              subtitle: const Text(
                  'How to view balances and submit new requests'),
              onTap: () => _showAction(context, 'Usage Guide'),
            ),

            const Divider(),

            // --- Legal & Compliance Section ---
            _sectionHeader(theme, 'Legal & Compliance'),
            ListTile(
              leading: Icon(Icons.gavel_outlined, color: cs.onSurface),
              title: const Text('Terms of Service'),
              subtitle:
                  const Text('Loan request process and approval disclosure'),
              onTap: () => _showInfoDialog(
                context,
                'Terms of Service',
                'By using this app, you acknowledge that loan applications submitted via the self-care portal are requests only. Requests are exported via CSV for manual management review. Submission does not guarantee approval.',
              ),
            ),
            ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: cs.onSurface),
              title: const Text('Privacy Policy'),
              subtitle:
                  const Text('How we handle your financial and personal data'),
              onTap: () => _showInfoDialog(
                context,
                'Privacy Policy',
                'We collect personal identification and financial data solely to facilitate loan requests. Your data is encrypted and shared only with authorized management for the purpose of credit assessment.',
              ),
            ),
            ListTile(
              leading: Icon(Icons.help_outline, color: cs.onSurface),
              title: const Text('Support'),
              subtitle:
                  const Text('Contact management regarding your loan status'),
              onTap: () => _showAction(context, 'Support'),
            ),

            const SizedBox(height: 32),

            // --- Logout Button (theme-consistent / monochrome) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: theme.dividerColor),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (onSignOut != null) {
                      try {
                        await onSignOut!();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')));
                        }
                        return;
                      }
                    }
                    if (context.mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                          '/signin', (route) => false);
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 40),
            Center(
              child: Text(
                'Direct Access Loan Manager v1.0.2',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// Shared section-header (replaces the 3 duplicated Padding+Text blocks).
  Widget _sectionHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, left: 16.0, bottom: 8.0),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
