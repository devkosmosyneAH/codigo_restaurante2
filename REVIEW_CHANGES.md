# Informe de auditoría y cambios

## Alcance y compatibilidad

Se auditó la copia del proyecto para producción manteniendo intacto el flujo de autenticación existente:

`Código Demo o Full → Firebase Authentication → área administrativa`.

La ruta pública canónica continúa siendo `/menu-public`. El área pública no consulta Firebase Authentication y el área administrativa conserva sus providers y rutas protegidas.

## Cambios funcionales y de arquitectura

| Archivo | Cambio | Motivo | Beneficio |
|---|---|---|---|
| `lib/Presentation/services/menu/public_menu_service.dart` | Nueva fuente de datos pública con lecturas separadas de categorías, productos y variantes; usa `onValue` y combina snapshots. | Evitar que el menú público dependa del servicio administrativo o de autenticación. | QR/enlaces públicos sin credenciales y actualización reactiva sin polling periódico. |
| `lib/Presentation/providers/menu/public_menu_provider.dart` | Nuevo provider para el menú público. | Separar estado público de operaciones administrativas. | Menor acoplamiento y control claro de loading/error/actualización. |
| `lib/Presentation/views/menu/menu_public_page.dart` | La vista pública usa `publicMenuProvider`. | Eliminar la dependencia accidental del provider administrativo. | Se preserva `/menu-public` como única ruta de clientes. |
| `lib/Presentation/views/menu/menu_page.dart` | Limpieza compensatoria de imágenes nuevas y borrado de Drive posterior al borrado confirmado del producto. | Evitar imágenes huérfanas y productos sin imagen por orden incorrecto de operaciones. | Mejor consistencia entre Firebase, SQLite y Drive. |
| `lib/Presentation/core/constants/app_constants.dart` | Versión de base local incrementada a 37. | Habilitar migración segura de índices nuevos. | Actualización compatible de instalaciones existentes. |
| `lib/Presentation/core/database/database_tables.dart` | Índice público de categorías por restaurante, estado y orden. | Optimizar consultas de menú. | Menor coste de lectura y mejor escalabilidad por restaurante. |
| `lib/Presentation/core/database/database_helper.dart` | Migración v37 con `CREATE INDEX IF NOT EXISTS`. | Aplicar el índice a bases ya instaladas sin recrearlas. | Migración idempotente y segura. |
| `lib/Presentation/views/reportes/reportes_page.dart` | Eliminación de `_TabRespaldosRedirect`, widget privado sin referencias. | Remover código muerto. | Menor superficie de mantenimiento y menos advertencias potenciales. |

## Seguridad y sincronización

| Archivo | Cambio | Motivo | Beneficio |
|---|---|---|---|
| `database.rules.json` | Se eliminó la lectura global; se limitaron lecturas públicas a `categorias`, `productos`, `variantes` y `public_config`; las escrituras administrativas requieren sesión y pertenencia del usuario. | Las páginas públicas necesitan lectura, no escritura ni acceso a datos internos. | Menor exposición de pedidos, clientes, ventas, usuarios y configuración privada. |
| `database.rules.json` | Se añadió protección para `users` y `auth`. | El flujo de login persiste datos de usuario y necesitaba reglas explícitas. | Compatibilidad con autenticación sin abrir escritura pública. |
| `lib/Presentation/core/sync/sync_cloud_service.dart` | Las operaciones REST autenticadas añaden el ID token vigente. | Las nuevas reglas exigen autenticación en escrituras. | Sincronización administrativa autorizada sin cambiar el flujo de login. |
| `lib/Presentation/services/menu/menu_realtime_database_service.dart` | Las operaciones administrativas REST añaden el ID token vigente. | Alinear el servicio de menú con las reglas. | Escrituras protegidas y consistentes. |
| `assets/env.txt` | Se retiró la configuración con valores reales del entregable. | Evitar distribuir configuración sensible por accidente. | Menor riesgo de exposición; se dejó plantilla en `assets/env.example`. |
| `.gitignore` | Se agregaron `assets/env.txt` y archivos `.env`. | Evitar futuras inclusiones accidentales. | Mejor higiene de secretos. |

## Calidad y formato

Se ejecutó `dart format lib test`; el código quedó formateado. También se retiraron varios campos privados sin uso en datasources locales que estaban silenciados con `ignore`.

## Validación realizada

- `database.rules.json` se validó como JSON.
- Se comprobó que las reglas modificadas no contienen comparaciones `===`.
- Se comprobó que no quedan claves `AIza` dentro de `assets/`.
- El formateador Dart procesó `lib` y `test`.

## Limitaciones conocidas

En este entorno no fue posible completar `flutter pub get`, `flutter analyze` ni `flutter test`: la ejecución offline no encuentra la dependencia `skeletonizer` y la ejecución Flutter queda bloqueada por el estado del SDK/cache local. El análisis Dart directo sin `.dart_tool/package_config.json` produce falsos errores de paquetes ausentes, por lo que no se considera una validación válida del proyecto.

