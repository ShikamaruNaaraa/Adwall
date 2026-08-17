import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/pairing_service.dart';

/// Admin screen: shows every paired TV and lets the admin pick one, then
/// pick an image/video file and push it to that TV.
class TvListScreen extends StatefulWidget {
  const TvListScreen({super.key, required this.pairingService});

  final PairingService pairingService;

  @override
  State<TvListScreen> createState() => _TvListScreenState();
}

class _TvListScreenState extends State<TvListScreen> {
  late Future<List<TvSummary>> _tvsFuture;

  @override
  void initState() {
    super.initState();
    _tvsFuture = widget.pairingService.fetchTvs();
  }

  Future<void> _refresh() async {
    setState(() {
      _tvsFuture = widget.pairingService.fetchTvs();
    });
    await _tvsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TVs'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<TvSummary>>(
          future: _tvsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load TVs: ${snapshot.error}')),
                ],
              );
            }
            final tvs = snapshot.data ?? [];
            if (tvs.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No TVs connected yet.')),
                ],
              );
            }
            return ListView.builder(
              itemCount: tvs.length,
              itemBuilder: (context, index) {
                final tv = tvs[index];
                return ListTile(
                  leading: const Icon(Icons.tv),
                  title: Text(tv.nickname),
                  subtitle: Text(
                    tv.playlist.isEmpty
                        ? 'No ads set'
                        : '${tv.playlist.length} ad(s) configured',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TvMediaScreen(
                          pairingService: widget.pairingService,
                          tv: tv,
                        ),
                      ),
                    );
                    _refresh();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Admin screen: pick an image/video and push it to a single TV.
class TvMediaScreen extends StatefulWidget {
  const TvMediaScreen({
    super.key,
    required this.pairingService,
    required this.tv,
  });

  final PairingService pairingService;
  final TvSummary tv;

  @override
  State<TvMediaScreen> createState() => _TvMediaScreenState();
}

class _TvMediaScreenState extends State<TvMediaScreen> {
  late List<PlaylistItem> _playlist;
  bool _uploading = false;
  String? _error;
  int _defaultDuration = 10;

  @override
  void initState() {
    super.initState();
    _playlist = List.of(widget.tv.playlist);
    if (_playlist.isNotEmpty) _defaultDuration = _playlist.first.durationSeconds;
  }

  Future<void> _pickAndSend() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      // Multiple selection is required for adding several ads at once.
      // ignore: deprecated_member_use
      allowMultiple: true,
      allowedExtensions: [
        'png', 'jpg', 'jpeg', 'gif', 'webp',
        'mp4', 'mov', 'm4v', 'webm',
      ],
    );
    if (result.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      for (final file in result) {
        if (file.path == null) continue;
        final updated = await widget.pairingService.uploadMedia(
          widget.tv.code,
          filePath: file.path!,
          fileName: file.name,
          durationSeconds: _defaultDuration,
        );
        if (mounted) setState(() => _playlist = updated);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.length} item(s) added to "${widget.tv.nickname}"')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _setDurationForAll() async {
    final controller = TextEditingController(text: _defaultDuration.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duration for all ads'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Seconds'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final seconds = int.tryParse(controller.text);
              if (seconds != null && seconds >= 1) Navigator.pop(context, seconds);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value == null || !mounted) return;
    setState(() => _defaultDuration = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('New ads will use $value seconds. Existing ads keep their durations.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tv.nickname)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('${_playlist.length} ad(s)')),
                OutlinedButton.icon(
                  onPressed: _setDurationForAll,
                  icon: const Icon(Icons.timer),
                  label: const Text('Same time for all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _playlist.isEmpty
                  ? const Center(child: Text('No ads added yet.'))
                  : ListView.separated(
                      itemCount: _playlist.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _playlist[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.image),
                            title: Text(item.mediaUrl.split('/').last),
                            subtitle: Text('${item.mediaType} · ${item.durationSeconds}s'),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                setState(() => _playlist.removeAt(index));
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickAndSend,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(_uploading ? 'Uploading...' : 'Add images'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
