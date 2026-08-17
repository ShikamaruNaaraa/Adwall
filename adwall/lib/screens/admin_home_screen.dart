import 'package:flutter/material.dart';
import '../services/pairing_service.dart';
import 'service_ads_screen.dart';
import 'tv_list_screen.dart';
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final _pairingService = PairingService();
  final _nicknameController = TextEditingController();

  late Future<List<TvSummary>> _tvsFuture;
  String? _activeCode;
  bool _generating = false;
  String? _error;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _tvsFuture = _pairingService.fetchTvs();
  }

  Future<void> _refreshTvs() async {
    final future = _pairingService.fetchTvs();
    if (!mounted) return;
    setState(() {
      _tvsFuture = future;
    });
    await future;
  }

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
      await _refreshTvs();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _openAddTv() async {
    _nicknameController.clear();
    setState(() {
      _selectedIndex = 1;
      _error = null;
      _activeCode = null;
    });
  }

  void _openTv(TvSummary tv) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) =>
                TvMediaScreen(pairingService: _pairingService, tv: tv),
          ),
        )
        .then((_) => _refreshTvs());
  }

  void _openServiceAds() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ServiceAdsScreen(pairingService: _pairingService),
      ),
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_selectedIndex == 0 ? 'Home' : 'Add TV')),
      body: _selectedIndex == 0 ? _buildHome() : _buildAddTv(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 1) {
            _openAddTv();
          } else if (index == 2) {
            _openServiceAds();
          } else {
            setState(() => _selectedIndex = 0);
            _refreshTvs();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.add), label: 'Add TV'),
          NavigationDestination(
            icon: Icon(Icons.campaign_outlined),
            selectedIcon: Icon(Icons.campaign),
            label: 'Service Ads',
          ),
        ],
      ),
    );
  }

  Widget _buildHome() {
    return RefreshIndicator(
      onRefresh: _refreshTvs,
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
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 80),
                Icon(Icons.tv_off, size: 56),
                SizedBox(height: 16),
                Center(child: Text('No TVs connected yet.')),
                SizedBox(height: 8),
                Center(child: Text('Tap + to connect a TV.')),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: tvs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final tv = tvs[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: tv.connected
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    child: Icon(
                      tv.connected ? Icons.tv : Icons.tv_off,
                      color: tv.connected ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Text(tv.nickname),
                  subtitle: Text(
                    tv.connected
                        ? (tv.playlist.isEmpty
                            ? 'Connected · No ads set'
                            : 'Connected · ${tv.playlist.length} ad(s)')
                        : 'Disconnected · reconnect with code ${tv.code}',
                    style: tv.connected
                        ? null
                        : TextStyle(color: Colors.red.shade700),
                  ),
                  onTap: () => _openTv(tv),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAddTv() {
    return ListView(
      padding: const EdgeInsets.all(24),
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
        FilledButton.icon(
          onPressed: _generating ? null : _generateCode,
          icon: const Icon(Icons.add),
          label: Text(_generating ? 'Generating...' : 'Add TV'),
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
