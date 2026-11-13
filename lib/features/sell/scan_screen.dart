import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'cart.dart';

enum ScanOutcome { added, alreadyInCart, sold, notFound }

/// Pure lookup used by the scanner (and unit tests): the scanned text must equal a SKU.
/// Labels carry only the SKU, never the price, so a changed price never makes a label stale.
({ScanOutcome outcome, Saree? saree}) resolveScan(String raw, List<Saree> all, Set<String> inCartIds) {
  final code = raw.trim().toUpperCase();
  final match = all.where((s) => s.sku.toUpperCase() == code).firstOrNull;
  if (match == null) return (outcome: ScanOutcome.notFound, saree: null);
  if (!match.isAvailable) return (outcome: ScanOutcome.sold, saree: match);
  if (inCartIds.contains(match.id)) return (outcome: ScanOutcome.alreadyInCart, saree: match);
  return (outcome: ScanOutcome.added, saree: match);
}

/// Continuous scanner: every recognised available saree is added to the cart and scanning
/// continues, so a whole counter-top can be rung up without leaving the camera.
/// Reads QR codes only. The QR payload is exactly the SKU.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
  );
  final Map<String, DateTime> _lastSeen = {};
  String? _message;
  ScanOutcome? _lastOutcome;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      // Ignore the same code for 2.5 s so one label is not processed repeatedly.
      final seen = _lastSeen[raw];
      if (seen != null && now.difference(seen) < const Duration(milliseconds: 2500)) continue;
      _lastSeen[raw] = now;

      final all = ref.read(sareesProvider).asData?.value ?? const <Saree>[];
      final cart = ref.read(cartProvider);
      final r = resolveScan(raw, all, {for (final l in cart.lines) l.saree.id});
      if (r.outcome == ScanOutcome.added) {
        ref.read(cartProvider.notifier).add(r.saree!);
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
      }
      setState(() {
        _lastOutcome = r.outcome;
        _message = switch (r.outcome) {
          ScanOutcome.added => '${r.saree!.sku} added · ${formatInr(r.saree!.markedPricePaise)}\n${r.saree!.description}',
          ScanOutcome.alreadyInCart => '${r.saree!.sku} is already in this sale',
          ScanOutcome.sold => '${r.saree!.sku} is already SOLD',
          ScanOutcome.notFound => 'No saree with code "${raw.trim()}"',
        };
      });
      break; // one label per frame
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = ref.watch(cartProvider).lines.length;
    final cs = Theme.of(context).colorScheme;
    final ok = _lastOutcome == ScanOutcome.added;
    final bad = _lastOutcome == ScanOutcome.sold || _lastOutcome == ScanOutcome.notFound;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan to add'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (c, state, _) => IconButton(
              tooltip: 'Torch',
              icon: Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off),
              onPressed: _controller.toggleTorch,
            ),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: _controller.switchCamera,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera permission is off. Enable it for this app in Android settings, or go back and search by SKU.'
                      : 'Camera unavailable (${error.errorCode.name}). Go back and search by SKU.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: ok ? Colors.greenAccent : bad ? Colors.redAccent : Colors.white70, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ok
                      ? Colors.green.shade800
                      : bad
                          ? cs.errorContainer
                          : Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    _message ?? 'Point at the QR code on the label',
                    style: TextStyle(color: bad ? cs.onErrorContainer : Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(cartCount == 0 ? 'Done' : 'Done · $cartCount in sale'),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
