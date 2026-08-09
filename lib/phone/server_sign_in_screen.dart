import 'dart:async';

import 'package:flutter/material.dart';

import '../server/server_endpoint.dart';
import 'deploy_http_client.dart';
import 'phone_session.dart';
import 'package:ethan_ui/ethan_ui.dart';

class ServerSignInScreen extends StatefulWidget {
  const ServerSignInScreen({required this.session, required this.onSignedIn});

  final PhoneSession session;
  final VoidCallback onSignedIn;

  @override
  State<ServerSignInScreen> createState() => _ServerSignInScreenState();
}

class _ServerSignInScreenState extends State<ServerSignInScreen> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter the shared password from the Mac .env');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.session.signIn(password);
      if (!mounted) return;
      widget.onSignedIn();
    } on ServerRequestException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in to Mac')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text('Shared password', style: EText.section),
          const SizedBox(height: 8),
          Text(
            'Enter the SERVER_PASSWORD from the Mac companion .env. '
            'Same value for every phone on your LAN.',
            style: EText.body,
          ),
          const SizedBox(height: 8),
          Text(serverBaseUrl, style: EText.monoEmphasis),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            style: EText.body,
            decoration: InputDecoration(
              hintText: 'Password',
              filled: true,
              fillColor: EColors.surfaceInset,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: EColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: EColors.border),
              ),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
              ),
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_signIn());
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _signIn,
            child: Text(_busy ? 'Signing in…' : 'Sign in'),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: EText.body.copyWith(color: EColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}
