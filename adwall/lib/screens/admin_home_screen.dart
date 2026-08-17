import 'dart:async';

import 'package:flutter/material.dart';
import '../services/pairing_service.dart';
import 'admin_login_screen.dart';
import 'group_animation_screen.dart';
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
  VoidCallback? _serviceAdsRefresh;

  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _tvsFuture = _pairingService.fetchTvs();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _pageController.dispose();
    super.dispose();
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

  void _goToPage(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    if (index == 1) {
      _nicknameController.clear();
      setState(() {
        _error = null;
        _activeCode = null;
      });
    } else if (index == 0) {
      _refreshTvs();
    }
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

  Future<bool> _confirmDeleteTv(TvSummary tv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove TV?'),
        content: Text(
          "This unpairs '${tv.nickname}' and clears its ad playlist. "
          'The TV will need a new code to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteTv(TvSummary tv) async {
    try {
      await _pairingService.deleteTv(tv.code);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove TV: $e')),
        );
      }
    } finally {
      await _refreshTvs();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _pairingService.clearLoggedInAdmin();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      (route) => false,
    );
  }


  @override
  Widget build(BuildContext context) {
    const titles = ['Home', 'Add TV', 'Service Ads', 'Group Animation'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_selectedIndex]),
        actions: [
          if (_selectedIndex == 2)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _serviceAdsRefresh,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedIndex = index);
          if (index == 0) _refreshTvs();
        },
        children: [
          _buildHome(),
          _buildAddTv(),
          ServiceAdsScreen(
            pairingService: _pairingService,
            embedded: true,
            onRefreshCallback: (refresh) => _serviceAdsRefresh = refresh,
          ),
          GroupAnimationScreen(pairingService: _pairingService),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _goToPage,
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
          NavigationDestination(
            icon: Icon(Icons.animation_outlined),
            selectedIcon: Icon(Icons.animation),
            label: 'Group Animation',
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
              return Dismissible(
                key: ValueKey(tv.code),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDeleteTv(tv),
                onDismissed: (_) => _deleteTv(tv),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                child: Card(
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
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove TV',
                      onPressed: () async {
                        if (await _confirmDeleteTv(tv)) _deleteTv(tv);
                      },
                    ),
                  ),
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
