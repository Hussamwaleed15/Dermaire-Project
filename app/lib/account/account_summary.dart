import 'package:flutter/material.dart';
import 'account_controller.dart';

class AccountSummary extends StatelessWidget {
  const AccountSummary({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: account,
    builder: (context, _) {
      final profile = account.value;
      if (account.phase == AccountPhase.loading) {
        return const Text('Loading your account profile…');
      }
      if (profile == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.error ?? 'Account profile is not available.'),
            if (account.phase != AccountPhase.unauthorized)
              TextButton(
                onPressed: () => account.hydrate(reuseConsent: false),
                child: const Text('Retry profile'),
              ),
          ],
        );
      }
      String text(String? value) =>
          value == null || value.isEmpty ? 'Not shared' : value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            profile.name.isEmpty ? 'Name not provided' : profile.name,
            key: const Key('accountName'),
          ),
          Text(profile.email, key: const Key('accountEmail')),
          Text('Account role: ${profile.role}'),
          Text('Skin type: ${text(profile.skinType)}'),
          Text('Goal: ${text(profile.selectedGoal)}'),
          Text(
            'Skin concerns: ${profile.skinConcerns == null
                ? 'Not shared'
                : profile.skinConcerns!.isEmpty
                ? 'None recorded'
                : profile.skinConcerns!.join(', ')}',
          ),
          if (account.error != null) ...[
            Text(account.error!),
            TextButton(
              onPressed: () => account.hydrate(reuseConsent: false),
              child: const Text('Retry profile'),
            ),
          ],
        ],
      );
    },
  );
}
