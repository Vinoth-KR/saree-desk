import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _google() async {
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: AppConfig.redirectUrl,
            authScreenLaunchMode: LaunchMode.externalApplication,
          );
    } catch (e) {
      if (mounted) showError(context, 'Google sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Email + password. Accounts are created by the owner in the Supabase dashboard
  /// (sign-ups are disabled); shop access is still gated by business_members.
  Future<void> _signInWithPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@') || _password.text.isEmpty) {
      showError(context, 'Enter your email and password');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).auth.signInWithPassword(email: email, password: _password.text);
    } on AuthException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (e) {
      if (mounted) showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandLogo(size: 150)),
                  const SizedBox(height: 12),
                  Text(AppConfig.appName,
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Private shop inventory', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 28),
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: !_showPassword,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _busy ? null : _signInWithPassword(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? 'Hide password' : 'Show password',
                              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _signInWithPassword,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _google,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in with Google'),
                  ),
                  const SizedBox(height: 4),
                  Text('Google needs one-time setup in Supabase (see README_SETUP.md).',
                      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NotAuthorizedScreen extends ConsumerWidget {
  const NotAuthorizedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(supabaseProvider).auth.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 64),
              const SizedBox(height: 16),
              Text('Not authorized for this shop',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('You are signed in as $email, but this account has not been given access yet.'
                  'Please contact the shop administrator and ask them to add this email under '
                  'Tools > Team and roles. Then tap "Check again".',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (email.isNotEmpty)
                FilledButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy my email to send'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: email));
                    if (context.mounted) showInfo(context, 'Copied $email');
                  },
                ),
              if (email.isNotEmpty) const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(membershipProvider),
                child: const Text('Check again'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupNeededScreen extends StatelessWidget {
  const SetupNeededScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Supabase is not configured.\n\nRun with:\nflutter run --dart-define-from-file=env.json\n\n'
                'See README_SETUP.md.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
