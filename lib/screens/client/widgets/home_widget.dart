// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:daml/screens/client/widgets/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:daml/services/api_service.dart';
import 'package:daml/screens/client/widgets/in_app_notification.dart';

class HomeWidget extends StatefulWidget {
  final String title;
  final VoidCallback? onBellPressed;
  final VoidCallback? onSettingsPressed; // Removed onProfilePressed
  final double height;

  final Color? backgroundColor;
  final Color? borderColor;

  final double titleFontSize;
  final double topPadding;
  final double titleRowHeight;

  final String? notificationsEmail;
  final Duration pollInterval;

  const HomeWidget({
    super.key,
    this.title = 'Direct Access',
    this.onBellPressed,
    this.onSettingsPressed,
    this.height = 100.0,
    this.backgroundColor,
    this.borderColor,
    this.titleFontSize = 15.0,
    this.topPadding = 32.0,
    this.titleRowHeight = 32.0,
    this.notificationsEmail,
    this.pollInterval = const Duration(seconds: 10), required Null Function() onProfilePressed,
  });

  @override
  State<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  late final StreamSubscription<InAppNotificationModel> _sub;
  final List<InAppNotificationModel> _notifications = [];
  final Set<String> _seenIds = <String>{};
  int _unreadCount = 0;
  Timer? _pollTimer;
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    _sub = NotificationService.instance.stream.listen((n) {
      if (!mounted) return;
      if (n.id.trim().isNotEmpty && _seenIds.contains(n.id)) return;
      if (n.id.trim().isNotEmpty) _seenIds.add(n.id);

      setState(() {
        _notifications.add(n);
        _unreadCount++;
      });
      _showQuickBanner(n);
    });

    final email = widget.notificationsEmail?.trim();
    if (email != null && email.isNotEmpty) {
      _pullFromServer();
      _pollTimer = Timer.periodic(widget.pollInterval, (_) => _pullFromServer());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _sub.cancel();
    super.dispose();
  }

  void _showQuickBanner(InAppNotificationModel n) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${n.title}: ${n.message}'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () {
            n.onTap?.call();
            _openNotificationsSheet();
          },
        ),
      ),
    );
  }

  Future<void> _pullFromServer() async {
    if (_pulling) return;
    final email = widget.notificationsEmail?.trim();
    if (email == null || email.isEmpty) return;
    _pulling = true;
    try {
      final list = await ApiService.fetchUnreadNotifications(email);
      if (!mounted || list.isEmpty) return;
      int added = 0;
      for (final m in list) {
        final id = (m['_id'] ?? m['id'] ?? '').toString().trim();
        if (id.isEmpty || _seenIds.contains(id)) continue;
        _seenIds.add(id);
        
        final typeStr = (m['type'] ?? 'info').toString().toLowerCase();
        InAppNotificationType t = InAppNotificationType.info;
        if (typeStr == 'success') t = InAppNotificationType.success;
        if (typeStr == 'warning') t = InAppNotificationType.warning;
        if (typeStr == 'error') t = InAppNotificationType.error;

        _notifications.add(
          InAppNotificationModel(
            id: id,
            title: (m['title'] ?? 'Update').toString(),
            message: (m['message'] ?? '').toString(),
            type: t,
          ),
        );
        added++;
      }
      if (added > 0 && mounted) {
        setState(() => _unreadCount += added);
        try { await ApiService.markAllNotificationsRead(email); } catch (_) {}
      }
    } catch (_) {} finally { _pulling = false; }
  }

  Future<void> _openNotificationsSheet() async {
    widget.onBellPressed?.call();
    await _pullFromServer();
    if (_unreadCount > 0) setState(() => _unreadCount = 0);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
                Row(
                  children: [
                    Text('Notifications', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(onPressed: () { setState(() => _notifications.clear()); Navigator.pop(ctx); }, child: const Text('Clear all')),
                  ],
                ),
                if (_notifications.isEmpty)
                   const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('No notifications', style: TextStyle(fontWeight: FontWeight.w700)))
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (c, i) {
                        final n = _notifications[_notifications.length - 1 - i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _leadingForType(n.type, theme),
                          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(n.message),
                          onTap: () { n.onTap?.call(); Navigator.pop(ctx); },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _leadingForType(InAppNotificationType t, ThemeData theme) {
    switch (t) {
      case InAppNotificationType.success: return Icon(Icons.check_circle_outline, color: theme.colorScheme.primary);
      case InAppNotificationType.error: return Icon(Icons.error_outline, color: theme.colorScheme.error);
      case InAppNotificationType.warning: return const Icon(Icons.warning_amber_outlined, color: Colors.orange);
      case InAppNotificationType.info: return Icon(Icons.info_outline, color: theme.colorScheme.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        // Blend with the surface so the header adapts to light/dark
        // (was cs.primary, which turned into a white strip in dark mode).
        color: widget.backgroundColor ?? cs.surface,
        border: Border(bottom: BorderSide(color: widget.borderColor ?? theme.dividerColor)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.0, widget.topPadding, 20.0, 0),
          child: Row(
            children: [
              Expanded(child: Text(widget.title, style: TextStyle(color: cs.onSurface, fontSize: widget.titleFontSize, fontWeight: FontWeight.bold))),
              
              // Notification Bell
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: _openNotificationsSheet,
                    icon: const Icon(Icons.notifications_none),
                    color: cs.onSurface,
                  ),
                  if (_unreadCount > 0)
                    Positioned(
                      right: 4, top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.surface)),
                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                        child: Center(child: Text('$_unreadCount', style: TextStyle(color: cs.onPrimary, fontSize: 10))),
                      ),
                    ),
                ],
              ),

              // Settings Only Overflow
              PopupMenuButton<int>(
                icon: Icon(Icons.more_vert, color: cs.onSurface),
                color: theme.cardColor,
                onSelected: (v) {
                  if (v == 1) {
                    if (widget.onSettingsPressed != null) {
                      widget.onSettingsPressed!.call();
                    } else {
                      Navigator.of(context).push(MaterialPageRoute(builder: (c) => const SettingsScreen()));
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 1,
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, size: 18, color: cs.onSurface),
                        const SizedBox(width: 10),
                        Text('Settings', style: TextStyle(color: cs.onSurface)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}