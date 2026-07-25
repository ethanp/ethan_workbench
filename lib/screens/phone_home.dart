import 'dart:async';

import 'package:flutter/material.dart';

import '../agent/session_store.dart';
import '../api/deploy_client.dart';
import 'pairing_screen.dart';
import 'projects_screen.dart';

/// Loads saved session token and routes to pairing or projects.
class PhoneHome extends StatefulWidget {
  const PhoneHome({super.key});

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  DeployClient? _client;
  bool _loading = true;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final token = await SessionStore.loadToken();
    final client = DeployClient(bearerToken: token);
    if (!mounted) {
      client.close();
      return;
    }
    setState(() {
      _client = client;
      _paired = token != null;
      _loading = false;
    });
  }

  void _onPaired() {
    setState(() => _paired = true);
  }

  Future<void> _onUnauthorized() async {
    await SessionStore.clearToken();
    _client?.setBearerToken(null);
    if (!mounted) return;
    setState(() => _paired = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _client == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_paired) {
      return PairingScreen(
        client: _client!,
        onPaired: _onPaired,
      );
    }
    return ProjectsScreen(
      client: _client!,
      onUnauthorized: _onUnauthorized,
    );
  }
}
