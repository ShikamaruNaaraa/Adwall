import 'package:flutter/material.dart';

import '../services/pairing_service.dart';
import 'admin_home_screen.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _service = PairingService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _submitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await _service.adminLogin(
        username: username,
        password: password,
      );

      if (!mounted) return;

      var loginResult = result;
      if (result.mustChangePassword) {
        final newPassword = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => _ForcedPasswordChangeScreen(
              service: _service,
              username: result.username,
              currentPassword: password,
            ),
          ),
        );
        if (newPassword == null) {
          setState(() => _submitting = false);
          return;
        }
        // Changing the password revokes the token issued above, so log in
        // again to get a fresh, valid session token.
        loginResult = await _service.adminLogin(
          username: username,
          password: newPassword,
        );
      }

      await _service.saveLoggedInAdmin(loginResult.username, token: loginResult.token);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Admin Login',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleLogin(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _handleLogin,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ForcedPasswordChangeScreen extends StatefulWidget {
  const _ForcedPasswordChangeScreen({
    required this.service,
    required this.username,
    required this.currentPassword,
  });

  final PairingService service;
  final String username;
  final String currentPassword;

  @override
  State<_ForcedPasswordChangeScreen> createState() =>
      _ForcedPasswordChangeScreenState();
}

class _ForcedPasswordChangeScreenState
    extends State<_ForcedPasswordChangeScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _submitting = false;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;

  static const _passwordHint =
      'At least 8 characters, with at least 1 letter and 1 number.';

  bool _isValidPassword(String password) {
    return password.length >= 8 &&
        RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password);
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (!_isValidPassword(newPassword)) {
      setState(() => _error = _passwordHint);
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.service.changeAdminPassword(
        username: widget.username,
        currentPassword: widget.currentPassword,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.of(context).pop(newPassword);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set a new password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'This is your first login. Please choose a new password.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: _passwordHint,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        );
                      },
                    ),
                  ),
                  obscureText: _obscureNewPassword,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(
                          () => _obscureConfirmPassword =
                              !_obscureConfirmPassword,
                        );
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleSubmit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _handleSubmit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
