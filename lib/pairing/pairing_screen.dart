import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_endpoint.dart';
import '../phone/deploy_http_client.dart';
import '../phone/paired_phone_session.dart';
import 'package:ethan_ui/ethan_ui.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({required this.session, required this.onPaired});

  final PairedPhoneSession session;
  final VoidCallback onPaired;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit PIN from the Mac app');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await widget.session.pair(pin);
      if (!mounted) return;
      widget.onPaired();
    } on AgentRequestException catch (error) {
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
      appBar: AppBar(title: const Text('Pair with Mac')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text('Enter pairing PIN', style: EText.section),
          const SizedBox(height: 8),
          Text(
            'On the Mac companion, copy the 6-digit PIN and enter it here. '
            'It refreshes every minute.',
            style: EText.body,
          ),
          const SizedBox(height: 8),
          Text(agentBaseUrl, style: EText.monoEmphasis),
          const SizedBox(height: 24),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: EText.mono.copyWith(fontSize: 28, letterSpacing: 8),
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
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
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_pair());
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: Text(_busy ? 'Pairing…' : 'Pair'),
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
