import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/pairing_service.dart';

/// Admin "Group Animation" section: pick a set of TVs, arrange the order
/// they should light up in, attach one animation (an image or video the
/// admin uploads), then Play to show it on the first TV. The moment that
/// TV finishes playing it, it hands off to the next TV in the order, and
/// so on down the list - so only one screen is ever playing the animation
/// at a time.
class GroupAnimationScreen extends StatefulWidget {
  const GroupAnimationScreen({super.key, required this.pairingService});

  final PairingService pairingService;

  @override
  State<GroupAnimationScreen> createState() => _GroupAnimationScreenState();
}

class _GroupAnimationScreenState extends State<GroupAnimationScreen> {
  late Future<_ScreenData> _future;
  String? _playingGroupId;
  String? _uploadingGroupId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ScreenData> _load() async {
    final tvs = await widget.pairingService.fetchTvs();
    final groups = await widget.pairingService.fetchGroups();
    return _ScreenData(tvs: tvs, groups: groups);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _openEditor({TvGroup? existing, required List<TvSummary> tvs}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _GroupEditorScreen(
          pairingService: widget.pairingService,
          allTvs: tvs,
          existing: existing,
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _quickAddTvs(TvGroup group, List<TvSummary> allTvs) async {
    final available =
        allTvs.where((t) => !group.tvCodes.contains(t.code)).toList();
    if (available.isEmpty) return;
    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Add TVs to '${group.name}'"),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final tv in available)
                  CheckboxListTile(
                    value: selected.contains(tv.code),
                    title: Text(tv.nickname),
                    subtitle: Text(tv.connected ? 'Connected' : 'Disconnected'),
                    onChanged: (checked) => setDialogState(() {
                      if (checked == true) {
                        selected.add(tv.code);
                      } else {
                        selected.remove(tv.code);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  selected.isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;
    try {
      await widget.pairingService.updateGroup(
        group.id,
        tvCodes: [...group.tvCodes, ...selected],
      );
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to add TVs: $e')));
      }
    }
  }

  Future<void> _deleteGroup(TvGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text("This removes the '${group.name}' animation group."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.pairingService.deleteGroup(group.id);
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete group: $e')));
      }
    }
  }

  /// Lets the admin pick an image or video from this device and upload it
  /// as the group's animation. Videos play to their own end on the TV;
  /// for images, ask for how many seconds to show it.
  Future<void> _addAnimation(TvGroup group) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'mp4', 'mov', 'webm', 'mkv'],
    );
    if (result.isEmpty || result.first.path == null) return;
    final file = result.first;
    final isVideo = ['.mp4', '.mov', '.webm', '.mkv']
        .any((ext) => file.name.toLowerCase().endsWith(ext));

    int? durationSeconds;
    if (!isVideo) {
      durationSeconds = await showDialog<int>(
        context: context,
        builder: (context) {
          final controller = TextEditingController(
            text: (group.animationDurationSeconds).toString(),
          );
          return AlertDialog(
            title: const Text('How long should it show?'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (seconds)',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(controller.text);
                  Navigator.pop(context, (value == null || value < 1) ? 8 : value);
                },
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
      if (durationSeconds == null) return;
    }

    setState(() {
      _uploadingGroupId = group.id;
      _error = null;
    });
    try {
      await widget.pairingService.uploadGroupAnimation(
        group.id,
        filePath: file.path!,
        fileName: file.name,
        durationSeconds: durationSeconds,
      );
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to add animation: $e');
    } finally {
      if (mounted) setState(() => _uploadingGroupId = null);
    }
  }

  Future<void> _playGroup(TvGroup group) async {
    if (!group.hasAnimation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an animation to this group first.')),
      );
      return;
    }
    setState(() {
      _playingGroupId = group.id;
      _error = null;
    });
    try {
      await widget.pairingService.playGroupAnimation(group.id);
    } catch (e) {
      setState(() => _error = 'Failed to play animation: $e');
    } finally {
      // Rough visual "playing" duration so the button shows feedback even
      // though the real playback happens on the TVs, not here.
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _playingGroupId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_ScreenData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('Failed to load groups: ${snapshot.error}')),
              ],
            );
          }
          final data = snapshot.data!;
          final connectedTvs = data.tvs.where((t) => t.connected).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.animation),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Arrange TVs in order, add an animation (image or '
                          'video), then Play. It shows on the first TV, and '
                          'the moment that TV finishes, the next TV in the '
                          'order starts - one screen at a time, in sequence.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: data.tvs.length < 2
                    ? null
                    : () => _openEditor(tvs: data.tvs),
                icon: const Icon(Icons.add),
                label: const Text('New animation group'),
              ),
              if (data.tvs.length < 2) ...[
                const SizedBox(height: 8),
                const Text(
                  'Add at least 2 TVs first to build an animation group.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
              const SizedBox(height: 24),
              if (data.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('No animation groups yet.')),
                )
              else
                ...data.groups.map((group) {
                  final byCode = {for (final t in data.tvs) t.code: t};
                  final playing = _playingGroupId == group.id;
                  final uploading = _uploadingGroupId == group.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                tooltip: 'Add TVs',
                                onPressed: data.tvs.length ==
                                        group.tvCodes.length
                                    ? null
                                    : () => _quickAddTvs(group, data.tvs),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit order',
                                onPressed: () => _openEditor(
                                  existing: group,
                                  tvs: data.tvs,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete group',
                                onPressed: () => _deleteGroup(group),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var i = 0; i < group.tvCodes.length; i++)
                                _OrderChip(
                                  index: i,
                                  label: byCode[group.tvCodes[i]]?.nickname ??
                                      group.tvCodes[i],
                                  connected:
                                      byCode[group.tvCodes[i]]?.connected ??
                                          false,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                group.hasAnimation
                                    ? (group.animationMediaType == 'video'
                                        ? Icons.movie_outlined
                                        : Icons.image_outlined)
                                    : Icons.image_not_supported_outlined,
                                size: 18,
                                color: group.hasAnimation ? null : Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  group.hasAnimation
                                      ? '${group.animationMediaType == 'video' ? 'Video' : 'Image'} animation added'
                                      : 'No animation added yet',
                                  style: TextStyle(
                                    color: group.hasAnimation
                                        ? null
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed:
                                    uploading ? null : () => _addAnimation(group),
                                icon: uploading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_outlined, size: 18),
                                label: Text(
                                  group.hasAnimation ? 'Replace' : 'Add animation',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: playing ? null : () => _playGroup(group),
                              icon: playing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_arrow),
                              label: Text(playing ? 'Playing...' : 'Play'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '$connectedTvs of ${data.tvs.length} TV(s) currently connected',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderChip extends StatelessWidget {
  const _OrderChip({
    required this.index,
    required this.label,
    required this.connected,
  });

  final int index;
  final String label;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        radius: 10,
        child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
      ),
      label: Text(label),
      backgroundColor: connected
          ? Colors.green.withValues(alpha: 0.12)
          : Colors.red.withValues(alpha: 0.12),
    );
  }
}

class _ScreenData {
  const _ScreenData({required this.tvs, required this.groups});
  final List<TvSummary> tvs;
  final List<TvGroup> groups;
}

/// Full-screen editor: reorder the selected TVs by dragging, toggle which
/// TVs are included, name the group, and save.
class _GroupEditorScreen extends StatefulWidget {
  const _GroupEditorScreen({
    required this.pairingService,
    required this.allTvs,
    this.existing,
  });

  final PairingService pairingService;
  final List<TvSummary> allTvs;
  final TvGroup? existing;

  @override
  State<_GroupEditorScreen> createState() => _GroupEditorScreenState();
}

class _GroupEditorScreenState extends State<_GroupEditorScreen> {
  late final TextEditingController _nameController;
  late List<TvSummary> _ordered; // TVs currently in the group, in order.
  late List<TvSummary> _available; // TVs not yet added.
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    final byCode = {for (final t in widget.allTvs) t.code: t};
    final existingCodes = widget.existing?.tvCodes ?? const [];
    _ordered = existingCodes
        .map((code) => byCode[code])
        .whereType<TvSummary>()
        .toList();
    _available = widget.allTvs
        .where((t) => !existingCodes.contains(t.code))
        .toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _add(TvSummary tv) {
    setState(() {
      _available.remove(tv);
      _ordered.add(tv);
    });
  }

  void _remove(TvSummary tv) {
    setState(() {
      _ordered.remove(tv);
      _available.add(tv);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final tv = _ordered.removeAt(oldIndex);
      _ordered.insert(newIndex, tv);
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    if (_ordered.length < 2) {
      setState(() => _error = 'Add at least 2 TVs, in the order they should light up.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final codes = _ordered.map((t) => t.code).toList();
      if (widget.existing != null) {
        await widget.pairingService.updateGroup(
          widget.existing!.id,
          name: name,
          tvCodes: codes,
        );
      } else {
        await widget.pairingService.createGroup(name, codes);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'Edit group' : 'New animation group'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Group name',
              hintText: 'e.g. Lobby wall',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          const Text(
            'Animation order (drag to reorder - the snake starts at #1 and '
            'moves left to right, screen by screen, down the list)',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_ordered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No TVs added yet.', style: TextStyle(color: Colors.grey)),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ordered.length,
              // ignore: deprecated_member_use
              onReorder: _reorder,
              itemBuilder: (context, index) {
                final tv = _ordered[index];
                return Card(
                  key: ValueKey(tv.code),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(tv.nickname),
                    subtitle: Text(tv.connected ? 'Connected' : 'Disconnected'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _remove(tv),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          const Text('Available TVs', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_available.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('All TVs are already in this group.', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._available.map(
              (tv) => Card(
                child: ListTile(
                  leading: Icon(tv.connected ? Icons.tv : Icons.tv_off),
                  title: Text(tv.nickname),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _add(tv),
                  ),
                  onTap: () => _add(tv),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
