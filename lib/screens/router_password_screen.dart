import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openwalla/main.dart';
import 'package:openwalla/widgets/luci_app_bar.dart';

class RouterPasswordScreen extends ConsumerStatefulWidget {
  const RouterPasswordScreen({super.key});

  @override
  ConsumerState<RouterPasswordScreen> createState() =>
      _RouterPasswordScreenState();
}

class _RouterPasswordScreenState extends ConsumerState<RouterPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  bool _isSaving = false;

  bool get _canSave {
    final password = _passwordController.text;
    return !_isSaving &&
        password.length >= 8 &&
        password == _confirmController.text;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Router Password?'),
        content: const Text(
          'Openwalla will update the root password on this router and save the new credential for future connections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final reconnected = await ref
          .read(appStateProvider)
          .changeRouterPassword(_passwordController.text, context: context);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            reconnected
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: reconnected
                ? const Color(0xFF20CF70)
                : Theme.of(context).colorScheme.tertiary,
            size: 40,
          ),
          title: Text(
            reconnected ? 'Password Updated' : 'Password Updated on Router',
          ),
          content: Text(
            reconnected
                ? 'The router accepted the new password and Openwalla reconnected successfully.'
                : 'The router accepted and saved the new password, but Openwalla could not confirm a new login. Reconnect using the new password.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update the router password: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final router = ref.watch(appStateProvider).selectedRouter;
    return Scaffold(
      appBar: const LuciAppBar(title: 'Router Password', showBack: true),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.router_rounded, color: colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            router?.lastKnownHostname?.trim().isNotEmpty == true
                                ? router!.lastKnownHostname!.trim()
                                : router?.ipAddress ?? 'OpenWrt Router',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Set the root password used by Openwalla, LuCI, and SSH. A current password is not required while this app session is authenticated.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isSaving,
                      obscureText: !_passwordVisible,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'New password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        helperText: 'Use at least 8 characters',
                        suffixIcon: IconButton(
                          tooltip: _passwordVisible
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 8) {
                          return 'Enter at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      enabled: !_isSaving,
                      obscureText: !_confirmVisible,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onFieldSubmitted: (_) {
                        if (_canSave) _save();
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _confirmVisible
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: () => setState(
                            () => _confirmVisible = !_confirmVisible,
                          ),
                          icon: Icon(
                            _confirmVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _canSave ? _save : null,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_isSaving ? 'Updating Password' : 'Save Password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
