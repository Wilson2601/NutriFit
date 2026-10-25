import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';

/// Round avatar: the user's own photo when there is one, otherwise their initials.
class UserAvatar extends StatelessWidget {
  final Map<String, dynamic>? user;
  final double size;
  final double fontSize;
  final Color borderColor;
  final Color textColor;
  const UserAvatar({
    super.key,
    required this.user,
    this.size = 40,
    this.fontSize = 14,
    this.borderColor = AppColors.green600,
    this.textColor = AppColors.green700,
  });

  @override
  Widget build(BuildContext context) {
    final b64 = user?['avatarB64'];
    Widget inner;
    if (b64 is String && b64.isNotEmpty) {
      inner = Image.memory(base64Decode(b64), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      inner = Center(child: Text('${user?['avatarInitials'] ?? '?'}', style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: fontSize)));
    }
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borderColor, width: size > 60 ? 3 : 1.5), color: Colors.white.withValues(alpha: 0.18)),
      child: ClipOval(child: inner),
    );
  }
}

/// Avatar for another person's payload ({initials, avatarB64}), used on coach and chat screens.
class PersonAvatar extends StatelessWidget {
  final Map<String, dynamic>? data;
  final double size;
  final double fontSize;
  final Color color;
  final Color? background;
  const PersonAvatar({super.key, required this.data, this.size = 48, this.fontSize = 15, this.color = AppColors.green700, this.background});

  @override
  Widget build(BuildContext context) {
    final b64 = data?['avatarB64'];
    final name = (data?['name'] ?? '').toString();
    final initials = (data?['initials'] ?? (name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?')).toString();
    final hasPhoto = b64 is String && b64.isNotEmpty;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2), color: background),
      child: ClipOval(
        child: hasPhoto
            ? Image.memory(base64Decode(b64), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true)
            : Center(child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: fontSize))),
      ),
    );
  }
}

/// The big profile picture. Tap it to choose a photo from the gallery, take a new one, or remove it.
class EditableAvatar extends StatefulWidget {
  const EditableAvatar({super.key});
  @override
  State<EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<EditableAvatar> {
  bool _busy = false;

  Future<void> _choose() async {
    final auth = context.read<AuthService>();
    final hasPhoto = ((auth.user?['avatarB64'] as String?) ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.of(ctx).pop('gallery')),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.of(ctx).pop('camera')),
          if (hasPhoto) ListTile(leading: const Icon(Icons.delete_outline, color: AppColors.red600), title: const Text('Remove photo'), onTap: () => Navigator.of(ctx).pop('remove')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') return _remove();
    await _pick(action == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _pick(ImageSource source) async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (file == null) return;
      setState(() => _busy = true);
      final bytes = await file.readAsBytes();
      final res = await api.uploadAvatar(auth.token!, bytes);
      auth.updateUser(res['user'] as Map<String, dynamic>);
      messenger.showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open that picture. Please try another one.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    setState(() => _busy = true);
    try {
      final res = await api.removeAvatar(auth.token!);
      auth.updateUser(res['user'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().user;
    return GestureDetector(
      onTap: _busy ? null : _choose,
      child: Stack(clipBehavior: Clip.none, children: [
        UserAvatar(user: user, size: 96, fontSize: 30, borderColor: Colors.white, textColor: Colors.white),
        if (_busy) const Positioned.fill(child: Center(child: CircularProgressIndicator(color: Colors.white))),
        Positioned(
          right: -2, bottom: -2,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.green600, width: 2)),
            child: const Icon(Icons.photo_camera, size: 16, color: AppColors.green700),
          ),
        ),
      ]),
    );
  }
}
