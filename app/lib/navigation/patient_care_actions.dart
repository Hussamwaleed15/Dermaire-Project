import 'package:flutter/material.dart';
import '../agent/server_agent_ui.dart';
import '../doctor/patient_access.dart';
import '../notifications/inbox_ui.dart';
import '../messaging/messaging_ui.dart';
import '../plans/plan_ui.dart';
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../services/api_service.dart';

class PatientCareActions extends StatelessWidget {
  const PatientCareActions({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) {
    final api = ApiService.instance,
        generation = ApiService.instance.sessionGeneration;
    Future<void> visit(Widget page) async {
      if (!api.isCurrentSession(generation) ||
          !api.canReadPatientClinicalStatus) {
        return;
      }
      await openPage(context, page);
      if (!context.mounted || !api.isCurrentSession(generation)) return;
      await state.refreshPatientHome(generation: generation);
    }

    return ExpansionTile(
      key: const Key('homeConnectedCare'),
      title: const Text('Connected care'),
      subtitle: const Text('Conversations, plans and sharing permissions'),
      children: [
        ListTile(
          leading: const Icon(Icons.forum_outlined),
          title: const Text('Care conversations'),
          onTap: () => visit(const CareThreadsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('Follow-ups & comparison plans'),
          onTap: () => visit(ClinicalPlansScreen(state: state)),
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('Doctor access'),
          onTap: () => visit(const PatientAccessScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notification inbox'),
          onTap: () => visit(NotificationInboxScreen(state: state)),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Agent sessions & requests'),
          onTap: () => visit(const ServerAgentScreen()),
        ),
      ],
    );
  }
}
