import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/pairing_service.dart';

/// Admin screen: manage "service ads" - images that automatically play on
/// every registered TV, inserted after every [interval] regular ads that
/// TV shows (or after 1 ad, if that TV only has a single regular ad).
class ServiceAdsScreen extends StatefulWidget {
  const ServiceAdsScreen({
    super.key,
    required this.pairingService,
    this.embedded = false,
    this.onRefreshCallback,
  });

  final PairingService pairingService;

  /// When true, this screen renders just its body content (no Scaffold or
  /// AppBar of its own) so it can live inside a host Scaffold - e.g. one
  /// page of a bottom-nav PageView that already has a shared AppBar.
  final bool embedded;

  /// Lets an embedding parent (e.g. the shared AppBar's refresh button)
  /// trigger this screen's own refresh logic.
  final ValueChanged<VoidCallback>? onRefreshCallback;

  @override
  State<ServiceAdsScreen> createState() => _ServiceAdsScreenState();
}

class _ServiceAdsScreenState extends State<ServiceAdsScreen> {
  late Future<List<ServiceAd>> _adsFuture;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adsFuture = widget.pairingService.fetchServiceAds();
    widget.onRefreshCallback?.call(() {
      _refresh();
    });
  }

  Future<void> _refresh() async {
    final future = widget.pairingService.fetchServiceAds();
    setState(() => _adsFuture = future);
    await future;
  }

  Future<void> _addServiceAd() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    if (result.isEmpty || result.first.path == null) return;
    final file = result.first;

    List<TvSummary> tvs;
    try {
      tvs = await widget.pairingService.fetchTvs();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return;
    }

    if (!mounted) return;
    final settings = await Navigator.of(context).push<_ServiceAdSettings>(
      MaterialPageRoute(builder: (context) => _ServiceAdSettingsPage(tvs: tvs)),
    );
    if (settings == null) return;

    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await widget.pairingService.createServiceAd(
        filePath: file.path!,
        fileName: file.name,
        durationSeconds: settings.durationSeconds,
        interval: settings.interval,
        targetTvCodes: settings.targetTvCodes,
      );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service ad added.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteServiceAd(ServiceAd ad) async {
    try {
      await widget.pairingService.deleteServiceAd(ad.id);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _editServiceAd(ServiceAd ad) async {
    List<TvSummary> tvs;
    try {
      tvs = await widget.pairingService.fetchTvs();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return;
    }
    if (!mounted) return;

    final settings = await Navigator.of(context).push<_ServiceAdSettings>(
      MaterialPageRoute(
        builder: (context) => _ServiceAdSettingsPage(
          tvs: tvs,
          initialDuration: ad.durationSeconds,
          initialInterval: ad.interval,
          initialTargetTvCodes: ad.targetTvCodes,
          title: 'Edit service ad',
          submitLabel: 'Save',
        ),
      ),
    );
    if (settings == null) return;

    try {
      await widget.pairingService.updateServiceAd(
        ad.id,
        durationSeconds: settings.durationSeconds,
        interval: settings.interval,
        updateTargetTvCodes: true,
        targetTvCodes: settings.targetTvCodes,
      );
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ads added here play automatically on every registered TV, '
            'after every N regular ads that TV shows (or after 1 ad, if '
            'that TV only has a single ad).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<ServiceAd>>(
              future: _adsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ListView(
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text('Failed to load: ${snapshot.error}')),
                    ],
                  );
                }
                final ads = snapshot.data ?? [];
                if (ads.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 60),
                      Icon(Icons.campaign_outlined, size: 56),
                      SizedBox(height: 16),
                      Center(child: Text('No service ads yet.')),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: ads.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final ad = ads[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.image),
                        title: Text(ad.mediaUrl.split('/').last),
                        subtitle: Text(
                          '${ad.durationSeconds}s · every ${ad.interval} ad(s) · '
                          '${ad.appliesToAllTvs ? 'All TVs' : '${ad.targetTvCodes!.length} TV(s)'}',
                        ),
                        onTap: () => _editServiceAd(ad),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editServiceAd(ad),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteServiceAd(ad),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _adding ? null : _addServiceAd,
            icon: const Icon(Icons.add_photo_alternate),
            label: Text(_adding ? 'Adding...' : 'Add service ad'),
          ),
        ),
      ],
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Ads'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: content,
    );
  }
}

class _ServiceAdSettings {
  const _ServiceAdSettings({
    required this.durationSeconds,
    required this.interval,
    required this.targetTvCodes,
  });
  final int durationSeconds;
  final int interval;

  /// `null` means the ad plays on every TV.
  final List<String>? targetTvCodes;
}

class _ServiceAdSettingsPage extends StatefulWidget {
  const _ServiceAdSettingsPage({
    required this.tvs,
    this.initialDuration = 10,
    this.initialInterval = 2,
    this.initialTargetTvCodes,
    this.title = 'Service ad settings',
    this.submitLabel = 'Add',
  });

  final List<TvSummary> tvs;
  final int initialDuration;
  final int initialInterval;

  /// `null` means "all TVs" - the default for a new service ad.
  final List<String>? initialTargetTvCodes;
  final String title;
  final String submitLabel;

  @override
  State<_ServiceAdSettingsPage> createState() => _ServiceAdSettingsPageState();
}

class _ServiceAdSettingsPageState extends State<_ServiceAdSettingsPage> {
  late final _durationController =
      TextEditingController(text: widget.initialDuration.toString());
  late final _intervalController =
      TextEditingController(text: widget.initialInterval.toString());

  late bool _allTvs = widget.initialTargetTvCodes == null ||
      widget.initialTargetTvCodes!.isEmpty;
  late final Set<String> _selectedTvCodes =
      {...?widget.initialTargetTvCodes};

  @override
  void dispose() {
    _durationController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  void _submit() {
    final duration = int.tryParse(_durationController.text);
    final interval = int.tryParse(_intervalController.text);
    if (duration == null || duration < 1 || interval == null || interval < 1) {
      return;
    }
    if (!_allTvs && _selectedTvCodes.isEmpty) return;
    Navigator.pop(
      context,
      _ServiceAdSettings(
        durationSeconds: duration,
        interval: interval,
        targetTvCodes: _allTvs ? null : _selectedTvCodes.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Playback', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (seconds)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _intervalController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Play after every N ads',
                helperText: 'e.g. 2 = play after every 2 ads on each TV',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 28),
            Text('Show on', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('All TVs'),
                    subtitle: const Text('Off = choose specific TVs below'),
                    value: _allTvs,
                    onChanged: widget.tvs.isEmpty
                        ? null
                        : (value) => setState(() => _allTvs = value),
                  ),
                  if (!_allTvs)
                    if (widget.tvs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('No TVs registered yet.'),
                        ),
                      )
                    else ...[
                      const Divider(height: 1),
                      ...widget.tvs.map(
                        (tv) => CheckboxListTile(
                          title: Text(tv.nickname),
                          value: _selectedTvCodes.contains(tv.code),
                          onChanged: (checked) {
                            setState(() {
                              if (checked ?? false) {
                                _selectedTvCodes.add(tv.code);
                              } else {
                                _selectedTvCodes.remove(tv.code);
                              }
                            });
                          },
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(widget.submitLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

