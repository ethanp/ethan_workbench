import 'dart:async';

import 'package:flutter/material.dart';

import '../pairing/pairing_screen.dart';
import '../projects/projects_screen.dart';
import 'phone_deploy_session.dart';

/// Loads saved session token and routes to pairing or projects.
class PhoneHome extends StatefulWidget {
  const PhoneHome();

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  final _session = PhoneDeploySession();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _session.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _session.restore();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onPaired() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_session.isPaired) {
      return PairingScreen(session: _session, onPaired: _onPaired);
    }
    return ProjectsScreen(
      trigger: _session.deployTrigger(
        onSessionEnded: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
