import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'chatbot.dart';
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
  Widget build(BuildContext context) => _TabPage(
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
      Text(
        'Day ${state.experimentDay} of 28',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      Text(
        'Testing: ${state.productController.active.where((product) => product.inExperiment).firstOrNull?.name ?? 'No active product'} for texture',
        style: TextStyle(
          fontSize: 13.5,
          color: DermaireColors.ink.withValues(alpha: .75),
        ),
      ),
      const SizedBox(height: 13),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: state.experimentDay / 28,
          minHeight: 6,
          color: DermaireColors.deep,
          backgroundColor: DermaireColors.line,
        ),
      ),
      const SizedBox(height: 16),
      const Row(
        children: [
          Expanded(child: MetricTile('Unavailable', 'Redness vs baseline')),
          SizedBox(width: 10),
          Expanded(child: MetricTile('Unavailable', 'Texture vs baseline')),
        ],
      ),
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
                        state.todayCheckedIn
                            ? "✓ Today's check-in"
                            : "🟢 Today's check-in",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        state.todayCheckedIn
                            ? 'Completed'
                            : state.baseline.available ? 'Not yet completed' : 'Progress unconfirmed',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (state.todayCheckedIn) const StatusPill('Done'),
              ],
            ),
            if (!state.todayCheckedIn) ...[
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
            'Weather today is within your normal range — no adjustment needed.',
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
      ...state.journal
          .take(2)
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
                          '${entry.date} · ${entry.time}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          entry.summary,
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

class ExperimentTab extends StatefulWidget {
  const ExperimentTab({super.key, required this.state});
  final DermaireState state;

  @override
  State<ExperimentTab> createState() => _ExperimentTabState();
}

class _ExperimentTabState extends State<ExperimentTab> {
  int step = 0;
  static const goals = [
    ('🔥', 'Reduce Acne'),
    ('💧', 'Improve Hydration'),
    ('✨', 'Even Skin Tone'),
    ('🌸', 'Reduce Redness'),
    ('⚪', 'Minimize Pores'),
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.state.baseline.hasProgress) {
      return _baselineStep(context);
    }
    if (step == 0) return _goalStep(context);
    if (step == 1) return _reviewStep(context);
    if (step == 2) return _safetyStep(context);
    return _baselineStep(context);
  }

  Widget _goalStep(BuildContext context) => _TabPage(
    children: [
      if (widget.state.baseline.error != null) Text(widget.state.baseline.error!),
      OutlinedButton(
        onPressed: widget.state.baseline.loading ? null : widget.state.baseline.refresh,
        child: const Text('Refresh baseline'),
      ),
      const Eyebrow('New experiment'),
      Text(
        'Choose your goal',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      const Text('What would you like to focus on?'),
      const SizedBox(height: 16),
      ...goals.map((goal) {
        final selected = widget.state.selectedGoal == goal.$2;
        return DermaireCard(
          color: selected ? DermaireColors.paper : DermaireColors.card,
          borderColor: selected ? DermaireColors.deep : DermaireColors.line,
          onTap: () => widget.state.selectGoal(goal.$2),
          child: Row(
            children: [
              Text(goal.$1),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  goal.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? DermaireColors.deep : DermaireColors.caramel,
              ),
            ],
          ),
        );
      }),
      FilledButton(
        onPressed: () {
          ApiService.instance.updateSkinProfile(selectedGoal: widget.state.selectedGoal).catchError((_) => <String, dynamic>{});
          setState(() => step = 1);
        },
        child: const Text('Next'),
      ),
    ],
  );

  Widget _reviewStep(BuildContext context) => _TabPage(
    children: [
      const Eyebrow('New experiment'),
      Text(
        'What do you want to test?',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      _LabeledValue(
        'Question',
        'Does ${widget.state.productController.active.where((product) => product.inExperiment).firstOrNull?.name ?? 'this product'} improve my skin texture?',
      ),
      _LabeledValue(
        'Variable',
        widget.state.productController.active
                .where((product) => product.inExperiment)
                .firstOrNull
                ?.name ??
            'Choose a product',
      ),
      const _LabeledValue('Target measurement', 'Texture'),
      const Row(
        children: [
          Expanded(child: MetricTile('Not started', 'Start date')),
          SizedBox(width: 10),
          Expanded(child: MetricTile('28 days', 'Duration')),
        ],
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () => setState(() => step = 2),
        child: const Text('Review'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => setState(() => step = 0),
        child: const Text('Back'),
      ),
    ],
  );

  Widget _safetyStep(BuildContext context) => _TabPage(
    children: [
      if (widget.state.baseline.error != null) Text(widget.state.baseline.error!),
      const Eyebrow('Ready to begin?'),
      Text(
        'Experiment safety check',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      _LabeledValue(
        'Test',
        '${widget.state.productController.active.where((product) => product.inExperiment).firstOrNull?.name ?? 'Choose a product'} · Texture · 28 days',
      ),
      const DermaireCard(
        color: DermaireColors.safeBackground,
        borderColor: Colors.transparent,
        child: Column(
          children: [
            StatusPill('🟢 GO'),
            SizedBox(height: 8),
            Text('Your experiment can begin.', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
      FilledButton(
        onPressed: widget.state.baseline.loading ? null : () async {
          final confirmed = await widget.state.baseline.refresh();
          if (mounted && confirmed) setState(() => step = 3);
        },
        child: const Text('Begin baseline'),
      ),
      const SizedBox(height: 14),
      const Notice(
        icon: 'ⓘ',
        text:
            'If an interaction check flags a conflict or unstable conditions, Dermaire blocks the experiment and explains the next step.',
      ),
    ],
  );

  Widget _baselineStep(BuildContext context) => _TabPage(
    children: [
      const Eyebrow('Baseline period'),
      if (!widget.state.baseline.available)
        Text(widget.state.baseline.error ?? 'Confirming baseline with server...'),
      OutlinedButton(
        onPressed: widget.state.baseline.loading ? null : widget.state.baseline.refresh,
        child: const Text('Refresh baseline'),
      ),
      Text(
        'Establishing your baseline',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      const Text(
        "We're learning what your skin looks like before the experiment begins.",
      ),
      const SizedBox(height: 16),
      DermaireCard(
        child: Column(
          children: [
            const Text('Day', style: TextStyle(fontSize: 13)),
            Text(
              '${widget.state.baselineCheckIns ?? 'Unknown'} of 5 days',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: widget.state.baselineCheckIns == null ? null : widget.state.baselineCheckIns! / 5,
              minHeight: 6,
              color: DermaireColors.deep,
              backgroundColor: DermaireColors.line,
            ),
          ],
        ),
      ),
      Row(
        children: [
          Expanded(
            child: MetricTile(
              '${widget.state.baselineCheckIns ?? 'Unknown'}',
              'Confirmed days',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: MetricTile(!widget.state.baseline.available ? 'Unknown' : widget.state.baseline.ready ? 'Ready' : 'Collecting', 'Baseline status')),
        ],
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: () => openPage(context, CameraScreen(state: widget.state)),
        child: const Text("Take today's check-in"),
      ),
      const SizedBox(height: 8),
      const Text('Baseline uses five different UTC days. Experiment comparisons require all five days before that experiment began. Image estimates are proxies, not clinical measurements.'),
      if (widget.state.baseline.ready)
        ...widget.state.baseline.metrics.entries.map((entry) => _LabeledValue(
          '${entry.key} baseline',
          'Mean: ${entry.value['mean']} · Standard deviation: ${entry.value['standard_deviation']}',
        )),
    ],
  );
}

class _LabeledValue extends StatelessWidget {
  const _LabeledValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => DermaireCard(
    color: DermaireColors.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: DermaireColors.ink.withValues(alpha: .6),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
      ],
    ),
  );
}

class RewardsTab extends StatelessWidget {
  const RewardsTab({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) => _TabPage(
    children: [
      const Eyebrow('Rewards'),
      Text('Token rewards', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DermaireColors.caramel, DermaireColors.deep],
          ),
        ),
        child: Column(
          children: [
            const Text('🌿  🪙', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              '${state.tokens} tokens',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              'Every product you add to your routine earns tokens toward a free skincare product.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: math.min(1, state.tokens / 10),
              minHeight: 7,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
            const SizedBox(height: 6),
            Text(
              '${state.tokens} / 10 tokens to your next free product',
              style: const TextStyle(color: Colors.white70, fontSize: 10.5),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      FilledButton(
        onPressed: state.tokens >= 10 ? () => _redeem(context) : null,
        child: Text(
          state.tokens >= 10
              ? '🎁 Redeem your free serum'
              : 'Keep adding products to unlock a reward',
        ),
      ),
      const Divider(height: 34),
      Text(
        'How you earn tokens',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
      ),
      const SizedBox(height: 10),
      const ActionCard(
        icon: '+1',
        title: 'Add a product to your routine',
        subtitle: 'From search, all products, or a custom entry',
      ),
      const ActionCard(
        icon: '+1',
        title: 'Log a new journal entry',
        subtitle: 'Daily check-ins keep your streak going',
      ),
      const ActionCard(
        icon: '+1',
        title: 'Complete a daily check-in',
        subtitle: 'Consistent measurements improve your report',
      ),
      Text(
        'Reward tiers',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
      ),
      const SizedBox(height: 10),
      const _RewardTier('🧴', 'Travel-size Hydrating Serum', r'$12 value'),
      const _RewardTier('🧼', 'Full-size Gentle Cleanser', r'$18 value'),
      const _RewardTier('☀️', 'SPF 30 Mineral Sunscreen', r'$22 value'),
      const _RewardTier('🎁', 'Complete Hydration Bundle', r'$45 value'),
      if (state.redemptionHistory.isNotEmpty) ...[
        Text(
          'Redemption history',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 10),
        ...state.redemptionHistory.map(
          (item) => DermaireCard(color: DermaireColors.card, child: Text(item)),
        ),
      ],
    ],
  );

  void _redeem(BuildContext context) {
    if (!state.redeemReward()) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DermaireColors.card,
        icon: const Text('🧴', style: TextStyle(fontSize: 42)),
        title: const Text("You've earned a free product!"),
        content: const Text(
          'Your Travel-size Hydrating Serum has been added to your redemption history.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Great!'),
          ),
        ],
      ),
    );
  }
}

class _RewardTier extends StatelessWidget {
  const _RewardTier(this.icon, this.name, this.value);
  final String icon;
  final String name;
  final String value;

  @override
  Widget build(BuildContext context) => DermaireCard(
    color: DermaireColors.card,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: DermaireColors.ink.withValues(alpha: .6),
          ),
        ),
      ],
    ),
  );
}

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) => _TabPage(
    children: [
      const Eyebrow('Demo results - not your measurements'),
      Text('Your results', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      const Text('Product X · 28-day experiment'),
      const SizedBox(height: 16),
      const DermaireCard(
        color: DermaireColors.card,
        child: SizedBox(height: 160, child: _ProgressChart()),
      ),
      const Row(
        children: [
          Expanded(child: MetricTile('−18%', 'Texture change')),
          SizedBox(width: 10),
          Expanded(child: MetricTile('25/28', 'Check-ins logged')),
        ],
      ),
      const SizedBox(height: 14),
      const Notice(
        icon: 'ⓘ',
        text:
            'Your result was adjusted for 3 days of recorded environmental conditions.',
      ),
      FilledButton(
        onPressed: () => openPage(context, ResultsScreen(state: state)),
        child: const Text('View full result'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () => openPage(context, ReportScreen(state: state)),
        child: const Text('Generate report'),
      ),
    ],
  );
}

class _ProgressChart extends StatelessWidget {
  const _ProgressChart();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _ChartPainter(), child: const SizedBox.expand());
}

class _ChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = DermaireColors.line
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final values = [.82, .74, .78, .57, .52, .33, .28, .13];
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        size.width * i / (values.length - 1),
        size.height * values[i],
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = DermaireColors.deep
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, required this.state});
  final DermaireState state;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  int interpretation = 0;

  @override
  Widget build(BuildContext context) {
    const titles = [
      'Your skin showed improvement',
      'No significant change detected',
      'Measurements changed negatively',
    ];
    const descriptions = [
      'Texture improved by 18% compared with your personal baseline.',
      'Your measurements stayed close to your personal baseline.',
      'Some measurements moved away from your baseline during the experiment.',
    ];
    final colors = [
      DermaireColors.safeBackground,
      DermaireColors.paper,
      DermaireColors.conflictBackground,
    ];
    return DermairePage(
      eyebrow: 'Demo result interpretation - not your baseline data',
      title: 'What this means',
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Positive')),
            ButtonSegment(value: 1, label: Text('No change')),
            ButtonSegment(value: 2, label: Text('Negative')),
          ],
          selected: {interpretation},
          onSelectionChanged: (value) =>
              setState(() => interpretation = value.first),
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(height: 16),
        DermaireCard(
          color: colors[interpretation],
          borderColor: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${interpretation == 0
                    ? '🟢'
                    : interpretation == 1
                    ? '⚪'
                    : '🟠'} ${titles[interpretation]}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                descriptions[interpretation],
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (interpretation == 0)
          FilledButton(
            onPressed: () =>
                openPage(context, ReportScreen(state: widget.state)),
            child: const Text('Generate report'),
          )
        else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              interpretation == 1
                  ? 'Start another experiment'
                  : 'Review experiment',
            ),
          ),
      ],
    );
  }
}

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) {
    const sections = [
      ('1. Experiment', 'Product X · 28 days · Target: texture'),
      (
        '2. Baseline',
        'Example baseline average and standard deviation; not computed from your measurements',
      ),
      ('3–4. Measurements & change', 'Texture improved 18% vs. baseline'),
      (
        '5. Context',
        '3 days excluded for abnormal weather; cycle context logged where provided',
      ),
      (
        '6. Conclusion',
        'The measured change was associated with the tested product during this controlled experiment.',
      ),
      ('7. Data quality', '25 of 28 check-ins · 89% consistency'),
    ];
    return DermairePage(
      eyebrow: 'Demo report - not your baseline data',
      title: 'Personal Skin Lab report',
      children: [
        ...sections.map((item) => _LabeledValue(item.$1, item.$2)),
        FilledButton(
          onPressed: () => openPage(context, DoctorAccessScreen(state: state)),
          child: const Text('Share with doctor'),
        ),
      ],
    );
  }
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
        title: 'Account',
        subtitle: '${state.userName}${state.userEmail.isNotEmpty ? " · ${state.userEmail}" : " · Verified Skin Lab Member"}',
        onTap: () => showDermaireSnack(context, 'Account: ${state.userName} (${state.userEmail})'),
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
    ('4', 'Control', 'Weather and other context are considered.'),
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

