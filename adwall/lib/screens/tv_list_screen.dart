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
                    tv.mediaUrl == null
                        ? 'No media set'
                        : 'Showing ${tv.mediaType} · ${tv.mediaUrl}',
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
  bool _uploading = false;
  String? _error;
  String? _lastMediaUrl;

  @override
  void initState() {
    super.initState();
    _lastMediaUrl = widget.tv.mediaUrl;
  }

  Future<void> _pickAndSend() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'png', 'jpg', 'jpeg', 'gif', 'webp', // images
        'mp4', 'mov', 'm4v', 'webm', // videos
      ],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    if (file.path == null) {
      setState(() => _error = "Couldn't read the selected file.");
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final mediaUrl = await widget.pairingService.uploadMedia(
        widget.tv.code,
        filePath: file.path!,
        fileName: file.name,
      );
      setState(() => _lastMediaUrl = mediaUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sent to "${widget.tv.nickname}"')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.tv.nickname)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _lastMediaUrl == null
                  ? 'Nothing playing on this TV yet.'
                  : 'Currently showing: $_lastMediaUrl',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _uploading ? null : _pickAndSend,
              icon: const Icon(Icons.upload),
              label: Text(_uploading ? 'Sending...' : 'Add image / video'),
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
