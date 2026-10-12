import 'package:flutter/material.dart';
import 'chatbot.dart';
import 'clinical/clinical_ui.dart';
import 'home/patient_home.dart';
import 'observations/observation_ui.dart';
import 'account/account_summary.dart';
import 'experiments/experiment_ui.dart';
import 'onboarding_screens.dart';
import 'dermaire_state.dart';
import 'dermaire_theme.dart';
import 'dermaire_widgets.dart';
import 'products/products_ui.dart';
import 'services/api_service.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state});
  final DermaireState state;

  static const labels = [
    'Home',
    'Experiment',
    'Products',
    'Rewards',
    'Reports',
    'Profile',
  ];
  static const icons = [
    Icons.home_rounded,
    Icons.science_rounded,
    Icons.spa_rounded,
    Icons.redeem_rounded,
    Icons.analytics_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) {
      final pages = [
        HomeTab(state: state),
        ExperimentTab(state: state),
        ProductsFeatureTab(state: state),
        RewardsTab(state: state),
        ReportsTab(state: state),
        ProfileTab(state: state),
      ];
      return Scaffold(
        body: IndexedStack(index: state.selectedTab, children: pages),
        floatingActionButton: FloatingActionButton.small(
          tooltip: 'Open Dermaire guide',
          onPressed: () => openPage(context, const SkinAssistantScreen()),
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: state.selectedTab,
          onTap: state.selectTab,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: .38),
          selectedFontSize: 9.5,
          unselectedFontSize: 9,
          selectedLabelStyle: const TextStyle(
            fontFamily: 'Karla',
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(fontFamily: 'Karla'),
          items: List.generate(
            labels.length,
            (index) => BottomNavigationBarItem(
              icon: Icon(icons[index], size: 21),
              label: labels[index],
            ),
          ),
        ),
      );
    },
  );
}

class _TabPage extends StatelessWidget {
  const _TabPage({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      children: children,
    ),
  );
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) => PatientHome(
    key: ValueKey(ApiService.instance.sessionGeneration),
    state: state,
  );
}

class ExperimentTab extends StatelessWidget {
  const ExperimentTab({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) => ExperimentsView(controller: state.experiments, header: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
      Text('${state.baseline.completedDays ?? 'Unknown'} of 5 days'),
      if (state.baseline.error != null) Text(state.baseline.error!),
      OutlinedButton(onPressed: state.baseline.loading ? null : state.baseline.refresh, child: const Text('Refresh baseline')),
      ExpansionTile(title: const Text('Personal baseline'), children: [
        const Text('The baseline feature uses five confirmed UTC days. Each experiment freezes its own recent comparison window.'),
        for (final metric in state.baseline.metrics.entries) Text('${metric.key}: mean ${metric.value['mean']}, standard deviation ${metric.value['standard_deviation']}'),
        TextButton(onPressed: () => openPage(context, CameraScreen(state: state)), child: const Text('Record a check-in')),
      ]),
    ])));
}

class RewardsTab extends StatelessWidget {
  const RewardsTab({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) => const _TabPage(
    children: [
      Eyebrow('Rewards'),
      Notice(
        icon: '🪙',
        text: 'Rewards are not available. Products and check-ins do not currently earn redeemable tokens.',
      ),
    ],
  );
}

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) =>
      ExperimentsView(controller: state.experiments);
}

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Experiment results')),
    body: ExperimentsView(controller: state.experiments),
  );
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) => ResultsScreen(state: state);
}

