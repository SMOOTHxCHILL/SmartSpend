import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_sync.dart';

/// App-bar button: tap to sync now; spins while a sync is running.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  Future<void> _sync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await CloudSync.instance.syncAll();
      messenger.showSnackBar(SnackBar(
        content: Text(result.warning ?? '${result.summary}. Open the website to see your analysis.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: CloudSync.instance.status,
      builder: (context, status, _) {
        if (status.running) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return IconButton(
          icon: Icon(status.error != null ? Icons.cloud_off : Icons.cloud_sync),
          tooltip: status.error != null
              ? 'Last sync failed: ${status.error}'
              : status.result != null
                  ? status.result!.summary
                  : 'Sync to your account',
          onPressed: () => _sync(context),
        );
      },
    );
  }
}

/// App-bar menu showing who is logged in, with a log-out option.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final phone = Supabase.instance.client.auth.currentUser?.phone ?? '';

    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle),
      tooltip: 'Account',
      onSelected: (value) async {
        if (value == 'logout') {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Log out?'),
              content: const Text(
                'Transactions stay on this phone. New ones sync again after you log back in.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
              ],
            ),
          );
          if (confirmed == true) {
            await Supabase.instance.client.auth.signOut();
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(phone.isEmpty ? 'Logged in' : 'Logged in as +$phone'),
        ),
        const PopupMenuItem<String>(value: 'logout', child: Text('Log out')),
      ],
    );
  }
}
