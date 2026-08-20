import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/social_auth_controller.dart';

class SocialOtpScreen extends ConsumerStatefulWidget {
  const SocialOtpScreen({super.key});

  @override
  ConsumerState<SocialOtpScreen> createState() => _SocialOtpScreenState();
}

class _SocialOtpScreenState extends ConsumerState<SocialOtpScreen> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(socialAuthControllerProvider).otpDraft,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialAuthControllerProvider);
    final loading = state.status == SocialAuthStatus.verifyingOtp;
    return Scaffold(
      appBar: AppBar(title: const Text('Verifica tu correo')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.mark_email_unread_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Introduce el código enviado a ${state.maskedEmail ?? 'tu correo de MPass'}.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Si no lo encuentras, revisa también la bandeja de spam.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _controller,
                      onChanged: ref
                          .read(socialAuthControllerProvider.notifier)
                          .updateOtpDraft,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'Código OTP',
                      ),
                      validator: (value) {
                        final token = value?.trim() ?? '';
                        if (!RegExp(r'^\d{6,8}$').hasMatch(token)) {
                          return 'Introduce el código recibido.';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _verify(),
                    ),
                    if (state.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: loading ? null : _verify,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Verificar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _verify() {
    if (_formKey.currentState!.validate()) {
      ref
          .read(socialAuthControllerProvider.notifier)
          .verifyOtp(_controller.text);
    }
  }
}
