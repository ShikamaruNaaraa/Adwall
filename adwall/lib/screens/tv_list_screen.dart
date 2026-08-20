import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/pairing_service.dart';
import '../widgets/pill_message.dart';
import '../widgets/upload_progress_card.dart';

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
  double _uploadProgress = 0;
  String? _uploadingFileName;
  String? _uploadingFilePath;
  bool _savingOrientation = false;
  bool _savingTransition = false;
  String? _error;
  int _defaultDuration = 10;
  late Future<List<TvSummary>> _tvsFuture;
  bool _gridView = false;
  bool _selectionMode = false;
  final Set<int> _selectedIndices = {};

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
        setState(() {
          _uploadingFileName = file.name;
          _uploadingFilePath = file.path;
          _uploadProgress = 0;
        });
        final results = await widget.pairingService.uploadMediaToTvs(
          codes: targetCodes,
          filePath: file.path!,
          fileName: file.name,
          durationSeconds: _defaultDuration,
          onProgress: (progress) {
            if (mounted) setState(() => _uploadProgress = progress);
          },
        );
        final ownPlaylist = results[widget.tv.code];
        if (mounted && ownPlaylist != null) {
          setState(() => _playlist = ownPlaylist);
        }
      }
      if (mounted) {
        showPillMessage(
          context,
          '${result.length} item(s) added to ${targetCodes.length} TV(s)',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadingFileName = null;
          _uploadingFilePath = null;
          _uploadProgress = 0;
        });
      }
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
    showPillMessage(context, 'New ads will use $value seconds. Existing ads keep their durations.');
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

  /// The 3-dot menu shown on every ad card (grid and list view): Rename,
  /// Edit duration, and Delete, all in one place instead of a long-press
  /// bottom sheet.
  Widget _itemMenuButton(int index) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'rename':
            _editItemName(index);
            break;
          case 'duration':
            _editItemDuration(index);
            break;
          case 'delete':
            _confirmRemoveItem(index);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename'),
          ),
        ),
        PopupMenuItem(
          value: 'duration',
          child: ListTile(
            leading: Icon(Icons.timer_outlined),
            title: Text('Edit duration'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
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

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIndices.clear();
    });
  }

  void _toggleItemSelected(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// Opens a full-screen preview of one ad (tap anywhere on its card,
  /// outside of selection mode). Uses a Hero-driven fade/scale transition
  /// so the thumbnail grows smoothly into the full-screen preview instead
  /// of the default hard-cut page swap.
  void _openAdPreview(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) => _AdPreviewScreen(
          item: _playlist[index],
          pairingService: widget.pairingService,
          heroTag: 'ad-thumb-$index',
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Only fade the page chrome (app bar, background) in. The image
          // itself is a Hero and already animates its own position/size -
          // scaling the whole page on top of that fought the Hero's motion
          // and made the image look like it was jumping/colliding into
          // place instead of gliding smoothly.
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  /// Applies one duration to every selected ad, one backend call per ad
  /// (there's no bulk endpoint), then exits selection mode on success.
  Future<void> _setDurationForSelected() async {
    if (_selectedIndices.isEmpty) return;
    final controller = TextEditingController(text: _defaultDuration.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Duration for ${_selectedIndices.length} selected ad(s)'),
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

    final indices = _selectedIndices.toList()..sort();
    try {
      List<PlaylistItem> updated = _playlist;
      for (final index in indices) {
        updated = await widget.pairingService.updatePlaylistItemDuration(
          widget.tv.code,
          index: index,
          durationSeconds: value,
        );
      }
      if (mounted) {
        setState(() {
          _playlist = updated;
          _selectionMode = false;
          _selectedIndices.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIndices.isEmpty) return;
    final count = _selectedIndices.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected ads?'),
        content: Text('$count ad(s) will be removed from this TV.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteSelected();
  }

  /// Removes every selected ad, highest index first so earlier removals
  /// never shift the position of an ad still waiting to be deleted.
  Future<void> _deleteSelected() async {
    final indices = _selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    try {
      List<PlaylistItem> updated = _playlist;
      for (final index in indices) {
        updated = await widget.pairingService.removePlaylistItem(
          widget.tv.code,
          index: index,
        );
      }
      if (mounted) {
        setState(() {
          _playlist = updated;
          _selectionMode = false;
          _selectedIndices.clear();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
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
            if (!_selectionMode)
              Row(
                children: [
                  const Spacer(),
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
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _playlist.isEmpty ? null : _toggleSelectionMode,
                    icon: const Icon(Icons.checklist),
                    label: const Text('Select'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: Text('${_selectedIndices.length} selected')),
                  IconButton(
                    tooltip: 'Set duration for selected',
                    icon: const Icon(Icons.timer),
                    onPressed: _selectedIndices.isEmpty ? null : _setDurationForSelected,
                  ),
                  IconButton(
                    tooltip: 'Delete selected',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _selectedIndices.isEmpty ? null : _confirmDeleteSelected,
                  ),
                  TextButton(
                    onPressed: _toggleSelectionMode,
                    child: const Text('Done'),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _playlist.isEmpty
                  ? const Center(child: Text('No ads added yet.'))
                  : (_gridView ? _buildGrid() : _buildList()),
            ),
            if (_uploading && _uploadingFilePath != null) ...[
              UploadProgressCard(
                filePath: _uploadingFilePath!,
                fileName: _uploadingFileName ?? '',
                progress: _uploadProgress,
              ),
              const SizedBox(height: 12),
            ],
            if (!_selectionMode)
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
      cacheWidth: 300,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image, color: Colors.black45),
      ),
    );
  }

  Widget _buildList() {
    return _selectionMode ? _buildSelectableList() : _buildReorderableList();
  }

  /// Ordinary mode: press-and-hold anywhere on a row to drag it to a new
  /// position (no separate drag handle needed).
  Widget _buildReorderableList() {
    return ReorderableListView.builder(
      itemCount: _playlist.length,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      onReorderItem: (index, newIndex) => _reorderItem(index, newIndex),
      // Default drag styling paints a tinted background behind the item;
      // this keeps just a clean elevation/shadow lift instead.
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final lift = Curves.easeOut.transform(animation.value);
            return Material(
              elevation: 6 * lift,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(8),
              color: Colors.transparent,
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final item = _playlist[index];
        return Card(
          key: ValueKey('playlist-item-$index-${item.mediaUrl}'),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _openAdPreview(index),
            leading: SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Hero(
                  tag: 'ad-thumb-$index',
                  child: _thumbnail(item),
                ),
              ),
            ),
            title: Text(item.displayName),
            subtitle: Text('${item.mediaType} · ${item.durationSeconds}s'),
            trailing: _itemMenuButton(index),
          ),
        );
      },
    );
  }

  /// Selection mode: tap anywhere on a row to check/uncheck it.
  Widget _buildSelectableList() {
    return ListView.separated(
      itemCount: _playlist.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _playlist[index];
        final selected = _selectedIndices.contains(index);
        return Card(
          child: ListTile(
            onTap: () => _toggleItemSelected(index),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(value: selected, onChanged: (_) => _toggleItemSelected(index)),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _thumbnail(item),
                  ),
                ),
              ],
            ),
            title: Text(item.displayName),
            subtitle: Text('${item.mediaType} · ${item.durationSeconds}s'),
          ),
        );
      },
    );
  }

  Widget _buildGrid() {
    return _selectionMode ? _buildSelectableGrid() : _buildReorderableGrid();
  }

  /// Ordinary mode: press-and-hold anywhere on a card to drag it onto
  /// another card's position (no separate drag handle needed).
  Widget _buildReorderableGrid() {
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

        // Builds the card body. [useHero] is false for the drag-feedback
        // copy below, since two Heroes sharing a tag at once would trip
        // Flutter's duplicate-hero assertion while dragging.
        Widget buildCard({required bool useHero}) {
          final thumbnail = _thumbnail(item);
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openAdPreview(index),
                    child: useHero
                        ? Hero(tag: 'ad-thumb-$index', child: thumbnail)
                        : thumbnail,
                  ),
                ),
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
                Align(
                  alignment: Alignment.centerRight,
                  child: _itemMenuButton(index),
                ),
              ],
            ),
          );
        }

        final cardContent = buildCard(useHero: true);

        // Accepts a dropped card (dragged via long-press below) and moves
        // it to this card's position.
        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) => _reorderItem(details.data, index),
          builder: (context, candidateData, rejectedData) {
            final isDropTarget = candidateData.isNotEmpty;
            // Smooth animated lift + highlight instead of an instant snap,
            // so hovering over a drop target feels like it's welcoming the
            // card rather than just flipping a border on and off.
            final animatedCard = AnimatedScale(
              scale: isDropTarget ? 1.03 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDropTarget
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: cardContent,
              ),
            );
            // Press-and-hold anywhere on the card to start dragging it; a
            // short tap still reaches the 3-dot menu underneath normally.
            // Feedback mirrors the real card (not just the thumbnail) so
            // there's no visual mismatch between what you pick up and what
            // was actually there. It uses the non-Hero copy since the
            // resting card's Hero is still mounted underneath it.
            return LongPressDraggable<int>(
              data: index,
              onDragStarted: () => HapticFeedback.mediumImpact(),
              feedback: Transform.scale(
                scale: 1.06,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 160,
                    height: 160 / 0.85,
                    child: buildCard(useHero: false),
                  ),
                ),
              ),
              childWhenDragging: AnimatedOpacity(
                opacity: 0.35,
                duration: const Duration(milliseconds: 150),
                child: Transform.scale(scale: 0.96, child: animatedCard),
              ),
              child: animatedCard,
            );
          },
        );
      },
    );
  }


  /// Selection mode: tap anywhere on a card to check/uncheck it.
  Widget _buildSelectableGrid() {
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
        final selected = _selectedIndices.contains(index);
        return GestureDetector(
          onTap: () => _toggleItemSelected(index),
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: selected
                  ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                  : BorderSide.none,
            ),
            child: Stack(
              children: [
                Column(
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
                  ],
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleItemSelected(index),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen preview of a single playlist item (image or video).
class _AdPreviewScreen extends StatefulWidget {
  const _AdPreviewScreen({
    required this.item,
    required this.pairingService,
    required this.heroTag,
  });

  final PlaylistItem item;
  final PairingService pairingService;

  /// Must match the Hero tag on the thumbnail that was tapped, so the
  /// image grows smoothly out of the card instead of just cutting to a
  /// new screen.
  final Object heroTag;

  @override
  State<_AdPreviewScreen> createState() => _AdPreviewScreenState();
}

class _AdPreviewScreenState extends State<_AdPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitError = false;

  bool get _isVideo => widget.item.mediaType == 'video';

  /// The thumbnail grid/list always loads media through this same
  /// resolver (relative backend paths like '/media/abc.png' aren't
  /// directly loadable) - the preview needs it too, or the image/video
  /// silently fails to load.
  String get _resolvedUrl => widget.pairingService.resolveMediaUrl(widget.item.mediaUrl);

  @override
  void initState() {
    super.initState();
    if (_isVideo) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_resolvedUrl));
      _videoController = controller;
      controller
          .initialize()
          .then((_) {
            if (mounted) {
              setState(() {});
              controller.play();
              controller.setLooping(true);
            }
          })
          .catchError((_) {
            if (mounted) setState(() => _videoInitError = true);
          });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(widget.item.displayName),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Hero(
          tag: widget.heroTag,
          // Arcs the image from the thumbnail's position to centered
          // full-screen, like Material's photo-gallery transitions,
          // instead of a straight line - reads as far more deliberate.
          createRectTween: (begin, end) => MaterialRectArcTween(begin: begin, end: end),
          // Morphs the thumbnail's rounded corners down to square as it
          // grows, rather than snapping straight to full-bleed - this is
          // what removes the "pop"/collide feeling at the end of the flight.
          flightShuttleBuilder: (flightContext, animation, direction, fromContext, toContext) {
            final radius = Tween<double>(begin: 8, end: 0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
            final destinationChild = (toContext.widget as Hero).child;
            return AnimatedBuilder(
              animation: radius,
              child: destinationChild,
              builder: (context, child) => ClipRRect(
                borderRadius: BorderRadius.circular(radius.value),
                child: child,
              ),
            );
          },
          child: _isVideo ? _buildVideoPreview() : _buildImagePreview(),
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return InteractiveViewer(
      child: Image.network(
        _resolvedUrl,
        fit: BoxFit.contain,
        // Cross-fades the image in once it's actually decoded, instead of
        // popping in abruptly once the last byte arrives.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: child,
          );
        },
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 64,
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_videoInitError) {
      return const Icon(Icons.error_outline, color: Colors.white54, size: 64);
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white54);
    }
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
