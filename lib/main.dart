import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:restaurant_app/Presentation/app_startup/app_startup.dart';
import 'package:restaurant_app/Presentation/config/routes/app_router.dart';
import 'package:restaurant_app/Presentation/core/di/injection_container.dart';
import 'package:restaurant_app/Presentation/core/firebase/firebase_initializer.dart';
import 'package:restaurant_app/Presentation/core/theme/app_theme.dart';
import 'package:restaurant_app/Presentation/providers/auth/activation_provider.dart';
import 'package:restaurant_app/Presentation/providers/auth/auth_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  return runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.dumpErrorToConsole(details);

        debugPrint('==================== FLUTTER ERROR ====================');
        debugPrint(details.exceptionAsString());
        debugPrintStack(stackTrace: details.stack);
        debugPrint('=======================================================');
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('================ PLATFORM ERROR =================');
        debugPrint(error.toString());
        debugPrintStack(stackTrace: stack);
        debugPrint('=================================================');
        return true;
      };

      try {
        debugPrint('STEP 1 - initializeDesktopWindow');
        await initializeDesktopWindow();

        // La registración es síncrona en la práctica y debe ocurrir antes de
        // construir el router, pero no debe retrasar el primer frame.
        debugPrint('STEP 2 - initDependencies');
        unawaited(initDependencies());

        runApp(const ProviderScope(child: RestaurantApp()));

        // SQLite, Firebase y la restauración de sesión pueden tardar bastante
        // en el primer acceso web. Se ejecutan después de mostrar la UI para
        // evitar una pantalla en blanco durante toda la inicialización.
        unawaited(_initializeServicesInBackground());
      } catch (e, s) {
        debugPrint('================ ERROR EN MAIN =================');
        debugPrint(e.toString());
        debugPrintStack(stackTrace: s);
        debugPrint('================================================');

        rethrow;
      }
    },
    (error, stack) {
      debugPrint('================ ZONE ERROR =================');
      debugPrint(error.toString());
      debugPrintStack(stackTrace: stack);
      debugPrint('==============================================');
    },
  );
}

Future<void> _initializeServicesInBackground() async {
  try {
    debugPrint('STARTUP - inicializando servicios en segundo plano');
    await Future.wait([
      initializeDateFormatting('es', null),
      initializePlatformSpecific(),
      initDatabaseSafely(),
      FirebaseAppInitializer.initialize(),
      sl<ActivationChangeNotifier>().loadStatus(),
    ]);

    debugPrint('STARTUP - restaurando sesión');
    await sl<AuthChangeNotifier>().restoreSession();
    debugPrint('STARTUP - servicios listos');
  } catch (e, s) {
    // La UI ya está visible. Un fallo de un servicio no debe convertir el
    // primer acceso en una pantalla en blanco; cada módulo mostrará su
    // estado de error o reintentará cuando corresponda.
    debugPrint('STARTUP - inicialización parcial: $e');
    debugPrintStack(stackTrace: s);
  }
}

class RestaurantApp extends StatelessWidget {
  const RestaurantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'La Peña • Sistema de Gestión',

      debugShowCheckedModeBanner: false,

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],

      locale: const Locale('es', 'ES'),

      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,

      routerConfig: AppRouter.router,
    );
  }
}
