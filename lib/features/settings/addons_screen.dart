import 'package:flutter/material.dart';

import '../../app/auto_reply.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../core/util/platform_info.dart';

/// Одно дополнение. Новая функция добавляется записью в [addons] —
/// страницу настроек переделывать не нужно.
class Addon {
  const Addon({required this.id, required this.section, required this.builder});

  final String id;

  /// Подзаголовок группы на экране «Дополнения».
  final String section;
  final WidgetBuilder builder;
}

final List<Addon> addons = [
  Addon(
    id: 'ai',
    section: 'ИИ-собеседник',
    builder: (context) {
      final services = Services.of(context);
      final auto = services.autoReply;
      return Column(children: [
        ValueListenableBuilder<bool>(
          valueListenable: auto.enabled,
          builder: (context, value, _) => SettingsSwitchTile(
            icon: Icons.smart_toy_outlined,
            title: 'Отвечать автоматически',
            subtitle: 'Собеседник в личном чате отвечает сам, пока нет дубля сцены. '
                'Модель работает на телефоне, без интернета.',
            value: value,
            onChanged: auto.setEnabled,
          ),
        ),
        SettingsTile(
          icon: Icons.memory_outlined,
          title: 'Модель и проверка',
          subtitle: 'Выбор файла .gguf, загрузка, замеры скорости',
          onTap: () {
            final page = AutoReplyController.engine?.buildSetupPage();
            if (page == null) return;
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
          },
        ),
      ]);
    },
  ),
  Addon(
    id: 'operator',
    section: 'Съёмка',
    builder: (context) => const SettingsTile(
      icon: Icons.movie_filter_outlined,
      title: 'Операторский режим',
      subtitle: 'Сцены, таймлайн, запуск и сброс дублей',
      onTap: AppNavigator.openOperator,
    ),
  ),
  Addon(
    id: 'kino',
    section: 'Съёмка',
    builder: (context) => const SettingsTile(
      icon: Icons.movie_creation_outlined,
      title: 'Кинорежим',
      subtitle: 'Своя строка состояния, скрытые служебные пункты',
      onTap: AppNavigator.openKino,
    ),
  ),
  Addon(
    id: 'connect',
    section: 'Съёмка',
    builder: (context) => const SettingsTile(
      icon: Icons.settings_remote_outlined,
      title: 'Connect',
      subtitle: 'Управление телефоном с Prop Controller по Wi-Fi',
      onTap: AppNavigator.openConnect,
    ),
  ),
  Addon(
    id: 'notifications',
    section: 'Уведомления',
    builder: (context) {
      final services = Services.of(context);
      return ValueListenableBuilder<bool>(
        valueListenable: services.notificationsEnabled,
        builder: (context, value, _) => SettingsSwitchTile(
          icon: Icons.notifications_outlined,
          title: 'Уведомления о новых сообщениях',
          subtitle: 'Настоящие уведомления со звуком, когда пишет собеседник, '
              'а чат не открыт. Чаты «без звука» уведомлений не дают.',
          value: value,
          onChanged: services.setNotificationsEnabled,
        ),
      );
    },
  ),
  Addon(
    id: 'notifications_test',
    section: 'Уведомления',
    builder: (context) => SettingsTile(
      icon: Icons.notification_add_outlined,
      title: 'Проверить уведомление',
      subtitle: 'Показать пробное уведомление через 3 секунды — успейте свернуть приложение',
      onTap: () async {
        final services = Services.read(context);
        final messenger = ScaffoldMessenger.of(context);
        final allowed = await services.notifications.ensurePermission();
        if (!allowed) {
          messenger.showSnackBar(const SnackBar(
            content: Text('Уведомления запрещены в настройках устройства для этого приложения'),
          ));
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        await services.notifications.showEvent(
          id: 7,
          title: 'Реплика',
          text: 'Пробное уведомление: звук и показ работают.',
        );
      },
    ),
  ),
  Addon(
    id: 'volume_keys',
    section: 'Кнопки громкости',
    builder: (context) {
      final services = Services.of(context);
      return ValueListenableBuilder<bool>(
        valueListenable: services.volumeKeysEnabled,
        builder: (context, value, _) => SettingsSwitchTile(
          icon: Icons.volume_up_outlined,
          title: 'Управлять сценой кнопками громкости',
          subtitle: 'Во время дубля: вверх — «Далее», вниз — «Назад», '
              'обе вместе 1,2 секунды — «Сброс сцены». Вне дубля кнопки '
              'меняют громкость как обычно.',
          value: value,
          onChanged: services.setVolumeKeys,
        ),
      );
    },
  ),
  Addon(
    id: 'reset_toast',
    section: isIOS ? 'Сброс сцены' : 'Кнопки громкости',
    builder: (context) {
      final services = Services.of(context);
      return ValueListenableBuilder<bool>(
        valueListenable: services.resetToastEnabled,
        builder: (context, value, _) => SettingsSwitchTile(
          icon: Icons.restart_alt_rounded,
          title: 'Показывать «Сцена сброшена»',
          subtitle: 'Плашка на 1,5 секунды после сброса кнопками или клавиатурой. '
              'Вибрация при сбросе есть всегда.',
          value: value,
          onChanged: services.setResetToast,
        ),
      );
    },
  ),
];

/// Настройки → Дополнения.
class AddonsScreen extends StatelessWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? section;
    for (final addon in addons) {
      // Кнопки громкости на iOS приложению недоступны — переключателя нет.
      if (isIOS && addon.id == 'volume_keys') continue;
      // ИИ есть только в сборке «Реплика AI».
      if (addon.id == 'ai' && AutoReplyController.engine == null) continue;
      if (addon.section != section) {
        section = addon.section;
        children.add(SectionLabel(addon.section));
      }
      children.add(addon.builder(context));
    }
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(Space.l + 4, Space.xl, Space.l + 4, 0),
      child: Text(
        isIOS
            ? 'На iPhone и iPad кнопки громкости приложению недоступны. Ход сцены '
                'ведут кнопки операторской, скрытый жест двумя пальцами, внешняя '
                'клавиатура (стрелки, пробел, удержание Esc) и Prop Controller.'
            : 'Кнопки громкости работают, пока приложение открыто на экране. '
                'При заблокированном экране или свёрнутом приложении их получает '
                'система — так устроен Android.',
        style: context.tt.bodySmall?.copyWith(color: context.rc.textSecondary),
      ),
    ));
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Дополнения', style: context.tt.titleMedium),
      ),
      body: ListView(
        padding: listPadding(context, const EdgeInsets.only(bottom: Space.xl)),
        children: children,
      ),
    );
  }
}
