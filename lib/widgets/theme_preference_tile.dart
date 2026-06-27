import 'package:daml/theme/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ThemePreferenceTile extends StatelessWidget {
  const ThemePreferenceTile({super.key});

  /// Helper function to get the display name for the current mode
  String _getModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System Default';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final themeMode = themeService.themeMode;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(
        Icons.palette_outlined,
        color: colorScheme.primary,
      ),
      title: const Text('App Theme'),
      subtitle: Text('Current: ${_getModeName(themeMode)}'),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<ThemeMode>(
          value: themeMode,
          icon: Icon(Icons.arrow_drop_down, color: colorScheme.onSurface),
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 16,
          ),
          onChanged: (ThemeMode? newValue) {
            if (newValue != null) {
              themeService.setThemeMode(newValue);
            }
          },
          items: ThemeMode.values.map<DropdownMenuItem<ThemeMode>>((ThemeMode mode) {
            return DropdownMenuItem<ThemeMode>(
              value: mode,
              child: Text(_getModeName(mode)),
            );
          }).toList(),
        ),
      ),
      onTap: () {
        // Dropdown is controlled by the trailing widget, tapping the tile does nothing
      },
    );
  }
}