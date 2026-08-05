import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restaurant_app/Presentation/core/theme/app_colors.dart';
import 'package:restaurant_app/Presentation/core/constants/app_constants.dart';
import 'package:restaurant_app/Presentation/providers/auth/auth_provider.dart';
import 'package:restaurant_app/Presentation/widgets/auth_email_password_form.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _entranceController;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _contentScale;
  late final Animation<double> _footerOpacity;
  bool _isLoading = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _contentOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0, 0.78, curve: Curves.easeOut),
    );
    _contentScale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.9, curve: Curves.easeOutBack),
      ),
    );
    _footerOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    final auth = sl<AuthChangeNotifier>();
    final result = await auth.loginWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    setState(() {
      _isLoading = false;
    });
    if (result != null) {
      setState(() => _errorText = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              Expanded(
                child: FadeTransition(
                  opacity: _contentOpacity,
                  child: ScaleTransition(
                    scale: _contentScale,
                    alignment: Alignment.topCenter,
                    child: Center(
                      child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.72),
                                width: 6,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.24),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/images/logo_la_pena.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.restaurant_rounded,
                                  size: 40,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(40),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.16),
                              ),
                            ),
                            child: const Text(
                              'PANEL DE OPERACIONES',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppConstants.appName,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AppConstants.appFullName,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              letterSpacing: 0.12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Inicia sesión con Firebase',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                22,
                                24,
                                24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Bienvenido de nuevo',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Text(
                                    'Accede a la administración de tu restaurante.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  AuthEmailPasswordForm(
                                    emailController: _emailController,
                                    passwordController: _passwordController,
                                    isLoading: _isLoading,
                                    onSubmit: _submit,
                                    errorText: _errorText,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.shield_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Seguridad activa: después de 3 intentos fallidos el acceso se bloquea temporalmente. Cambia los PIN iniciales desde Usuarios.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
              ),

              FadeTransition(
                opacity: _footerOpacity,
                child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.chevron_left_rounded,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Desarrollado por DevKosmosyne',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: _showSupportDialog, /*
                        final messenger = ScaffoldMessenger.of(context);
                        messenger.hideCurrentMaterialBanner();

                        messenger.showMaterialBanner(
                          MaterialBanner(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            forceActionsBelow: true,
                            content: Container(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                                border: Border.all(color: Colors.grey.shade100),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Header
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.support_agent_rounded,
                                          color: AppColors.primary,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Soporte DevKosmosyne',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 16,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Contáctanos directamente o copia los datos',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 16),

                                  // Items
                                  _infoRow(
                                    Icons.language_rounded,
                                    'https://devkosmosyneah.github.io/devkosmosyne-website/',
                                    accentColor: AppColors.primary,
                                    actionLabel: 'Abrir sitio',
                                    actionUri: Uri.parse(
                                      'https://devkosmosyneah.github.io/devkosmosyne-website/',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.email_outlined,
                                    'devkosmosyne@gmail.com',
                                    accentColor: Colors.blueGrey,
                                    actionLabel: 'Enviar correo',
                                    actionUri: Uri(
                                      scheme: 'mailto',
                                      path: 'devkosmosyne@gmail.com',
                                      queryParameters: {
                                        'subject': 'Soporte de La Peña Bar&House',
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.phone_outlined,
                                    '+593 992380201',
                                    accentColor: Colors.teal,
                                    actionLabel: 'Llamar',
                                    actionUri: Uri.parse('tel:+593992380201'),
                                  ),
                                  const SizedBox(height: 8),
                                  _infoRow(
                                    Icons.chat_rounded,
                                    '+593 992380201',
                                    accentColor: const Color(0xFF25D366),
                                    actionLabel: 'WhatsApp',
                                    actionUri: Uri.parse(
                                      'https://wa.me/593992380201?text=Hola%20DevKosmosyne%2C%20necesito%20soporte%20con%20La%20Pe%C3%B1a.',
                                    ),
                                  ),

                                  const SizedBox(height: 14),

                                  // Botón cerrar
                                  SizedBox(
                                    width: double.infinity,
                                    child: TextButton(
                                      onPressed: () =>
                                          messenger.hideCurrentMaterialBanner(),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Cerrar',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            actions: const [
                              SizedBox.shrink(),
                            ], // Ocultamos las actions por defecto
                          ),
                        );
                      },
                      */
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        minimumSize: const Size(100, 42),
                      ),
                      child: const Text('Soporte'),
                    ),
                  ],
                ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _showSupportDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar soporte',
      barrierColor: Colors.black.withValues(alpha: 0.34),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 30,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.support_agent_rounded,
                                  color: AppColors.primary,
                                  size: 25,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Soporte DevKosmosyne',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Contáctanos directamente o copia los datos',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _infoRow(
                            Icons.language_rounded,
                            'https://devkosmosyneah.github.io/devkosmosyne-website/',
                            accentColor: AppColors.primary,
                            actionLabel: 'Abrir sitio',
                            actionUri: Uri.parse(
                              'https://devkosmosyneah.github.io/devkosmosyne-website/',
                            ),
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.email_outlined,
                            'devkosmosyne@gmail.com',
                            accentColor: Colors.blueGrey,
                            actionLabel: 'Enviar correo',
                            actionUri: Uri(
                              scheme: 'mailto',
                              path: 'devkosmosyne@gmail.com',
                              queryParameters: {
                                'subject': 'Soporte de La Peña Bar&House',
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.phone_outlined,
                            '+593 992380201',
                            accentColor: Colors.teal,
                            actionLabel: 'Llamar',
                            actionUri: Uri.parse('tel:+593992380201'),
                          ),
                          const SizedBox(height: 8),
                          _infoRow(
                            Icons.chat_rounded,
                            '+593 992380201',
                            accentColor: const Color(0xFF25D366),
                            actionLabel: 'WhatsApp',
                            actionUri: Uri.parse(
                              'https://wa.me/593992380201?text=Hola%20DevKosmosyne%2C%20necesito%20soporte%20con%20La%20Pe%C3%B1a.',
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              child: const Text('Cerrar'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _infoRow(
    IconData icon,
    String text, {
    required Color accentColor,
    required String actionLabel,
    required Uri actionUri,
  }) {
    Future<void> openContact() async {
      final opened = await launchUrl(
        actionUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir $actionLabel.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
    }

    Future<void> copyContact() async {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copiado: $text'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  actionLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            onPressed: copyContact,
            icon: Icon(
              Icons.copy_rounded,
              size: 17,
              color: accentColor.withValues(alpha: 0.75),
            ),
          ),
          FilledButton.tonal(
            onPressed: openContact,
            style: FilledButton.styleFrom(
              foregroundColor: accentColor,
              backgroundColor: accentColor.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
