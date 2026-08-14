import 'package:flutter/material.dart';
import '../services/pairing_service.dart';
import 'tv_list_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _pairingService = PairingService();
  final _nicknameController = TextEditingController();

  String? _activeCode;
  bool _generating = false;
  String? _error;

  Future<void> _generateCode() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() => _error = 'Give the TV a nickname first.');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
      _activeCode = null;
    });
    try {
      final code = await _pairingService.createPairingCode(nickname);
      setState(() => _activeCode = code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AdWall Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tv),
            tooltip: 'Manage TVs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TvListScreen(pairingService: _pairingService),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'TV nickname',
                hintText: 'e.g. Lobby Screen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _generating ? null : _generateCode,
              child: Text(_generating ? 'Generating...' : 'Add TV'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_activeCode != null) ...[
              const SizedBox(height: 32),
              _PairingStatus(code: _activeCode!, pairingService: _pairingService),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairingStatus extends StatelessWidget {
  const _PairingStatus({required this.code, required this.pairingService});

  final String code;
  final PairingService pairingService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: pairingService.watchPairing(code),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final paired = data?['status'] == 'paired';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Enter this code on the TV'),
                const SizedBox(height: 8),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      paired ? Icons.check_circle : Icons.hourglass_top,
                      color: paired ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(paired ? 'TV connected' : 'Waiting for TV...'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