Antes de desplegar, ejecutar en una máquina con dependencias Flutter disponibles:

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
firebase deploy --only database
```

Después del despliegue se debe probar con Firebase Emulator Suite: lectura anónima de las cuatro colecciones públicas, rechazo de lectura de datos internos, y CRUD administrativo autenticado. También conviene validar en producción el flujo de compensación de Drive ante pérdida de red y configurar restricciones de las claves web en Google Cloud/Firebase.

## Inventario de archivos modificados

Además de los archivos descritos arriba, los siguientes archivos fueron formateados con `dart format` o recibieron limpieza de imports/campos sin uso. En estos casos el comportamiento funcional se mantuvo:

```text
lib/Presentation/core/sync/hybrid_sync_orchestrator.dart
lib/Presentation/core/sync/sync_manager.dart
lib/Presentation/data/caja/caja_local_datasource.dart
lib/Presentation/data/caja/caja_local_datasource_impl.dart
lib/Presentation/data/clientes/cliente_local_datasource.dart
lib/Presentation/data/cotizaciones/cotizacion_local_datasource.dart
lib/Presentation/data/cotizaciones/cotizacion_repository.dart
lib/Presentation/data/menu/drive_connection_local_datasource.dart
lib/Presentation/data/menu/llamado_local_datasource.dart
lib/Presentation/data/menu/menu_local_datasource.dart
lib/Presentation/data/menu/menu_local_datasource_impl.dart
lib/Presentation/data/mesas/llamado_local_datasource.dart
lib/Presentation/data/mesas/llamado_local_datasource_impl.dart
lib/Presentation/data/mesas/llamado_repository_impl.dart
lib/Presentation/data/mesas/mesa_local_datasource.dart
lib/Presentation/data/mesas/mesa_local_datasource_impl.dart
lib/Presentation/data/mesas/mesa_repository_impl.dart
lib/Presentation/data/pagina_publica/public_config_datasource.dart
lib/Presentation/data/pagina_publica/public_config_datasource_impl.dart
lib/Presentation/data/pagina_publica/public_config_repository_impl.dart
lib/Presentation/data/pedidos/pedido_local_datasource.dart
lib/Presentation/data/pedidos/pedido_repository_impl.dart
lib/Presentation/data/reportes/reportes_local_datasource_impl.dart
lib/Presentation/data/reservaciones/reserva_local_datasource.dart
lib/Presentation/data/reservaciones/reserva_local_datasource_impl.dart
lib/Presentation/data/reservaciones/reserva_repository_impl.dart
lib/Presentation/data/usuarios/usuario_local_datasource.dart
lib/Presentation/data/usuarios/usuario_local_datasource_impl.dart
lib/Presentation/domain/caja/repositories/caja_repository.dart
lib/Presentation/Models
lib/Presentation/providers
lib/Presentation/services
lib/Presentation/views
lib/Presentation/widgets
test
```

La lista anterior agrupa por directorio los archivos que solo cambiaron por formato; el detalle funcional se encuentra en las tablas de este informe.

## Auditoría responsive mobile-first

| Archivo | Cambio | Motivo | Beneficio |
|---|---|---|---|
| `lib/Presentation/views/home/home_page.dart` | Se verificó el dashboard con `LayoutBuilder`, grid adaptativo de KPIs, `Wrap` para accesos y padding dependiente del ancho. | Evitar una composición fija para móvil y escritorio. | KPIs apilados en teléfonos y distribuidos en columnas en pantallas amplias. |
| `lib/Presentation/views/reportes/reportes_page.dart` | Se conserva el grid KPI basado en `SliverGridWithMaxCrossAxisExtent`, filtros con `Wrap`, pestañas desplazables y subtítulo compacto en móvil. | Reportes debe seguir siendo usable con una mano y sin overflow. | KPIs verticales en móvil, gráficos a ancho disponible y controles que se reorganizan naturalmente. |
| `lib/Presentation/widgets/home/main_scaffold.dart` | Se verificó navegación móvil con `NavigationBar`, menú inferior para destinos adicionales y sidebar desplazable en tablet/escritorio. | Mantener navegación accesible sin duplicar interfaces. | Menos saturación horizontal en teléfonos y aprovechamiento del espacio en escritorio. |
| `lib/Presentation/views/clientes/clientes_page.dart` | El resumen usa ancho dinámico limitado al viewport. | El ancho fijo podía exceder pantallas pequeñas. | Diálogos utilizables en Safari/iPhone sin recorte horizontal. |
| `lib/Presentation/widgets/menu/menu_sync_diagnostics_dialog.dart` | Ancho del diagnóstico limitado dinámicamente al viewport. | Evitar overflow en herramientas internas desde móvil. | El contenido conserva scroll vertical y se adapta a teléfonos. |
| `lib/Presentation/widgets/menu/producto_form_dialog.dart` | Altura disponible considera el teclado mediante `MediaQuery.viewInsetsOf`. | Safari móvil reduce el viewport al abrir el teclado. | Formularios de producto permanecen accesibles sin quedar ocultos. |
| `lib/Presentation/views/menu/menu_public_page.dart` | Se verificó grid público con `LayoutBuilder` y extensión máxima por ancho. | El menú es el principal punto de entrada desde QR. | Tarjetas redistribuidas automáticamente para teléfono, tablet y escritorio. |

La auditoría no introduce pantallas paralelas para móvil/escritorio; usa una sola interfaz responsive. Las tablas de datos de la interfaz no usan `DataTable` rígidas; cuando existen listados largos se mantienen dentro de listas/grid con scroll vertical. Queda recomendada una prueba visual automatizada en Safari iOS real o BrowserStack para confirmar casos extremos de teclado, orientación y zoom del navegador.

## Correcciones posteriores a la primera ejecución

| Archivo | Corrección | Beneficio |
|---|---|---|
| `lib/Presentation/views/menu/menu_public_page.dart` | Se restauró el import de `MenuState`, requerido por la firma del builder de la pantalla pública. | El proyecto vuelve a compilar el menú público sin cambiar su ruta ni su flujo. |
| `lib/Presentation/data/usuarios/usuario_local_datasource_impl.dart` | Se restauró la referencia inyectada a `TenantContext`, que todavía se utiliza al registrar operaciones de eliminación. | Se elimina el error de compilación y se conserva el aislamiento por restaurante. |
