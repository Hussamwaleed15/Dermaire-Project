import 'package:flutter/material.dart';
import '../capture/capture_history_models.dart';
import '../capture/private_capture_image.dart';
import 'plan_models.dart';
import 'plan_controller.dart';

class PlanImages {
  PlanImages(this.controller, this.plan) {
    images = PrivateCaptureImages(
      controller.api,
      reader: read,
      authorization: (_) => active,
      scope: controller,
    );
  }
  final PlanController controller;
  final ClinicalPlan plan;
  late final PrivateCaptureImages images;
  bool get active =>
      controller.current &&
      !controller.busy &&
      controller.value?.id == plan.id &&
      controller.value?.revision == plan.revision;
  bool same(ClinicalPlan current) =>
      current.id == plan.id &&
      current.patient == plan.patient &&
      current.doctor == plan.doctor &&
      current.grant == plan.grant &&
      current.revision == plan.revision &&
      current.baseline == plan.baseline &&
      current.followup == plan.followup;
  Future<PrivateImageBytes> read(String id, int generation) async {
    bool allowed() =>
        active &&
        generation == controller.generation &&
        [plan.baseline, plan.followup].contains(id);
    try {
      if (!allowed() || !same(await controller.read()) || !allowed()) {
        throw const FormatException('Plan image authority changed');
      }
      final bytes = controller.role == 'doctor'
          ? await controller.api.readDoctorCaptureImage(
              id,
              generation,
              scope: controller,
              active: allowed,
            )
          : await controller.api.readPrivateCaptureImage(id, generation);
      // The image endpoint alone accepts any current VIEW grant. Re-read the
      // original plan after bytes arrive before allowing decoding/display.
      if (!allowed() || !same(await controller.read()) || !allowed()) {
        throw const FormatException('Original plan authority changed');
      }
      return bytes;
    } catch (e) {
      if (controller.current) {
        controller.invalidateEvidence();
      }
      rethrow;
    }
  }

  void dispose() => images.dispose();
}

class PlanImagePanel extends StatefulWidget {
  const PlanImagePanel({
    super.key,
    required this.controller,
    required this.plan,
  });
  final PlanController controller;
  final ClinicalPlan plan;
  @override
  State<PlanImagePanel> createState() => _PlanImagePanelState();
}

class _PlanImagePanelState extends State<PlanImagePanel> {
  late final access = PlanImages(widget.controller, widget.plan);
  @override
  void dispose() {
    access.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Private plan images · visual records, not a medical assessment',
      ),
      if (widget.plan.baseline != null) ...[
        const Text('Baseline'),
        PrivateCaptureImage(
          id: widget.plan.baseline!,
          generation: widget.controller.generation,
          stored: true,
          viewer: true,
          images: access.images,
        ),
      ],
      if (widget.plan.followup != null) ...[
        const Text('Follow-up'),
        PrivateCaptureImage(
          id: widget.plan.followup!,
          generation: widget.controller.generation,
          stored: true,
          viewer: true,
          images: access.images,
        ),
      ] else
        const Text('Awaiting a server-associated follow-up capture.'),
      const Text(
        'Image appearance depends on capture conditions. No diagnosis or improvement percentage is inferred.',
      ),
    ],
  );
}
