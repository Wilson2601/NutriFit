import 'dart:async';

import 'package:flutter/material.dart';
import '../services/in_app_notifier.dart';
import '../widgets/user_avatar.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// One chat thread between a coach and a client.
/// - A client opens it without arguments (their own thread).
/// - A coach opens it with the client's id.
class ChatScreen extends StatefulWidget {
  final String? clientId;
  const ChatScreen({super.key, this.clientId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String _title = 'Chat';
  String? _error;
  bool _loading = true;
  bool _sending = false;
  Timer? _poll;

  late final String _clientId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    _myUid = (auth.user?['uid'] ?? '') as String;
    _clientId = widget.clientId ?? _myUid;
    _title = auth.role == 'coach' ? 'Client' : 'My Coach';
    _notifier.activeChatClientId = _clientId;
    _notifier.markChatRead(_clientId);
    _load(initial: true);
    // Simple polling keeps the thread fresh while the screen is open.
    // Push notifications cover the case when the app is in the background.
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _notifier.activeChatClientId = null;
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _peer;
  late final InAppNotifier _notifier = context.read<InAppNotifier>();

  Future<void> _load({bool initial = false}) async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    if (auth.token == null) return;
    try {
      final data = await api.chatThread(auth.token!, _clientId);
      final list = (data['messages'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final changed = list.length != _messages.length;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
        if (auth.role == 'coach') {
          _title = data['client']['name'] as String;
          _peer = Map<String, dynamic>.from(data['client'] as Map);
        }
      });
      if (changed) {
        _scrollToEnd();
        // Fire and forget: mark incoming messages as read.
        api.markChatRead(auth.token!, _clientId).catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      // Keep showing old messages on a transient polling error; only surface the first failure.
      if (initial) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    setState(() => _sending = true);
    try {
      final res = await api.sendChatMessage(auth.token!, _clientId, text);
      _controller.clear();
      setState(() => _messages = [..._messages, res['message'] as Map<String, dynamic>]);
      _scrollToEnd();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final isCoach = context.read<AuthService>().role == 'coach';
    final accent = isCoach ? AppColors.blue600 : AppColors.green600;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Row(children: [
          if (_peer != null) ...[PersonAvatar(data: _peer, size: 34, fontSize: 12, color: AppColors.blue600), const SizedBox(width: 10)],
          Flexible(child: Text(_title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: AppColors.red600))))
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                isCoach ? 'No messages yet. Say hello to your client.' : 'No messages yet. Ask your coach anything about your plan.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.all(16),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final mine = m['senderId'] == _myUid;
                              return Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: mine ? accent : Colors.white,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(mine ? 16 : 4),
                                      bottomRight: Radius.circular(mine ? 4 : 16),
                                    ),
                                    border: mine ? null : Border.all(color: const Color(0xFFDFE6DB)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(m['text'] as String, style: TextStyle(color: mine ? Colors.white : AppColors.ink, fontSize: 14.5)),
                                      const SizedBox(height: 3),
                                      Text(_time(m['createdAt'] as String),
                                          style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : AppColors.muted)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.paper,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: accent),
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send_rounded, size: 20),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
