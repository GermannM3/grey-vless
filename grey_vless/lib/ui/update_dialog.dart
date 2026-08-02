import 'package:flutter/material.dart';

import '../services/update_service.dart';

Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  var progress = 0.0;
  var installing = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: !installing,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Доступно обновление'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Новая версия: ${info.latest}'),
                const SizedBox(height: 8),
                if (installing) ...[
                  LinearProgressIndicator(value: progress > 0 ? progress : null),
                  const SizedBox(height: 8),
                  Text(
                    progress > 0
                        ? 'Скачано ${(progress * 100).toStringAsFixed(0)}%'
                        : 'Скачивание…',
                  ),
                ] else
                  const Text(
                    'Скачает сборку с GitHub. Windows: окно закроется на ~5с, затем откроется само '
                    '(файлы в %LOCALAPPDATA%\\Programs\\Grey-vless). '
                    'Если снова предложит обновление — поставьте zip через Установить.cmd вручную.',
                  ),
              ],
            ),
            actions: [
              if (!installing)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Позже'),
                ),
              FilledButton(
                onPressed: installing
                    ? null
                    : () async {
                        setState(() {
                          installing = true;
                          progress = 0;
                        });
                        try {
                          await UpdateService.downloadAndApply(
                            info,
                            onProgress: (v) => setState(() => progress = v),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          if (ctx.mounted) {
                            setState(() => installing = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                child: Text(installing ? 'Подождите…' : 'Обновить'),
              ),
            ],
          );
        },
      );
    },
  );
}
