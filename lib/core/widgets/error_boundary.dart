import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/crash_reporting_service.dart';

class ErrorBoundary extends ConsumerWidget {
  const ErrorBoundary({
    super.key,
    required this.value,
    required this.builder,
    required this.onRetry,
  });

  factory ErrorBoundary.page({
    Key? key,
    required Widget child,
    Future<void> Function()? onRetry,
  }) =>
      ErrorBoundary(
        key: key,
        value: const AsyncData(null),
        onRetry: onRetry ?? () async {},
        builder: (_) => child,
      );

  final AsyncValue<void> value;
  final WidgetBuilder builder;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      data: (_) => builder(context),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        crashReporting.record(error, stack, context: 'ErrorBoundary');
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Qayta urinish'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