class DoctorAccessScreen extends StatelessWidget {
  const DoctorAccessScreen({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => DermairePage(
      eyebrow: 'Doctor access',
      title: state.doctorLinkActive ? 'Scan to view report' : 'Access revoked',
      children: [
        if (state.doctorLinkActive) ...[
          Center(
            child: Container(
              width: 156,
              height: 156,
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DermaireColors.paper,
                border: Border.all(color: DermaireColors.caramel),
              ),
              child: const _QrPattern(),
            ),
          ),
          const DermaireCard(
            color: DermaireColors.card,
            child: Column(
              children: [
                Text(
                  'Valid for 7 days',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text('Expires Apr 29, 2025', style: TextStyle(fontSize: 11.5)),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: DermaireColors.conflict,
              side: const BorderSide(color: DermaireColors.conflict),
            ),
            onPressed: state.revokeDoctorLink,
            child: const Text('Revoke access'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () =>
                showDermaireSnack(context, 'Report prepared for export'),
            child: const Text('Export report'),
          ),
          const SizedBox(height: 14),
          const Text(
            'No login required — your doctor opens this on any browser.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5),
          ),
        ] else ...[
          const SizedBox(height: 24),
          const Center(
            child: Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: DermaireColors.conflict,
            ),
          ),
          const SizedBox(height: 18),
          const Notice(
            icon: '✓',
            text: 'The previous link can no longer be used.',
            color: DermaireColors.safeBackground,
          ),
        ],
      ],
    ),
  );
}

class _QrPattern extends StatelessWidget {
  const _QrPattern();
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _QrPainter(), child: const SizedBox.expand());
}

class _QrPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = DermaireColors.ink;
    const cells = 13;
    final cell = size.width / cells;
    for (var y = 0; y < cells; y++) {
      for (var x = 0; x < cells; x++) {
        if (((x * 7 + y * 11 + x * y) % 5 < 2) ||
            (x < 3 && y < 3) ||
            (x > 9 && y < 3) ||
            (x < 3 && y > 9)) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell - 1, cell - 1),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) => _TabPage(
    children: [
      const Eyebrow('Settings'),
      Text(
        'Privacy dashboard',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      const DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What we store',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6),
            Text(
              '• Skin measurement vectors & Erythema scores\n• High-resolution photos encrypted in Azure Blob Storage\n• Azure AI Vision & Content Safety analytics',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
      AccountSummary(account: state.account),
      OutlinedButton(onPressed: () => openPage(context, ClinicalStatusScreen(controller: state.clinical)), child: const Text('Safety & clinician guidance')),
      ActionCard(
        icon: '👤',
        title: 'Account and skin profile',
        subtitle: state.userEmail.isEmpty ? 'Account profile unavailable' : '${state.userName} · ${state.userEmail}',
        onTap: () => openPage(context, SkinProfileScreen(state: state, editing: true)),
      ),
      ActionCard(
        icon: '🔔',
        title: 'Notifications',
        subtitle: 'Check-in and experiment reminders',
        onTap: () => openPage(context, NotificationsScreen()),
      ),
      ActionCard(
        icon: '🔒',
        title: 'Doctor access',
        subtitle: state.doctorLinkActive
            ? 'One active QR link'
            : 'No active links',
        onTap: () => openPage(context, DoctorAccessScreen(state: state)),
      ),
      ActionCard(
        icon: '♿',
        title: 'Accessibility',
        subtitle: 'Voice, larger text and contrast follow your device',
        onTap: () =>
            showDermaireSnack(context, 'Accessibility preferences opened'),
      ),
      ActionCard(
        icon: 'ⓘ',
        title: 'About & methodology',
        subtitle: 'How Personal Skin Lab works',
        onTap: () => openPage(context, const HowItWorksScreen()),
      ),
      ActionCard(
        icon: '💬',
        title: 'Dermaire guide',
        subtitle: 'App help, measurement explanations and safety escalation',
        onTap: () => openPage(context, const SkinAssistantScreen()),
      ),
      TextButton(
        onPressed: () async {
          await ApiService.instance.logout();
          state.clearAccountData();
          if (!context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => WelcomeScreen(state: state)),
            (_) => false,
          );
        },
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => showDermaireSnack(
                context,
                'Your data export is being generated from Azure PostgreSQL',
              ),
              child: const Text('Export data'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: DermaireColors.conflict,
                side: const BorderSide(color: DermaireColors.conflict),
              ),
              onPressed: () => _deleteWarning(context),
              child: const Text('Delete account'),
            ),
          ),
        ],
      ),
    ],
  );

  void _deleteWarning(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Delete account?'),
      content: const Text(
        'This will permanently delete your account, skin history, and photos from Azure PostgreSQL and Azure Blob Storage. This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: DermaireColors.conflict, foregroundColor: Colors.white),
          onPressed: () async {
            Navigator.pop(dialogContext);
            showDermaireSnack(context, 'Deleting your account from Azure cloud…');
            final deleted = await ApiService.instance.deleteAccount();
            if (!context.mounted) return;
            if (!deleted) {
              showDermaireSnack(context, 'Account deletion failed. Please retry.');
              return;
            }
            state.clearAccountData();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => WelcomeScreen(state: state)),
              (_) => false,
            );
          },
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  static const templates = [
    (
      '☀️',
      'Your daily skin check-in is ready',
      "It's usually a good time for your check-in.",
    ),
    (
      '🕒',
      "You missed yesterday's check-in",
      'Consistency helps, but you can continue anytime.',
    ),
    (
      '⏳',
      'Your experiment ends tomorrow',
      'One more check-in to complete this round.',
    ),
    ('🎉', 'Your results are ready', 'Open the app to see your report.'),
    (
      '🔒',
      'Your doctor access expires tomorrow',
      'Generate a new link if they still need it.',
    ),
    ('⚠️', 'Interaction check required', 'Review before adding this product.'),
  ];
  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Notifications',
    title: 'Templates',
    children: templates
        .map(
          (item) =>
              ActionCard(icon: item.$1, title: item.$2, subtitle: item.$3),
        )
        .toList(),
  );
}

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});
  static const steps = [
    ('1', 'Capture', 'Your phone guides you into the same position each time.'),
    ('2', 'Measure', 'Skin features are extracted on your device.'),
    (
      '3',
      'Compare',
      'Measurements are compared against your personal baseline.',
    ),
    ('4', 'Control', 'You can log daily context. Weather is not measured and scores are not adjusted.'),
    (
      '5',
      'Report',
      'AI turns your experiment data into an understandable report.',
    ),
  ];
  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'About',
    title: 'How Personal Skin Lab works',
    children: [
      ...steps.map(
        (step) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                child: Text(
                  step.$1,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.$2,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(step.$3, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const Notice(
        icon: 'ⓘ',
        text:
            'We measure changes in your skin measurements. Interaction checks use fixed rules, not AI guesswork.',
      ),
    ],
  );
}

/// Existing navigation names delegate to the observation journey/history.
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key,required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context)=>ObservationHistoryScreen(state:state,onRecord:()async{await openPage(context,CameraScreen(state:state));});
}

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key,required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context)=>ObservationScreen(state:state,
    onHistory:()=>openPage(context,TimelineScreen(state:state)),
    onContext:()=>openPage(context,ContextScreen(state:state)));
}

