import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/pairing_service.dart';

/// Turns a raw exception into a short, non-technical message for the UI.
String _friendlyError(Object e) {
  if (e is PairingException) return e.message;
  return 'Something went wrong. Please try again.';
}

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
                  Center(child: Text('Could not load TVs. Pull down to try again.')),
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
  late String _orientation;
  late String _transition;
  bool _uploading = false;
  bool _savingOrientation = false;
  bool _savingTransition = false;
  String? _error;
  int _defaultDuration = 10;
  late Future<List<TvSummary>> _tvsFuture;
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _playlist = List.of(widget.tv.playlist);
    _orientation = widget.tv.orientation;
    _transition = widget.tv.transition;
    if (_playlist.isNotEmpty) _defaultDuration = _playlist.first.durationSeconds;
    _tvsFuture = widget.pairingService.fetchTvs();
  }

  Future<void> _setOrientation(String orientation) async {
    if (orientation == _orientation || _savingOrientation) return;
    setState(() => _savingOrientation = true);
    try {
      final updated = await widget.pairingService.updateTvOrientation(
        widget.tv.code,
        orientation,
      );
      if (mounted) setState(() => _orientation = updated);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingOrientation = false);
    }
  }

  Future<void> _setTransition(String transition) async {
    if (transition == _transition || _savingTransition) return;
    setState(() => _savingTransition = true);
    try {
      final updated = await widget.pairingService.updateTvTransition(
        widget.tv.code,
        transition,
      );
      if (mounted) setState(() => _transition = updated);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _savingTransition = false);
    }
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

    if (!mounted) return;
    final targetCodes = await _pickTargetTvs();
    if (targetCodes == null || targetCodes.isEmpty) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      for (final file in result) {
        if (file.path == null) continue;
        final results = await widget.pairingService.uploadMediaToTvs(
          codes: targetCodes,
          filePath: file.path!,
          fileName: file.name,
          durationSeconds: _defaultDuration,
        );
        final ownPlaylist = results[widget.tv.code];
        if (mounted && ownPlaylist != null) {
          setState(() => _playlist = ownPlaylist);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.length} item(s) added to ${targetCodes.length} TV(s)',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Lets the admin choose which TVs should receive the ad(s) about to be
  /// uploaded, so the same ad can be pushed to multiple TVs at once. The
  /// current TV is preselected.
  Future<List<String>?> _pickTargetTvs() async {
    List<TvSummary> tvs;
    try {
      tvs = await _tvsFuture;
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
      return null;
    }
    if (!mounted) return null;

    final selected = <String>{widget.tv.code};
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Send to which TVs?'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: tvs.map((tv) {
                return CheckboxListTile(
                  value: selected.contains(tv.code),
                  title: Text(tv.nickname),
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked ?? false) {
                        selected.add(tv.code);
                      } else {
                        selected.remove(tv.code);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _editItemDuration(int index) async {
    final item = _playlist[index];
    final controller = TextEditingController(text: item.durationSeconds.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit duration'),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value == null || !mounted) return;

    try {
      final updated = await widget.pairingService.updatePlaylistItemDuration(
        widget.tv.code,
        index: index,
        durationSeconds: value,
      );
      if (mounted) setState(() => _playlist = updated);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _editItemName(int index) async {
    final item = _playlist[index];
    final controller = TextEditingController(text: item.displayName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename ad'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (value == null || !mounted) return;

    try {
      final updated = await widget.pairingService.updatePlaylistItemName(
        widget.tv.code,
        index: index,
        name: value,
      );
      if (mounted) setState(() => _playlist = updated);
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _removeItem(int index) async {
    final removed = _playlist[index];
    setState(() => _playlist.removeAt(index));
    try {
      final updated = await widget.pairingService.removePlaylistItem(
        widget.tv.code,
        index: index,
      );
      if (mounted) setState(() => _playlist = updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlist.insert(index, removed);
          _error = _friendlyError(e);
        });
      }
    }
  }

  Future<void> _confirmRemoveItem(int index) async {
    final item = _playlist[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove ad?'),
        content: Text('"${item.displayName}" will be removed from this TV.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) _removeItem(index);
  }

  /// Shows the rename/edit-duration options for one grid item, triggered by
  /// a long-press on its thumbnail so it doesn't clash with drag-to-reorder.
  Future<void> _showImageOptions(int index) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _editItemName(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Edit duration'),
              onTap: () {
                Navigator.pop(context);
                _editItemDuration(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Moves a playlist item from one position to another, updating the UI
  /// immediately and reverting if the backend call fails.
  Future<void> _reorderItem(int fromIndex, int toIndex) async {
    if (fromIndex == toIndex) return;
    final previous = List.of(_playlist);
    setState(() {
      final item = _playlist.removeAt(fromIndex);
      _playlist.insert(toIndex, item);
    });
    try {
      final updated = await widget.pairingService.reorderPlaylistItem(
        widget.tv.code,
        fromIndex: fromIndex,
        toIndex: toIndex,
      );
      if (mounted) setState(() => _playlist = updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          _playlist = previous;
          _error = _friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tv.nickname),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'landscape',
                    icon: Icon(Icons.stay_current_landscape),
                    label: Text('Horizontal'),
                  ),
                  ButtonSegment(
                    value: 'portrait',
                    icon: Icon(Icons.stay_current_portrait),
                    label: Text('Vertical'),
                  ),
                ],
                selected: {_orientation},
                onSelectionChanged: _savingOrientation
                    ? null
                    : (selection) => _setOrientation(selection.first),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text('Image transition')),
                DropdownButton<String>(
                  value: _transition,
                  onChanged: _savingTransition
                      ? null
                      : (value) {
                          if (value != null) _setTransition(value);
                        },
                  items: const [
                    DropdownMenuItem(
                      value: 'none',
                      child: Text('None'),
                    ),
                    DropdownMenuItem(
                      value: 'slide_left_to_right',
                      child: Text('Slide (left to right)'),
                    ),
                    DropdownMenuItem(
                      value: 'slide_right_to_left',
                      child: Text('Slide (right to left)'),
                    ),
                    DropdownMenuItem(
                      value: 'slide_top_to_bottom',
                      child: Text('Slide (top to bottom)'),
                    ),
                    DropdownMenuItem(
                      value: 'slide_bottom_to_top',
                      child: Text('Slide (bottom to top)'),
                    ),
                    DropdownMenuItem(
                      value: 'fade',
                      child: Text('Fade'),
                    ),
                    DropdownMenuItem(
                      value: 'blur',
                      child: Text('Blur'),
                    ),
                  ],
                ),

              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('${_playlist.length} ad(s)')),
                IconButton(
                  tooltip: _gridView ? 'List view' : 'Grid view',
                  icon: Icon(_gridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _gridView = !_gridView),
                ),
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
                  : (_gridView ? _buildGrid() : _buildList()),
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

  Widget _thumbnail(PlaylistItem item) {
    if (item.mediaType == 'video') {
      return Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.movie, color: Colors.black45),
      );
    }
    return Image.network(
      widget.pairingService.resolveMediaUrl(item.mediaUrl),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.black45),
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _playlist.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _playlist[index];
        // Touch-and-hold anywhere on the card to rename it or edit its
        // duration, same as in grid view.
        return GestureDetector(
          onLongPress: () => _showImageOptions(index),
          child: Card(
            child: ListTile(
              leading: SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _thumbnail(item),
                ),
              ),
              title: Text(item.displayName),
              subtitle: Text('${item.mediaType} · ${item.durationSeconds}s'),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _confirmRemoveItem(index),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: _playlist.length,
      itemBuilder: (context, index) {
        final item = _playlist[index];
        // Accepts a dropped item (dragged via the handle below) and moves
        // it to this card's position.
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => _reorderItem(details.data, index),
          builder: (context, candidateData, rejectedData) {
            final isDropTarget = candidateData.isNotEmpty;
            return Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isDropTarget
                    ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                    : BorderSide.none,
              ),
              // Touch-and-hold anywhere on the card to rename it or edit
              // its duration, kept separate from the drag handle below so
              // reordering and this menu never fight over the same gesture.
              child: GestureDetector(
                onLongPress: () => _showImageOptions(index),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _thumbnail(item)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${item.durationSeconds}s',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Drag handle: press-and-drag here to reorder. Kept
                        // separate from the image so it doesn't clash with
                        // the long-press menu above.
                        Draggable<int>(
                          data: index,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: _thumbnail(item),
                              ),
                            ),
                          ),
                          childWhenDragging: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_indicator, color: Colors.black26),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_indicator, color: Colors.black54),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmRemoveItem(index),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
