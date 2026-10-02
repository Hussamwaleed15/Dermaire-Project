import 'package:flutter/material.dart';

import 'chatbot.dart';
import 'capture/capture_panel.dart';
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
  const _TabPage({required this.children, this.header});
  final List<Widget> children;
  final Widget? header;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
      children: [?header, ...children],
    ),
  );
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.home.current;
    final experiment = snapshot?['experiment'] as Map?;
    final entries = snapshot?['journal'] as List? ?? [];
    String delta(String key) {
      final value = experiment?[key] as num?;
      return value == null ? 'Unavailable' : '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
    }
    return _TabPage(
      header: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Welcome, ${state.userName.split(" ").first} 🌿',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            Text(
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: DermaireColors.ink.withValues(alpha: .55),
              ),
            ),
          ],
        ),
      ),
      children: [
        if (snapshot == null)
          Notice(icon: 'ℹ️', text: state.home.loading ? 'Loading Home…' :
            state.home.error ?? 'Home unconfirmed. Refresh to load current data.')
        else if (experiment == null)
          const Notice(icon: 'ℹ️', text: 'No current experiment')
        else ...[
          Text('Day ${experiment['current_day']} of ${experiment['target_days']}',
            style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text('Testing: ${experiment['product_name'] ?? 'No linked product'} · ${experiment['primary_concern']}'),
          Text('Status: ${experiment['status']}'),
          const SizedBox(height: 13),
          LinearProgressIndicator(value: (experiment['current_day'] as int) /
              (experiment['target_days'] as int)),
        ],
        OutlinedButton(
          onPressed: state.home.loading ? null : state.home.refresh,
          child: const Text('Refresh Home'),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: MetricTile(delta('redness_delta_percent'), 'Redness vs baseline')),
          const SizedBox(width: 10),
          Expanded(child: MetricTile(delta('texture_delta_percent'), 'Texture vs baseline')),
        ]),
        const SizedBox(height: 14),
        DermaireCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (snapshot?['today_checked_in'] == true)
                              ? "✓ Today's check-in"
                              : "🟢 Today's check-in",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          (snapshot?['today_checked_in'] == true)
                              ? 'Completed'
                              : snapshot != null ? 'Not yet completed' : 'Progress unconfirmed',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if ((snapshot?['today_checked_in'] == true)) const StatusPill('Done'),
                ],
              ),
              if (!(snapshot?['today_checked_in'] == true)) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => openPage(context, CameraScreen(state: state)),
                  child: const Text('Check in now'),
                ),
              ],
            ],
          ),
        ),
        const Notice(
          icon: '🌤',
          text:
              'Weather is not measured. Context does not currently adjust skin scores.',
        ),
        OutlinedButton(
          onPressed: () => openPage(context, ContextScreen(state: state)),
          child: const Text("View or edit today's context"),
        ),
        OutlinedButton(
          onPressed: () => openPage(context, TimelineScreen(state: state)),
          child: const Text('View experiment timeline'),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Latest journal entries',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontSize: 16),
            ),
            TextButton(
              onPressed: () => state.selectTab(2),
              child: const Text('View products'),
            ),
          ],
        ),
        if (snapshot != null && entries.isEmpty)
          const Text('No confirmed journal entries'),
        ...entries
            .map(
              (entry) => DermaireCard(
                color: DermaireColors.card,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEAD3BC), Color(0xFFC9A47E)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${(entry['created_at'] as String).split('T').first} · ${entry['time_of_day']}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "Hydration: ${entry['hydration_score']} · Redness: ${entry['redness_score']} · Texture: ${entry['texture_score']} (${entry['measurement_source']})",
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
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
      ActionCard(
        icon: '👤',
        title: 'Account and skin profile',
        subtitle: '${state.userName}${state.userEmail.isNotEmpty ? " · ${state.userEmail}" : " · Verified Skin Lab Member"}',
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
      backgroundColor: DermaireColors.card,
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
          style: FilledButton.styleFrom(backgroundColor: DermaireColors.conflict),
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
                backgroundColor: DermaireColors.deep,
                foregroundColor: Colors.white,
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

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key, required this.state});
  final DermaireState state;
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    ApiService.instance.addListener(_sessionChanged);
    _load();
  }
  void _sessionChanged() {
    if (!ApiService.instance.isAuthenticated && mounted) {
      setState(() { _rows = null; _error = 'Sign in to view skin history'; });
    }
  }
  @override
  void dispose() {
    ApiService.instance.removeListener(_sessionChanged);
    super.dispose();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _rows = null; _error = null; });
    try {
      final rows = await ApiService.instance.getCheckIns();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'Skin history unavailable: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Longitudinal skin history', title: 'Your check-ins',
    children: [
      if (_loading) const CircularProgressIndicator(),
      if (_error != null) Text(_error!),
      if (_rows != null && _rows!.isEmpty) const Text('No check-ins yet. Record your first observation.'),
      ...?_rows?.map((row) {
        final observation = row['observation'];
        final report = observation?['user_reported'];
        final source = row['ai_vision_analysis']?['measurement_source'];
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['created_at']} UTC', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(report == null ? 'Overall change: not reported' : 'User reported: ${report['overall_change']}'),
            if (report != null) ...[
              Text('Symptoms: ${(report['symptoms'] as List).join(', ')}'),
              Text('Routine: ${report['routine_status'] ?? 'not reported'}'),
            ],
            if (source != 'none') Text('${source == 'manual' ? 'User-entered measurements' : 'Photo estimates'}: hydration ${row['hydration_score']}, texture ${row['texture_score']}, redness ${row['redness_score']}'),
            if (row['notes'] != null) Text('User notes: ${row['notes']}'),
            if (row['image_sas_url'] != null) const Text('Linked photo available'),
            if (observation != null) Text('Daily context: ${observation['daily_context_date']} · ${observation['daily_context_id'] == null ? 'not linked at submission' : 'linked'}'),
          ],
        )));
      }),
      OutlinedButton(onPressed: _loading ? null : _load, child: const Text('Refresh history')),
      FilledButton(onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CameraScreen(state: widget.state)));
        if (mounted) _load();
      }, child: const Text('Record check-in')),
    ],
  );
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.state});
  final DermaireState state;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isUploading = false;
  String? _errorMessage;
  String? _overallChange;
  String? _routineStatus;
  final Set<String> _symptoms = {};
  final _notes = TextEditingController();
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submitPhoto() async {
    if (_isUploading) return;
    if (_overallChange == null) {
      setState(() => _errorMessage = 'Choose your overall skin change.');
      return;
    }
    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    Map<String, dynamic>? analysisResult;
    try {
      analysisResult = await ApiService.instance.submitCheckIn(
        timeOfDay: DateTime.now().hour < 12 ? 'Morning' : 'Evening',
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        report: {'overall_change': _overallChange, 'symptoms': _symptoms.toList(),
          'routine_status': _routineStatus},
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage =
              "Could not confirm this check-in. Check your connection and refresh history before retrying; the server may have received it.\n($e)";
        });
      }
      return;
    }
    // The write is confirmed; separately confirm baseline progress on the server.
    await widget.state.markTodayCheckedIn();
    if (mounted) setState(() => _isUploading = false);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => CheckInCompleteScreen(
          state: widget.state,
          analysisData: analysisResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Structured skin check-in',
    title: 'Record your observation',
    subtitle: 'Report your skin change. Photo quality checking is separate from your observation.',
    children: [
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Overall change since last check-in'),
        items: ['better', 'same', 'worse'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: _isUploading ? null : (value) => setState(() => _overallChange = value),
      ),
      const Text('Symptoms / concerns (optional)'),
      Wrap(spacing: 6, children: ['redness', 'dryness', 'itching', 'burning', 'breakouts', 'sensitivity', 'texture'].map((value) => FilterChip(
        label: Text(value), selected: _symptoms.contains(value),
        onSelected: _isUploading ? null : (selected) => setState(() { selected ? _symptoms.add(value) : _symptoms.remove(value); }),
      )).toList()),
      DropdownButtonFormField<String>(
        decoration: const InputDecoration(labelText: 'Routine adherence (optional)'),
        items: ['followed', 'partial', 'skipped', 'not_applicable'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: _isUploading ? null : (value) => setState(() => _routineStatus = value),
      ),
      TextField(controller: _notes, enabled: !_isUploading, maxLength: 1500, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      const CapturePanel(),
      if (_errorMessage != null)
        Notice(icon: '⚠️', text: _errorMessage!, color: DermaireColors.unknownBackground),
      const SizedBox(height: 8),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: DermaireColors.deep),
        onPressed: _isUploading ? null : _submitPhoto,
        child: _isUploading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Save check-in'),
      ),
    ],
  );
}

