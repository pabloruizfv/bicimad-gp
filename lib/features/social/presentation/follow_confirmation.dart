import 'package:flutter/material.dart';

enum FollowRemovalKind { unfollow, removeFollower }

Future<bool> showFollowRemovalConfirmation(
  BuildContext context, {
  required FollowRemovalKind kind,
  required String displayName,
}) async {
  final isUnfollow = kind == FollowRemovalKind.unfollow;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isUnfollow ? '¿Dejar de seguir?' : '¿Eliminar seguidor?'),
          content: Text(
            isUnfollow
                ? 'Dejarás de seguir a $displayName.'
                : '$displayName dejará de seguirte.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(isUnfollow ? 'Dejar de seguir' : 'Eliminar'),
            ),
          ],
        ),
      ) ??
      false;
}
