import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    required this.isLoading,
    required this.child,
  });

  final bool isLoading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return isLoading ? Skeletonizer(enabled: true, child: child) : child;
  }
}

/// Estado de carga reutilizable para evitar pantallas blancas durante
/// consultas locales, Firebase o carga de imágenes.
class AppLoadingView extends StatefulWidget {
  const AppLoadingView({
    super.key,
    this.message = 'Cargando...',
    this.compact = false,
    this.color,
  });

  final String message;
  final bool compact;
  final Color? color;

  @override
  State<AppLoadingView> createState() => _AppLoadingViewState();
}

class _AppLoadingViewState extends State<AppLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    if (!widget.compact) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.color ?? theme.colorScheme.primary;

    if (widget.compact) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
        ),
      );
    }

    return Center(
      child: Semantics(
        liveRegion: true,
        label: widget.message,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = 0.92 + (_controller.value * 0.08);
            return Transform.scale(scale: pulse, child: child);
          },
          child: Card(
            elevation: 0,
            color: theme.colorScheme.surface,
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SkeletonCardPlaceholder extends StatelessWidget {
  const SkeletonCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Bone.text(width: 160),
            const SizedBox(height: 12),
            Bone.text(words: 8),
            const SizedBox(height: 12),
            Bone.text(words: 4),
            const SizedBox(height: 16),
            Row(
              children: [
                Bone.button(
                  width: 96,
                  height: 36,
                  type: BoneButtonType.elevated,
                ),
                const SizedBox(width: 10),
                Bone.button(
                  width: 96,
                  height: 36,
                  type: BoneButtonType.elevated,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SkeletonListPlaceholder extends StatelessWidget {
  const SkeletonListPlaceholder({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: itemCount,
        itemBuilder: (context, index) => const SkeletonCardPlaceholder(),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
      ),
    );
  }
}
