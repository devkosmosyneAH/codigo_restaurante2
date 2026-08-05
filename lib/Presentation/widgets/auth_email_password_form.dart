import 'package:flutter/material.dart';
import 'package:restaurant_app/Presentation/core/theme/app_colors.dart';

class AuthEmailPasswordForm extends StatelessWidget {
  const AuthEmailPasswordForm({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.onSubmit,
    this.errorText,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final VoidCallback onSubmit;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          enabled: !isLoading,
          decoration: const InputDecoration(
            hintText: 'Correo electrónico',
            labelText: 'Correo electronico',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordController,
          obscureText: true,
          enabled: !isLoading,
          decoration: const InputDecoration(
            hintText: 'Contraseña',
            labelText: 'Contrasena',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: isLoading ? null : onSubmit,
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_rounded),
          label: const Text('Entrar'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }
}
