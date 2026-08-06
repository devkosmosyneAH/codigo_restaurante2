import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:restaurant_app/Presentation/services/backup_access.dart'
    as backup;
import 'package:restaurant_app/Presentation/widgets/skeleton_loader.dart';

/// Gestión de respaldos locales.
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'es');
  late Future<Map<String, dynamic>> _overview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _overview = backup.getBackupOverview();

  Future<void> _create() async {
    setState(() => _busy = true);
    final ok = await backup.createManualBackup();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reload();
    });
    _message(ok ? 'Respaldo local creado.' : 'No se pudo crear el respaldo.');
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar respaldo'),
        content: Text('¿Eliminar "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await backup.deleteBackup(name);
    if (!mounted) return;
    setState(_reload);
    _message(ok ? 'Respaldo eliminado.' : 'No se pudo eliminar el respaldo.');
  }

  Future<void> _restore(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: Text(
          'Se reemplazarán los datos locales por "$name". ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await backup.restoreBackup(name);
    if (!mounted) return;
    _message(
      ok
          ? 'Respaldo restaurado. Reinicia la aplicación.'
          : 'No se pudo restaurar el respaldo.',
    );
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Respaldos locales')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _overview,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppLoadingView(message: 'Revisando respaldos...');
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 42),
                  const SizedBox(height: 12),
                  const Text('No se pudieron revisar los respaldos.'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => setState(_reload),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final entries =
            (data['backups'] as List<dynamic>? ?? const <dynamic>[]);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.storage_rounded, size: 36),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Los respaldos se guardan localmente en este dispositivo/navegador.',
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _create,
                      icon: const Icon(Icons.backup),
                      label: const Text('Crear'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Aún no hay respaldos locales.')),
              )
            else
              ...entries.map((raw) {
                final item = raw as Map<String, dynamic>;
                final created = item['created'] is DateTime
                    ? item['created'] as DateTime
                    : DateTime.tryParse(item['created']?.toString() ?? '');
                final name = item['name']?.toString() ?? 'respaldo';
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text(name),
                    subtitle: Text(
                      created == null ? '' : _dateFormat.format(created),
                    ),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: 'Restaurar',
                          onPressed: () => _restore(name),
                          icon: const Icon(Icons.restore),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () => _delete(name),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    ),
  );
}
