import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';

/// Product availability, based on the audited app integration. No patient data,
/// preference receipt, OS permission query, HTTP request or notification record.
class NotificationAvailabilityScreen extends StatelessWidget {
  const NotificationAvailabilityScreen({super.key});

  @override
  Widget build(BuildContext context) => const DermairePage(
    eyebrow: 'Notifications',
    title: 'Device delivery is unavailable',
    subtitle: 'Use the notification inbox for current in-app updates.',
    children: [
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preferences', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Notification preferences and routine reminder schedules can be saved from the inbox. A saved setting does not prove device delivery.',
            ),
            SizedBox(height: 16),
            Text(
              'Device permission',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Notification permission has not been checked or requested by this app. Device permission alone would not confirm registration or delivery.',
            ),
          ],
        ),
      ),
      Text(
        'Open Dermaire to check your current routine and safety or clinician guidance. Notifications do not replace clinical care.',
      ),
    ],
  );
}
