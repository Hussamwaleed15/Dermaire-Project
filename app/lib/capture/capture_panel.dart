import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'capture_controller.dart';
import 'photo_disclosure.dart';

class CapturePanel extends StatefulWidget {
  const CapturePanel({super.key, this.controller});
  final CaptureController? controller;
  @override
  State<CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends State<CapturePanel> {
  late final CaptureController controller;
  Uint8List? image;
  bool picking = false;
  int selectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        CaptureController(ApiService.instance.submitCapture);
    controller.addListener(changed);
    ApiService.instance.addListener(sessionChanged);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void sessionChanged() {
    if (!ApiService.instance.isAuthenticated) {
      selectionGeneration++;
      image = null;
      controller.retake();
    }
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(sessionChanged);
    controller.removeListener(changed);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final generation = ++selectionGeneration;
    controller.retake();
    setState(() {
      image = null;
      picking = true;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (file == null || !mounted || generation != selectionGeneration) return;
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (!mounted || generation != selectionGeneration) return;
        if (buffer.length + chunk.length > 8 * 1024 * 1024) {
          throw const FormatException('Image too large');
        }
        buffer.add(chunk);
      }
      final bytes = buffer.takeBytes();
      if (!mounted || generation != selectionGeneration) return;
      setState(() => image = bytes);
      await controller.check(bytes, file.name);
    } catch (_) {
      if (mounted) {
        controller.selectionFailed();
        setState(() => image = null);
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> history() async {
    final generation = selectionGeneration;
    try {
      final rows = await ApiService.instance.getCaptureHistory();
      if (!mounted || generation != selectionGeneration) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recent capture history'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: rows.isEmpty
                    ? [const Text('No captures recorded.')]
                    : rows
                          .map(
                            (row) => ListTile(
                              title: Text(
                                '${row['state']} • ${row['received_at']}',
                              ),
                              subtitle: Text(
                                row['storage'] == 'azure_blob'
                                    ? 'Image stored'
                                    : 'Image not stored',
                              ),
                            ),
                          )
                          .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture history unavailable. Please retry.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Guided photo capture',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const Text(
        'Take an upright front photo, then choose it here. Center your whole face, keep both eyes visible, hold still, and use soft even light. Keep the same distance and lighting each time. No live camera analysis is available.',
      ),
      if (image != null)
        Image.memory(
          image!,
          height: 220,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('Preview unavailable'),
        ),
      Text(switch (controller.phase) {
        CapturePhase.ready =>
          'Ready — choose a photo for server quality checking.',
        CapturePhase.checking => 'Checking quality on the server…',
        CapturePhase.accepted =>
          controller.record?['storage'] == 'azure_blob'
              ? 'Accepted by the quality gate. Image stored on the server.'
              : 'Accepted by the quality gate. Image was not stored; image storage is unavailable.',
        CapturePhase.rejected => 'Rejected — retake with the guidance below.',
        CapturePhase.failure => controller.error ?? 'Quality checking failed.',
      }),
      for (final reason in controller.reasons) Text(reason),
      const Text(
        'Photo checks and any image estimates are not a diagnosis. Rejected images are not retained.',
      ),
      const Text(photoUploadDisclosure),
      FilledButton(
        onPressed: picking || controller.phase == CapturePhase.checking
            ? null
            : pick,
        child: Text(
          controller.phase == CapturePhase.ready
              ? 'Choose photo and check quality'
              : 'Retake / choose another photo',
        ),
      ),
      TextButton(onPressed: history, child: const Text('View capture history')),
    ],
  );
}