class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key, required this.state});
  final DermaireState state;
  static const events = [
    ('Day 1', 'Baseline period begins'),
    ('Day 5', 'Baseline established'),
    ('Day 7', 'Check-in logged'),
    ('Day 10', 'Product added — interaction check passed'),
    ('Day 14', 'Environmental anomaly recorded'),
    ('Day 21', 'Check-in logged'),
    ('Day 28', 'Experiment complete'),
  ];

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Demo timeline - not your baseline history',
    title:
        '${state.productController.active.where((product) => product.inExperiment).firstOrNull?.name ?? 'No active product'} · Texture',
    actions: [
      IconButton(
        onPressed: state.togglePause,
        icon: Icon(
          state.experimentPaused
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded,
        ),
      ),
    ],
    children: [
      if (state.experimentPaused)
        const Notice(
          icon: '⏸',
          text: 'Experiment paused. Resume any time.',
          color: DermaireColors.unknownBackground,
        ),
      ...events.indexed.map((entry) {
        final current = entry.$1 + 1 == state.experimentDay;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: current
                            ? DermaireColors.deep
                            : DermaireColors.caramel,
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (entry.$1 < events.length - 1)
                      Expanded(
                        child: Container(
                          width: 1,
                          color: DermaireColors.caramel,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.$2.$1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      Text(entry.$2.$2, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
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
  Uint8List? _photoBytes;
  String? _photoFilename;
  bool _isUploading = false;
  String? _errorMessage;

  Future<void> _pickPhoto() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _photoBytes = bytes;
          _photoFilename = file.name;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to select image: $e');
    }
  }

  Future<void> _submitPhoto() async {
    if (_isUploading) return;
    if (_photoBytes == null) {
      setState(() => _errorMessage = 'Select a skin photo before analyzing.');
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
        photoBytes: _photoBytes,
        photoFilename: _photoFilename,
        notes: 'Skin photo captured via app',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage =
              "Could not confirm this photo check-in. Check your connection and retry; the server may have received it.\n($e)";
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
    eyebrow: 'Photo estimate check-in',
    title: 'Analyze your skin',
    subtitle: _photoBytes == null
        ? 'Upload or take a clear, well-lit photo for image-property estimates.'
        : 'Photo ready for server processing.',
    children: [
      if (_photoBytes != null)
        Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DermaireColors.line),
            color: DermaireColors.paper,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(_photoBytes!, fit: BoxFit.cover),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                      SizedBox(width: 4),
                      Text('Photo ready', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        )
      else
        const FaceGuide(
          label: 'Take or choose\na skin photo',
          warning: false,
        ),
      const SizedBox(height: 14),
      if (_errorMessage != null)
        Notice(
          icon: '⚠️',
          text: _errorMessage!,
          color: DermaireColors.unknownBackground,
        ),
      Notice(
        icon: '🔒',
        text: _photoBytes == null
            ? 'Photos are stored by the server. Measurements are image-property proxies, not clinical analysis.'
            : 'Image: ${_photoFilename ?? "Skin photo"} selected. Tap Analyze to process on the server.',
        color: DermaireColors.paper,
      ),
      FilledButton.icon(
        icon: const Icon(Icons.photo_library_rounded),
        onPressed: _isUploading ? null : _pickPhoto,
        label: Text(_photoBytes == null ? 'Select skin photo' : 'Choose another photo'),
      ),
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
            : const Text('Capture & Analyze measurement'),
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
      subtitle: "Server saved your image-property estimates. These are not clinical measurements.",
      centered: true,
      children: [
        if (state.baseline.error != null) Text('Check-in saved; ${state.baseline.error}'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: MetricTile(redness, 'Redness')),
            const SizedBox(width: 10),
            Expanded(child: MetricTile(texture, 'Texture')),
            const SizedBox(width: 10),
            Expanded(child: MetricTile(hydration, 'Hydration')),
          ],
        ),
        const SizedBox(height: 14),
        if (analysisData != null && analysisData!['photo_url'] != null)
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
  bool unusualWeather = false;
  double cycleDay = 12;

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: "Today's context",
    title: unusualWeather
        ? 'Unusual conditions detected'
        : 'A few quick details',
    children: [
      if (unusualWeather)
        const Notice(
          icon: '🟡',
          text:
              "Today's environmental conditions differ significantly from your usual measurements. We'll account for this in your result.",
          color: DermaireColors.unknownBackground,
        ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weather',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    unusualWeather ? '34°C' : '22°C',
                    'Temperature',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MetricTile(unusualWeather ? '88%' : '48%', 'Humidity'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Simulate unusual weather',
                style: TextStyle(fontSize: 12.5),
              ),
              value: unusualWeather,
              activeTrackColor: DermaireColors.deep,
              onChanged: (value) => setState(() => unusualWeather = value),
            ),
          ],
        ),
      ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Personal context (optional)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Cycle day ${cycleDay.round()}',
              style: const TextStyle(fontSize: 12),
            ),
            Slider(
              value: cycleDay,
              min: 1,
              max: 28,
              divisions: 27,
              activeColor: DermaireColors.deep,
              onChanged: (value) => setState(() => cycleDay = value),
            ),
          ],
        ),
      ),
      FilledButton(
        onPressed: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
          showDermaireSnack(context, 'Context saved');
        },
        child: const Text('Save context'),
      ),
    ],
  );
}
