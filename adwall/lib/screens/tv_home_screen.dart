import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../services/pairing_service.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final _pairingService = PairingService();
  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  final _connectFocusNode = FocusNode();

  bool _submitting = false;
  String? _error;
  String? _connectedNickname;
  String? _connectedCode;
  List<PlaylistItem> _playlist = [];
  int _selectedIndex = 0;
  StreamSubscription<Map<String, dynamic>>? _pairingSub;

  Future<void> _loadSavedPairing() async {
    try {
      final saved = await _pairingService.getSavedPairing();
      if (!mounted || saved == null) return;
      setState(() {
        _connectedCode = saved.code;
        _connectedNickname = saved.nickname;
      });
      _listenForMedia(saved.code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit pairing code.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tvDeviceId = await _pairingService.getDeviceId();
      final nickname = await _pairingService.claimCode(code, tvDeviceId: tvDeviceId);
      await _pairingService.savePairing(code: code, nickname: nickname);
      if (!mounted) return;
      setState(() {
        _connectedNickname = nickname;
        _connectedCode = code;
        _selectedIndex = 0;
      });
      _listenForMedia(code);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _disconnect() async {
    await _pairingService.clearPairing();
    await _pairingSub?.cancel();
    if (!mounted) return;
    setState(() {
      _connectedNickname = null;
      _connectedCode = null;
      _playlist = [];
      _error = null;
    });
  }

  void _listenForMedia(String code) {
    _pairingSub?.cancel();
    _pairingSub = _pairingService.watchPairing(code).listen((data) {
      final raw = data['playlist'] as List<dynamic>?;
      if (!mounted || raw == null) return;
      setState(() {
        _playlist = raw
            .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
            .map((item) => PlaylistItem(
                  mediaType: item.mediaType,
                  mediaUrl: _pairingService.resolveMediaUrl(item.mediaUrl),
                  durationSeconds: item.durationSeconds,
                ))
            .toList();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _loadSavedPairing();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _codeFocusNode.hasFocus) {
      _connectFocusNode.requestFocus();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _codeController.dispose();
    _codeFocusNode.dispose();
    _connectFocusNode.dispose();
    _pairingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.link),
                selectedIcon: Icon(Icons.link_rounded),
                label: Text('Pairing'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.campaign_outlined),
                selectedIcon: Icon(Icons.campaign),
                label: Text('Ads'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _selectedIndex == 0 ? _buildPairingPage() : _buildAdsPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildPairingPage() {
    final connected = _connectedCode != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: connected ? _buildConnectedState() : _buildPairingForm(),
      ),
    );
  }

  Widget _buildConnectedState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 72, color: Colors.green),
        const SizedBox(height: 20),
        const Text('Connected to this phone', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(_connectedNickname ?? '', style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          onPressed: _disconnect,
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }

  Widget _buildPairingForm() {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tv, size: 64),
          const SizedBox(height: 18),
          const Text('Enter pairing code', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 24),
          SizedBox(
            width: 280,
            child: FocusTraversalOrder(
              order: const NumericFocusOrder(1),
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
                  SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
                },
                child: TextField(
                  controller: _codeController,
                  focusNode: _codeFocusNode,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 32, letterSpacing: 8),
                  decoration: const InputDecoration(counterText: ''),
                  onSubmitted: (_) => _submitCode(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FocusTraversalOrder(
            order: const NumericFocusOrder(2),
            child: FilledButton(
              focusNode: _connectFocusNode,
              onPressed: _submitting ? null : _submitCode,
              child: Text(_submitting ? 'Connecting...' : 'Connect'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildAdsPage() {
    if (_connectedCode == null) {
      return const Center(child: Text('Pair this TV with a phone to receive ads.'));
    }
    if (_playlist.isEmpty) {
      return const Center(child: Text('No ads have been sent to this TV yet.'));
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: _PlaylistDisplay(playlist: _playlist),
    );
  }
}


class _PlaylistDisplay extends StatefulWidget {
  const _PlaylistDisplay({required this.playlist});

  final List<PlaylistItem> playlist;

  @override
  State<_PlaylistDisplay> createState() => _PlaylistDisplayState();
}

class _PlaylistDisplayState extends State<_PlaylistDisplay> {
  Timer? _timer;
  int _index = 0;
  VideoPlayerController? _controller;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  @override
  void didUpdateWidget(covariant _PlaylistDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist != widget.playlist || _index >= widget.playlist.length) {
      _index = 0;
      _loadCurrent();
    }
  }

  Future<void> _loadCurrent() async {
    final generation = ++_loadGeneration;
    _timer?.cancel();
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();
    if (!mounted || generation != _loadGeneration || widget.playlist.isEmpty) return;

    final item = widget.playlist[_index];
    if (item.mediaType == 'video') {
      final controller = VideoPlayerController.networkUrl(Uri.parse(item.mediaUrl));
      try {
        await controller.initialize();
        if (!mounted || generation != _loadGeneration ||
            !widget.playlist.contains(item)) {
          await controller.dispose();
          return;
        }
        _controller = controller;
        await controller.setLooping(true);
        await controller.play();
        if (mounted && generation == _loadGeneration) setState(() {});
      } catch (_) {
        await controller.dispose();
        return;
      }
    } else if (mounted && generation == _loadGeneration) {
      setState(() {});
    }

    if (!mounted || generation != _loadGeneration) return;
    _timer = Timer(Duration(seconds: item.durationSeconds), _next);
  }

  void _next() {
    if (!mounted || widget.playlist.isEmpty) return;
    _index = (_index + 1) % widget.playlist.length;
    _loadCurrent();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) return const SizedBox.shrink();
    final item = widget.playlist[_index];
    if (item.mediaType == 'video') {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(child: CircularProgressIndicator(color: Colors.white));
      }
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
    return Image.network(
      item.mediaUrl,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.broken_image,
        color: Colors.white54,
        size: 64,
      ),
    );
  }
}
