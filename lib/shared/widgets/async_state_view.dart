import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';

class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({required this.value, required this.data, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(safeErrorMessage(error), textAlign: TextAlign.center),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
