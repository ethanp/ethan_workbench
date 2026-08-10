import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_history_screen.dart';
import '../deploy/deploy_trigger.dart';
import '../projects/projects_screen.dart';
import 'phone_session.dart';
import 'server_sign_in_screen.dart';

/// Loads saved server password and routes to sign-in or projects.
class PhoneHome extends StatefulWidget {
  const PhoneHome();

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  final _session = PhoneSession();
  bool _loading = true;
  int _tabIndex = 0;

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

  void _resetTabsAfterSignIn() {
    setState(() => _tabIndex = 0);
  }

  void _resetTabsAfterSessionEnded() {
    if (!mounted) return;
    setState(() => _tabIndex = 0);
  }

  DeployTrigger get _deployTrigger => _session.deployTrigger(
    onSessionEnded: _resetTabsAfterSessionEnded,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_session.isSignedIn) {
      return ServerSignInScreen(session: _session, onSignedIn: _resetTabsAfterSignIn);
    }
    final trigger = _deployTrigger;
    return Scaffold(
      backgroundColor: EColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          ProjectsScreen(
            trigger: trigger,
            localRun: _session.localRun,
          ),
          DeployHistoryScreen(trigger: trigger),
        ],
      ),
      bottomNavigationBar: EFrostedBottomBar(
        child: ESegmentedControl(
          selectedIndex: _tabIndex,
          onSelected: (index) => setState(() => _tabIndex = index),
          segments: const [
            ESegment(
              icon: Icons.rocket_launch_rounded,
              label: 'Deploy',
            ),
            ESegment(
              icon: Icons.history_rounded,
              label: 'History',
            ),
          ],
        ),
      ),
    );
  }
}
