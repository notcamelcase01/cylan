import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/strava_route.dart';
import '../providers/strava_import_provider.dart';

/// Returns `true` (via `Navigator.pop`) when at least one route was imported,
/// so the caller can refresh its rides list.
class StravaImportScreen extends StatelessWidget {
  const StravaImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => StravaImportProvider(),
      child: const _StravaImportView(),
    );
  }
}

class _StravaImportView extends StatefulWidget {
  const _StravaImportView();

  @override
  State<_StravaImportView> createState() => _StravaImportViewState();
}

class _StravaImportViewState extends State<_StravaImportView>
    with WidgetsBindingObserver {
  StravaImportProvider? _provider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider ??= context.read<StravaImportProvider>();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Covers the back button, swipe-back, and any other way this screen can
    // be popped without going through the explicit Cancel/Done buttons.
    _provider?.disconnectOnExit();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user comes back to the app after consenting in the browser.
    if (state == AppLifecycleState.resumed) {
      context.read<StravaImportProvider>().checkAfterConsent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StravaImportProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Strava')),
      body: SafeArea(child: _body(context, provider)),
    );
  }

  Widget _body(BuildContext context, StravaImportProvider provider) {
    switch (provider.step) {
      case StravaStep.checking:
        return const Center(child: CircularProgressIndicator());
      case StravaStep.connect:
        return _ConnectPrompt(provider: provider);
      case StravaStep.awaitingConsent:
        return _AwaitingConsent(provider: provider);
      case StravaStep.routes:
      case StravaStep.importing:
        return _RoutePicker(provider: provider);
      case StravaStep.done:
        return _Summary(provider: provider);
    }
  }
}

class _ConnectPrompt extends StatelessWidget {
  final StravaImportProvider provider;
  const _ConnectPrompt({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFFC4C02).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.link, size: 44, color: Color(0xFFFC4C02)),
            ),
            const SizedBox(height: 20),
            Text(
              'Connect your Strava',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We'll open Strava in your browser to approve access. Come back "
              'when you\'re done and pick the routes to import.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (provider.error != null) ...[
              const SizedBox(height: 16),
              Text(
                provider.error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFC4C02),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Connect Strava'),
                onPressed: provider.connect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AwaitingConsent extends StatelessWidget {
  final StravaImportProvider provider;
  const _AwaitingConsent({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Waiting for Strava…',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Approve access in the browser, then return here. We\'ll pick up '
              'your routes automatically.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => provider.refreshStatus(),
              child: const Text("I've connected — check now"),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutePicker extends StatelessWidget {
  final StravaImportProvider provider;
  const _RoutePicker({required this.provider});

  @override
  Widget build(BuildContext context) {
    final importing = provider.step == StravaStep.importing;
    if (provider.routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No saved routes found on your Strava account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _cancelImport(context),
                  child: const Text('Cancel import'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount: provider.routes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final route = provider.routes[i];
              final selected = provider.selectedIds.contains(route.id);
              return Card(
                child: CheckboxListTile(
                  value: selected,
                  onChanged: importing
                      ? null
                      : (_) => provider.toggle(route.id),
                  title: Text(
                    route.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_subtitle(route)),
                  secondary: Icon(
                    route.type == 2
                        ? Icons.directions_run
                        : Icons.directions_bike,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              );
            },
          ),
        ),
        if (provider.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              provider.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: importing || !provider.isSelected
                        ? null
                        : provider.importSelected,
                    child: importing
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Import ${provider.selectedIds.length} '
                            'route${provider.selectedIds.length == 1 ? '' : 's'}',
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed:
                        importing ? null : () => _cancelImport(context),
                    child: const Text('Cancel import'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cancelImport(BuildContext context) async {
    await provider.cancelImport();
    if (context.mounted) Navigator.of(context).pop(false);
  }

  String _subtitle(StravaRoute r) {
    final parts = <String>[];
    if (r.distanceM != null) parts.add('${r.distanceKm.toStringAsFixed(1)} km');
    if (r.elevationGainM != null) {
      parts.add('${r.elevationGainM!.toStringAsFixed(0)} m up');
    }
    return parts.join(' · ');
  }
}

class _Summary extends StatelessWidget {
  final StravaImportProvider provider;
  const _Summary({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = provider.imported.length;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              count > 0 ? Icons.check_circle : Icons.error_outline,
              size: 56,
              color: count > 0
                  ? const Color(0xFF12B76A)
                  : theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              count > 0
                  ? 'Imported $count route${count == 1 ? '' : 's'}'
                  : 'Nothing was imported',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (provider.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${provider.failures.length} failed',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Disconnected from Strava to free the slot for others.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(count > 0),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
