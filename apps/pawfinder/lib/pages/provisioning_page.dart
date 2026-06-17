import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pawfinder/services/device_auth_service.dart';
import 'package:services/providers/device_credentials_provider.dart';

bool get _scannerSupported =>
    kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

class ProvisioningPage extends ConsumerStatefulWidget {
  const ProvisioningPage({super.key});

  @override
  ConsumerState<ProvisioningPage> createState() => _ProvisioningPageState();
}

class _ProvisioningPageState extends ConsumerState<ProvisioningPage> {
  bool _provisioning = false;
  String? _error;

  Future<void> _processPayload(String raw) async {
    if (_provisioning) return;

    DeviceCredentials credentials;
    try {
      final json = decodeProvisioningPayload(raw);
      credentials = DeviceCredentials.fromJson(json);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Invalid Code — not a Pawfinder provisioning payload.',
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _provisioning = true;
        _error = null;
      });
    }

    try {
      final service = await ref.read(deviceAuthServiceProvider.future);

      await service.provision(
        clientId: credentials.clientId,
        clientSecret: credentials.clientSecret,
        domain: credentials.domain,
        audience: credentials.audience,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _provisioning = false;
          _error = 'Provisioning failed: $e';
        });
      }
    }
  }

  Future<void> _showPasteDialog() async {
    final textController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _PastePayloadDialog(controller: textController),
    );

    textController.dispose();

    if (result != null && result.isNotEmpty) {
      await _processPayload(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Provision Device')),
      body: _scannerSupported
          ? _buildScannerView(colorScheme)
          : _buildPasteOnlyView(colorScheme),
    );
  }

  Widget _buildScannerView(ColorScheme colorScheme) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final raw = capture.barcodes.firstOrNull?.rawValue;
            if (raw != null) unawaited(_processPayload(raw));
          },
        ),
        Positioned(
          top: 32,
          left: 0,
          right: 0,
          child: Center(
            child:
                Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Scan the QR code from Beariscope',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(
                      begin: -0.5,
                      end: 0,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    ),
          ),
        ),
        Positioned(
          bottom: 32,
          left: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child:
                      Card(
                            color: colorScheme.errorContainer,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 300.ms)
                          .shake(hz: 4, curve: Curves.easeInOut),
                ),
              FilledButton.tonal(
                    onPressed: _provisioning ? null : _showPasteDialog,
                    child: const Text("Can't scan? Paste JSON instead"),
                  )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 600.ms)
                  .slideY(
                    begin: 0.5,
                    end: 0,
                    delay: 200.ms,
                    duration: 500.ms,
                    curve: Curves.easeOut,
                  ),
            ],
          ),
        ),
        if (_provisioning)
          Container(
            color: Colors.black45,
            child: Center(
              child:
                  Card(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Provisioning device…'),
                            ],
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: 300.ms)
                      .scale(
                        begin: Offset(0.8, 0.8),
                        end: Offset(1.0, 1.0),
                        duration: 300.ms,
                        curve: Curves.easeOut,
                      ),
            ),
          ),
      ],
    );
  }

  Widget _buildPasteOnlyView(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.qr_code_scanner, size: 64, color: Colors.grey)
                .animate()
                .fadeIn(duration: 600.ms)
                .scale(
                  delay: 100.ms,
                  duration: 500.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 16),
            const Text(
                  'Camera scanning is not available on this platform.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                )
                .animate()
                .fadeIn(delay: 200.ms, duration: 600.ms)
                .slideY(begin: 0.3, end: 0, delay: 200.ms, duration: 500.ms),
            const SizedBox(height: 8),
            const Text(
                  'Paste the provisioning code from Beariscope to provision this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                )
                .animate()
                .fadeIn(delay: 300.ms, duration: 600.ms)
                .slideY(begin: 0.3, end: 0, delay: 300.ms, duration: 500.ms),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Card(
                    color: colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .shake(hz: 4, curve: Curves.easeInOut),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
                  onPressed: _provisioning ? null : _showPasteDialog,
                  icon: const Icon(Icons.paste),
                  label: const Text('Paste Provisioning code'),
                )
                .animate()
                .fadeIn(delay: 400.ms, duration: 600.ms)
                .slideY(
                  begin: 0.3,
                  end: 0,
                  delay: 400.ms,
                  duration: 500.ms,
                  curve: Curves.easeOut,
                ),
            if (_provisioning) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Center(child: Text('Provisioning device…')),
            ],
          ],
        ),
      ),
    );
  }
}

class _PastePayloadDialog extends StatefulWidget {
  const _PastePayloadDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_PastePayloadDialog> createState() => _PastePayloadDialogState();
}

class _PastePayloadDialogState extends State<_PastePayloadDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste Provisioning Code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Paste the provisioning code from Beariscope below.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.controller,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Base64 code or JSON',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(widget.controller.text.trim()),
          child: const Text('Provision'),
        ),
      ],
    );
  }
}
