import 'package:flutter/material.dart';
import '../entry/entry_motion.dart';

/// Six existing destinations retain their state indices; the central action opens
/// observation/capture without pretending it is another selected tab.
class PatientNavigation extends StatelessWidget {
  const PatientNavigation({
    super.key,
    required this.selected,
    required this.labels,
    required this.icons,
    required this.onSelect,
    required this.onObserve,
  });
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelect;
  final VoidCallback onObserve;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showLabels =
              constraints.maxWidth >= 360 &&
              MediaQuery.textScalerOf(context).scale(10) <= 13;
          Widget destination(int index) => Expanded(
            child: Semantics(
              label: labels[index],
              button: true,
              onTap: () => onSelect(index),
              selected: selected == index,
              child: Tooltip(
                message: labels[index],
                child: ExcludeSemantics(
                  child: InkResponse(
                    key: ValueKey('patientDestination$index'),
                    onTap: () => onSelect(index),
                    child: SizedBox(
                      height: 64,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: EntryMotion.duration(context, 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: selected == index
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              icons[index],
                              size: 22,
                              color: selected == index
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (showLabels)
                            Text(
                              labels[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          return Row(
            children: [
              for (var i = 0; i < 3; i++) destination(i),
              SizedBox(
                width: 56,
                child: IconButton.filled(
                  key: const Key('centralObservationAction'),
                  tooltip: 'Record observation or guided photo',
                  onPressed: onObserve,
                  iconSize: 27,
                  padding: const EdgeInsets.all(14),
                  icon: const Icon(Icons.camera_alt_rounded),
                ),
              ),
              for (var i = 3; i < labels.length; i++) destination(i),
            ],
          );
        },
      ),
    ),
  );
}
