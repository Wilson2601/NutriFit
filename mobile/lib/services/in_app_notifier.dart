import 'dart:async';
import 'package:flutter/material.dart';
import '../app_keys.dart';
import '../theme.dart';
import 'api_service.dart';

/// Polls the server's in-app notification feed. It shows a banner for every new notification and keeps the
/// unread counters for the bell and the Messages tab. It works even when browser/phone push is blocked.
class InAppNotifier extends ChangeNotifier {
  final ApiService api;
  InAppNotifier(this.api);

  Timer? _timer;
  String? _token;
  String _role = 'user';
  String? _lastSeen; // createdAt of the newest notification already handled
  bool _busy = false;

  List<Map<String, dynamic>> items = [];
  int unread = 0;

  /// The chat thread currently on screen; its banners are skipped because the messages are visible anyway.
  String? activeChatClientId;

  int get chatUnread => items.where((n) => n['read'] != true && n['type'] == 'chat').length;

  void start(String token, String role) {
    if (_token == token && _timer != null) return;
    stop();
    _token = token;
    _role = role;
    _lastSeen = null;
    _poll(first: true);
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _token = null;
    items = [];
    unread = 0;
    _lastSeen = null;
    notifyListeners();
  }

  Future<void> refresh() => _poll();

  Future<void> _poll({bool first = false}) async {
    final token = _token;
    if (token == null || _busy) return;
    _busy = true;
    try {
      final res = await api.notifications(token);
      final list = (res['items'] as List).cast<Map<String, dynamic>>();
      final newest = list.isEmpty ? null : list.first['createdAt'] as String?;
      if (first || _lastSeen == null) {
        _lastSeen = newest ?? '';
      } else {
        final fresh = list.where((n) => (n['createdAt'] as String).compareTo(_lastSeen!) > 0 && n['read'] != true).toList().reversed;
        for (final n in fresh) {
          final isOpenChat = n['type'] == 'chat' && (n['data']?['clientId'] ?? '') == activeChatClientId;
          if (isOpenChat) {
            _markRead([n['id'] as String]);
          } else {
            _banner(n);
          }
        }
        if (newest != null && newest.compareTo(_lastSeen!) > 0) _lastSeen = newest;
      }
      items = list;
      unread = (res['unread'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {
      // Offline or server restarting: try again on the next tick.
    } finally {
      _busy = false;
    }
  }

  void _banner(Map<String, dynamic> n) {
    final route = routeFor(n);
    messengerKey.currentState?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((n['title'] ?? '') as String, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (((n['body'] ?? '') as String).isNotEmpty) Text(n['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      action: route == null
          ? null
          : SnackBarAction(
              label: 'Open',
              textColor: AppColors.green100,
              onPressed: () {
                messengerKey.currentState?.hideCurrentSnackBar();
                navigatorKey.currentState?.pushNamed(route);
                _markRead([n['id'] as String]);
              },
            ),
    ));
  }

  /// Where tapping a notification should go (null = nowhere).
  String? routeFor(Map<String, dynamic> n) {
    final clientId = (n['data']?['clientId'] ?? '') as String;
    final type = n['type'];
    if (_role == 'coach' && clientId.isNotEmpty) {
      if (type == 'chat') return '/chat/$clientId';
      if (type == 'meal_logged' || type == 'mission_passed') return '/coach/clients/$clientId';
    }
    if (_role != 'coach') {
      if (type == 'chat') return '/chat';
      if (type == 'targets_updated') return '/nutrition';
      if (type == 'mission_passed') return '/mission';
    }
    return null;
  }

  Future<void> _markRead(List<String> ids) async {
    final token = _token;
    if (token == null || ids.isEmpty) return;
    for (final n in items) {
      if (ids.contains(n['id'])) n['read'] = true;
    }
    unread = items.where((n) => n['read'] != true).length;
    notifyListeners();
    try {
      await api.markNotificationsRead(token, ids: ids);
    } catch (_) {}
  }

  Future<void> markRead(Map<String, dynamic> n) => _markRead([n['id'] as String]);

  Future<void> markAllRead() async {
    final token = _token;
    if (token == null) return;
    for (final n in items) {
      n['read'] = true;
    }
    unread = 0;
    notifyListeners();
    try {
      await api.markNotificationsRead(token);
    } catch (_) {}
  }

  /// Called when a chat thread is opened: its chat notifications are read by definition.
  Future<void> markChatRead(String clientId) => _markRead([
        for (final n in items)
          if (n['read'] != true && n['type'] == 'chat' && (n['data']?['clientId'] ?? '') == clientId) n['id'] as String
      ]);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
