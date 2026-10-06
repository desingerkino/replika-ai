import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/device.dart';
import '../../data/profile_transfer.dart';

typedef ProfileItem = ({Device device, String ownerName});

/// Сменить профиль с подтверждением (идущая сцена не останавливается).
Future<bool> switchProfile(BuildContext context, ProfileItem target, String currentName) async {
  final services = Services.read(context);
  if (services.currentDeviceId.value == target.device.id) return false;
  final ok = await showConfirmDialog(
    context,
    title: 'Переключить профиль?',
    message: 'Текущий: $currentName\nНовый: ${target.ownerName}'
        '${services.engine.hasTake ? '\n\nТекущая сцена активна. Переключение профиля не остановит сцену.' : ''}',
    confirmLabel: 'Переключить',
  );
  if (!ok) return false;
  await services.setCurrentDevice(target.device.id);
  return true;
}

/// Настройки → Профили телефона.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _create(BuildContext context) async {
    final services = Services.read(context);
    final first = TextEditingController();
    final last = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('Новый профиль'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReplikaTextField(controller: first, label: 'Имя персонажа'),
            const SizedBox(height: Space.s),
            ReplikaTextField(controller: last, label: 'Фамилия'),
            const SizedBox(height: Space.s),
            ReplikaTextField(controller: phone, label: 'Номер для кадра', keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Создать')),
        ],
      ),
    );
    if (ok != true || first.text.trim().isEmpty) return;
    await services.devices.createProfile(firstName: first.text, lastName: last.text, phone: phone.text);
    if (context.mounted) _snack(context, 'Профиль «${first.text.trim()}» создан — пустой телефон персонажа');
  }

  Future<void> _export(BuildContext context, ProfileItem p) async {
    final services = Services.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final json = await services.profiles.export(p.device.id);
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(json)));
      final path = await FilePicker.saveFile(
        dialogTitle: 'Сохранить профиль',
        fileName: 'Профиль ${p.ownerName}.replika.json',
        bytes: bytes,
      );
      messenger.showSnackBar(SnackBar(
        content: Text(path == null ? 'Сохранение отменено' : 'Профиль сохранён (${(bytes.length / 1024).ceil()} КБ)'),
      ));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('Не удалось сохранить профиль')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final services = Services.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(type: FileType.any, allowMultiple: false);
    if (picked.isEmpty) return;
    final bytes = await picked.first.readAsBytes();
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const ProfileImportException('Это не файл профиля «Реплики»');
      await services.profiles.import(Map<String, Object?>.from(decoded));
      messenger.showSnackBar(const SnackBar(content: Text('Профиль импортирован')));
    } on ProfileImportException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on FormatException {
      messenger.showSnackBar(const SnackBar(content: Text('Файл повреждён или это не профиль')));
    }
  }

  Future<void> _menu(BuildContext context, ProfileItem p, bool current) async {
    final services = Services.read(context);
    final choice = await showActionSheet<String>(
      context,
      header: Text(p.ownerName, style: context.tt.titleMedium),
      actions: [
        const SheetAction(value: 'export', icon: Icons.ios_share_rounded, label: 'Экспортировать профиль'),
        if (!current)
          const SheetAction(value: 'delete', icon: Icons.delete_outline_rounded, label: 'Удалить профиль', destructive: true),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'export') await _export(context, p);
    if (choice == 'delete') {
      final ok = await showConfirmDialog(
        context,
        title: 'Удалить профиль «${p.ownerName}»?',
        message: 'Удалятся контакты, чаты, сообщения, звонки и сцены этого телефона. '
            'Сначала можно экспортировать профиль.',
        confirmLabel: 'Удалить',
        destructive: true,
      );
      if (ok) await services.devices.delete(p.device.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: ReplikaTopBar(
        leading: const BackIconButton(),
        title: Text('Профили телефона', style: context.tt.titleMedium),
      ),
      body: ValueListenableBuilder<String>(
        valueListenable: services.currentDeviceId,
        builder: (context, currentId, _) => LiveQuery<List<ProfileItem>>(
          tables: const {Tables.devices, Tables.characters},
          queryKey: currentId,
          load: services.devices.profiles,
          builder: (context, snapshot) {
            final list = snapshot.data;
            if (list == null) return const LoadingState();
            final current = list.where((p) => p.device.id == currentId).firstOrNull;
            return ListView(
              padding: listPadding(context, const EdgeInsets.only(bottom: Space.xxl)),
              children: [
                const SectionLabel('Текущий профиль'),
                if (current != null)
                  ListTile(
                    leading: Avatar(name: current.ownerName, size: 48),
                    title: Text('📱 ${current.ownerName}', style: context.tt.titleMedium),
                    subtitle: Text(current.device.name),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.l),
                  child: Text(
                    'Профиль — отдельный телефон персонажа: свои контакты, чаты, сообщения и звонки. '
                    'Профили не смешиваются. Смена профиля не останавливает идущую сцену.',
                  ),
                ),
                const SectionLabel('Сменить профиль'),
                for (final p in list)
                  ListTile(
                    leading: Avatar(name: p.ownerName, size: 40),
                    title: Text(p.ownerName),
                    subtitle: Text(p.device.name),
                    trailing: p.device.id == currentId
                        ? Icon(Icons.radio_button_checked_rounded, color: context.cs.primary)
                        : const Icon(Icons.radio_button_off_rounded),
                    onTap: () => switchProfile(context, p, current?.ownerName ?? ''),
                    onLongPress: () => _menu(context, p, p.device.id == currentId),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.xs),
                  child: Text('Долгое нажатие на профиль — экспорт или удаление.'),
                ),
                SettingsTile(icon: Icons.person_add_alt_rounded, title: 'Создать профиль', onTap: () => _create(context)),
                SettingsTile(
                  icon: Icons.file_download_outlined,
                  title: 'Импортировать профиль',
                  subtitle: 'Из файла, экспортированного на этом или другом телефоне',
                  onTap: () => _import(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