class ContextScreen extends StatefulWidget {
  const ContextScreen({super.key, required this.state});
  final DermaireState state;

  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
  bool? unusual;
  final cycle = TextEditingController();
  bool initialized = false;
  late final int generation;

  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != ApiService.instance.sessionGeneration) return;
      widget.state.dailyContext.refresh().then((_) {
        if (!mounted || generation != ApiService.instance.sessionGeneration) return;
        final value = widget.state.dailyContext.current;
        setState(() {
          unusual = value?['unusual_conditions'] as bool?;
          cycle.text = value?['cycle_day']?.toString() ?? '';
          initialized = true;
        });
      });
    });
  }

  @override
  void dispose() {
    cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state.dailyContext,
    builder: (context, _) {
      if (generation != ApiService.instance.sessionGeneration) {
        return const DermairePage(title: 'Session ended', children: [Text('Reopen context from your current account.')]);
      }
      final controller = widget.state.dailyContext;
      return DermairePage(
        eyebrow: "Today's context (UTC)",
        title: 'Your reported context',
        children: [
          const Notice(icon: '🌤', text: 'Weather is not measured. These optional reports do not currently adjust skin scores.'),
          if (controller.error != null) Notice(icon: '!', text: controller.error!),
          if (controller.loading) const LinearProgressIndicator(),
          if (controller.current != null)
            Text(controller.current!['recorded'] == true ? 'Server-confirmed context: unusual conditions ${controller.current!['unusual_conditions'] ?? 'not reported'}; cycle day ${controller.current!['cycle_day'] ?? 'not reported'}' : 'No context recorded for today'),
          DropdownButtonFormField<bool>(
            key: ValueKey(initialized),
            initialValue: unusual,
            decoration: const InputDecoration(labelText: 'Unusual conditions (optional)'),
            items: const [
              DropdownMenuItem(value: null, child: Text('Not reported')),
              DropdownMenuItem(value: false, child: Text('No unusual conditions reported')),
              DropdownMenuItem(value: true, child: Text('Unusual conditions reported')),
            ],
            onChanged: controller.loading ? null : (value) => setState(() => unusual = value),
          ),
          TextField(controller: cycle, enabled: !controller.loading,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cycle day (optional, 1–60)')),
          const Text('Edits are an unsaved draft until the server confirms them.'),
          OutlinedButton(onPressed: controller.loading ? null : controller.refresh,
            child: const Text('Refresh server context')),
          FilledButton(
            onPressed: !initialized || controller.loading ? null : () async {
              if (generation != ApiService.instance.sessionGeneration) return;
              final text = cycle.text.trim();
              final day = text.isEmpty ? null : int.tryParse(text);
              if (text.isNotEmpty && (day == null || day < 1 || day > 60)) {
                showDermaireSnack(context, 'Enter a cycle day between 1 and 60, or leave it blank.');
                return;
              }
              final saved = await controller.save(unusual, day);
              if (!context.mounted || !saved || generation != ApiService.instance.sessionGeneration) return;
              showDermaireSnack(context, 'Context saved on server');
              Navigator.pop(context);
            }, child: const Text('Save context')),
        ],
      );
    },
  );
}
