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
  StreamSubscription<Map<String, dynamic>>? _pairingSub;

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code shown in the admin app.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // TODO: replace with a real persisted device identifier
      // (e.g. android_id / a UUID stored on first launch).
      final tvDeviceId = DateTime.now().millisecondsSinceEpoch.toString();
      final nickname = await _pairingService.claimCode(code, tvDeviceId: tvDeviceId);
      setState(() {
        _connectedNickname = nickname;
        _connectedCode = code;
      });
      _listenForMedia(code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _submitting = false);
    }
  }

  /// Once paired, stay subscribed to the same pairing channel so whatever
  /// the admin pushes to this code (an image or video) shows up here live.
  void _listenForMedia(String code) {
    _pairingSub?.cancel();
    _pairingSub = _pairingService.watchPairing(code).listen((data) {
      final mediaType = data['media_type'] as String?;
      final mediaUrl = data['media_url'] as String?;
      if (mediaUrl == null) return;
      setState(() {
        _mediaType = mediaType;
        _mediaUrl = _pairingService.resolveMediaUrl(mediaUrl);
      });
    });
  }

  String? _mediaType;
  String? _mediaUrl;

  @override
  void initState() {
    super.initState();
    // TextField consumes ArrowDown internally (cursor movement) before it
    // ever reaches a Shortcuts/Actions ancestor, so declarative
    // NextFocusIntent mapping never fires while the code field is focused.
    // Listen at the hardware level instead and move focus explicitly.
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
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
    if (_connectedCode != null) {
      if (_mediaUrl != null) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: _MediaDisplay(mediaType: _mediaType, mediaUrl: _mediaUrl!),
        );
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text('Connected as "$_connectedNickname"', style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 8),
              const Text('Waiting for the admin to send an image or video...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter pairing code', style: TextStyle(fontSize: 28)),
                const SizedBox(height: 24),
                SizedBox(
                  width: 280,
                  child: FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(LogicalKeyboardKey.arrowUp):
                            PreviousFocusIntent(),
                        SingleActivator(LogicalKeyboardKey.arrowDown):
                            NextFocusIntent(),
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
          ),
        ),
      ),
    );
  }
}


/// Full-screen image or video, depending on what the admin pushed.
class _MediaDisplay extends StatefulWidget {
  const _MediaDisplay({required this.mediaType, required this.mediaUrl});

  final String? mediaType;
  final String mediaUrl;

  @override
  State<_MediaDisplay> createState() => _MediaDisplayState();
}

class _MediaDisplayState extends State<_MediaDisplay> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == 'video') {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _controller!
            ..setLooping(true)
            ..play();
        });
    }
  }

  @override
  void didUpdateWidget(covariant _MediaDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaUrl != widget.mediaUrl) {
      _controller?.dispose();
      _controller = null;
      if (widget.mediaType == 'video') {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl))
          ..initialize().then((_) {
            if (!mounted) return;
            setState(() {});
            _controller!
              ..setLooping(true)
              ..play();
          });
      } else {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mediaType == 'video') {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      }
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }

    // Default to image.
    return Center(
      child: Image.network(
        widget.mediaUrl,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image,
          color: Colors.white54,
          size: 64,
        ),
      ),
    );
  }
}
