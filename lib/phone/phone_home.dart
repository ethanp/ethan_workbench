import 'dart:async';

import 'package:ethan_ui/ethan_ui.dart';
import 'package:flutter/material.dart';

import '../deploy/deploy_history_screen.dart';
import '../deploy/deploy_trigger.dart';
import '../pairing/pairing_screen.dart';
import '../projects/projects_screen.dart';
import 'paired_phone_session.dart';

/// Loads saved session token and routes to pairing or projects.
class PhoneHome extends StatefulWidget {
  const PhoneHome();

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  final _session = PairedPhoneSession();
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

  void _onPaired() {
    setState(() => _tabIndex = 0);
  }

  void _onSessionEnded() {
    if (!mounted) return;
    setState(() => _tabIndex = 0);
  }

  DeployTrigger get _deployTrigger => _session.deployTrigger(
    onSessionEnded: _onSessionEnded,
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_session.isPaired) {
      return PairingScreen(session: _session, onPaired: _onPaired);
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
