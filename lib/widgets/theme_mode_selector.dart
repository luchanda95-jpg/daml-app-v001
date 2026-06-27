// lib/widgets/theme_mode_selector.dart
// A clean segmented control for choosing System / Light / Dark.
// Wired to the existing ThemeService (which already persists the choice).

// ignore_for_file: deprecated_member_use

import 'package:daml/theme/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final current = themeService.themeMode;
    final cs = Theme.of(context).colorScheme;
    final divider = Theme.of(context).dividerColor;

    const options = <_ThemeOption>[
      _ThemeOption(ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
      _ThemeOption(ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      _ThemeOption(ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.04), // subtle neutral track
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: _Segment(
                option: o,
                selected: current == o.mode,
                onTap: () => themeService.setThemeMode(o.mode),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final _ThemeOption option;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurface.withOpacity(0.7);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(option.icon, size: 22, color: fg),
            const SizedBox(height: 4),
            Text(
              option.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption {
  final ThemeMode mode;
  final IconData icon;
  final String label;
  const _ThemeOption(this.mode, this.icon, this.label);
}
