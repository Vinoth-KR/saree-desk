import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// Private, signed-URL photo. Shows a placeholder when there is no image or it fails.
class SareeImage extends ConsumerWidget {
  const SareeImage({super.key, required this.path, this.size = 72, this.fit = BoxFit.cover, this.radius = 8});
  final String? path;
  final double? size;
  final BoxFit fit;
  final double radius;

  Widget _placeholder(BuildContext context, {IconData icon = Icons.image_not_supported_outlined}) =>
      Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(icon, color: Theme.of(context).colorScheme.outline),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: p == null
          ? _placeholder(context)
          : ref.watch(signedUrlProvider(p)).when(
                data: (url) => Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: fit,
                  errorBuilder: (c, _, _) => _placeholder(c, icon: Icons.broken_image_outlined),
                  loadingBuilder: (c, child, prog) =>
                      prog == null ? child : _placeholder(c, icon: Icons.hourglass_empty),
                ),
                loading: () => _placeholder(context, icon: Icons.hourglass_empty),
                error: (_, _) => _placeholder(context, icon: Icons.broken_image_outlined),
              ),
    );
  }
}

class CopyChip extends StatelessWidget {
  const CopyChip({super.key, required this.text, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(text, style: style ?? Theme.of(context).textTheme.titleLarge),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Copied $text'), duration: const Duration(seconds: 1)));
              }
            },
          ),
        ],
      );
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(e.toString()),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 6),
    ));
}

void showInfo(BuildContext context, String m) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String body, String ok = 'Confirm', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: destructive ? Theme.of(c).colorScheme.error : null,
            foregroundColor: destructive ? Theme.of(c).colorScheme.onError : null,
          ),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'available' => (const Color(0xFF2E7D32), 'Available'),
      'sold' => (const Color(0xFF757575), 'Sold'),
      'confirmed' => (const Color(0xFF2E7D32), 'Confirmed'),
      'draft' => (const Color(0xFFB26A00), 'Draft'),
      'void' => (const Color(0xFFB3261E), 'Void'),
      _ => (Colors.grey, status),
    };
    return Chip(
      label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.08),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Shown instead of data-entry screens for read-only members (the database enforces this too).
class ReadOnlyScreen extends StatelessWidget {
  const ReadOnlyScreen({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('You have view-only access. Ask the owner for editor access to add stock or sell.',
                textAlign: TextAlign.center),
          ),
        ),
      );
}

/// The shop logo from assets/brand/logo.png (rounded like an app tile).
/// Falls back to a neutral icon if the asset is ever missing.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/brand/logo.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Aadav Creations logo',
          errorBuilder: (c, _, _) =>
              Icon(Icons.storefront_outlined, size: size, color: Theme.of(c).colorScheme.primary),
        ),
      );
}