class CheckInCompleteScreen extends StatelessWidget {
  const CheckInCompleteScreen({
    super.key,
    required this.state,
    this.analysisData,
  });
  final DermaireState state;
  final Map<String, dynamic>? analysisData;

  @override
  Widget build(BuildContext context) {
    final redness = analysisData?['redness_score']?.toString() ?? 'Unavailable';
    final texture = analysisData?['texture_score']?.toString() ?? 'Unavailable';
    final hydration = analysisData?['hydration_score']?.toString() ?? 'Unavailable';

    return DermairePage(
      title: 'Check-in complete',
      subtitle: "Server saved your observation. Optional photo estimates are not clinical measurements.",
      centered: true,
      children: [
        if (state.baseline.error != null) Text('Check-in saved; ${state.baseline.error}'),
        const SizedBox(height: 8),
        if (analysisData?['observation']?['user_reported'] != null)
          Text('Your reported change: ${analysisData!['observation']['user_reported']['overall_change']}'),
        if (analysisData?['hydration_score'] != null) Row(
          children: [
            Expanded(child: MetricTile(redness, 'Redness')),
            const SizedBox(width: 10),
            Expanded(child: MetricTile(texture, 'Texture')),
            const SizedBox(width: 10),
            Expanded(child: MetricTile(hydration, 'Hydration')),
          ],
        ),
        const SizedBox(height: 14),
        if (analysisData != null && analysisData!['image_sas_url'] != null)
          Notice(
            icon: '☁️',
            text: 'Uploaded to Azure Blob Storage securely.',
            color: DermaireColors.paper,
          )
        else
          const Notice(
            icon: 'ⓘ',
            text:
                "One day's result doesn't prove anything on its own — your report looks at the trend over time.",
          ),
        FilledButton(
          onPressed: () => openPage(context, ContextScreen(state: state)),
          child: const Text("Add today's context"),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Text('View experiment'),
        ),
      ],
    );
  }
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

  @override
  void initState() {
    super.initState();
    widget.state.dailyContext.refresh().then((_) {
      if (!mounted) return;
      final value = widget.state.dailyContext.current;
      setState(() {
        unusual = value?['unusual_conditions'] as bool?;
        cycle.text = value?['cycle_day']?.toString() ?? '';
        initialized = true;
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
              final text = cycle.text.trim();
              final day = text.isEmpty ? null : int.tryParse(text);
              if (text.isNotEmpty && (day == null || day < 1 || day > 60)) {
                showDermaireSnack(context, 'Enter a cycle day between 1 and 60, or leave it blank.');
                return;
              }
              final saved = await controller.save(unusual, day);
              if (!context.mounted || !saved) return;
              showDermaireSnack(context, 'Context saved on server');
              Navigator.pop(context);
            }, child: const Text('Save context')),
        ],
      );
    },
  );
}
