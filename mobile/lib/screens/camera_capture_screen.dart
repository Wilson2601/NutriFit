import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// What the capture screen hands back to the caller.
class CapturedPhoto {
  final Uint8List bytes;
  final DateTime capturedAt;
  const CapturedPhoto(this.bytes, this.capturedAt);
}

/// Live camera only. There is deliberately no gallery or file picker anywhere
/// in this flow, so a meal photo can only come from the camera at this moment.
class CameraCaptureScreen extends StatefulWidget {
  final String mealName;
  const CameraCaptureScreen({super.key, required this.mealName});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;
  Uint8List? _shot;
  DateTime? _shotAt;

  @override
  void initState() {
    super.initState();
    _startCamera();
  }

  Future<void> _startCamera() async {
    setState(() => _error = null);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera was found on this device.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(back, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (e) {
      setState(() => _error = _friendly(e));
    } catch (e) {
      setState(() => _error = 'Could not start the camera: $e');
    }
  }

  String _friendly(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is blocked. Allow camera permission for this app (or site) and try again.';
      default:
        return 'Camera error: ${e.description ?? e.code}';
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      setState(() {
        _shot = bytes;
        _shotAt = DateTime.now();
      });
    } on CameraException catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Photo: ${widget.mealName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 56),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _startCamera, child: const Text('Try again')),
          ]),
        ),
      );
    }

    if (_shot != null) {
      return Column(children: [
        Expanded(child: Center(child: Image.memory(_shot!, fit: BoxFit.contain))),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: () => setState(() { _shot = null; _shotAt = null; }),
                child: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(CapturedPhoto(_shot!, _shotAt!)),
                child: const Text('Use photo'),
              ),
            ),
          ]),
        ),
      ]);
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Column(children: [
      Expanded(child: Center(child: CameraPreview(controller))),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(children: [
          const Text('Place your finished meal in the frame', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 74, height: 74,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.white38 : AppColors.green500),
                ),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }
}
