import 'package:flutter/material.dart';

import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/models/contact.dart';
import '../../data/models/media_item.dart';
import '../../data/repositories/contact_repository.dart';
import '../media/media_library_screen.dart';

/// Проверка формы: какое имя увидит телефон и чего не хватает.
class ContactFormCheck {
  const ContactFormCheck({
    required this.displayName,
    required this.firstName,
    required this.lastName,
    required this.ownerMode,
  });

  final String displayName;
  final String firstName;
  final String lastName;
  final bool ownerMode;

  /// Имя в контактах: введённое или, если пусто, настоящее имя.
  String get resolvedDisplayName {
    final shown = displayName.trim();
    if (shown.isNotEmpty) return shown;
    return '${firstName.trim()} ${lastName.trim()}'.trim();
  }

  String? get error {
    if (ownerMode) {
      return firstName.trim().isEmpty ? 'Укажите имя владельца телефона' : null;
    }
    return resolvedDisplayName.isEmpty ? 'Укажите имя в контактах или настоящее имя' : null;
  }
}

/// Новый контакт, изменение контакта или профиль владельца телефона.
class ContactEditScreen extends StatefulWidget {
  const ContactEditScreen({
    super.key,
    required this.deviceId,
    this.characterId,
    this.ownerMode = false,
  });

  final String deviceId;
  final String? characterId;
  final bool ownerMode;

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  final _displayName = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _status = TextEditingController();
  final _note = TextEditingController();

  Contact? _original;
  int? _tone;
  String? _avatarMediaId;
  String? _avatarPath;
  String? _callAudioId;
  String? _callAudioName;
  String? _callVideoId;
  String? _callVideoName;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  Object? _loadError;

  bool get _isNew => widget.characterId == null;

  static const _statusPresets = ['в сети', 'был недавно', 'была недавно', 'был давно', 'была давно'];

  @override
  void initState() {
    super.initState();
    if (_isNew) {
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_displayName, _firstName, _lastName, _phone, _status, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.characterId;
    if (id == null) return;
    try {
      final contact = await Services.read(context).contacts.view(widget.deviceId, id);
      if (!mounted) return;
      if (contact != null) {
        final c = contact.character;
        _displayName.text = contact.saved ? contact.displayName : '';
        _firstName.text = c.firstName;
        _lastName.text = c.lastName;
        _phone.text = c.phone;
        _status.text = c.statusText;
        _note.text = c.description;
        _tone = c.avatarTone;
        _avatarMediaId = c.avatarMediaId;
        _avatarPath = contact.avatarPath;
        _callAudioId = c.callAudioMediaId;
        _callVideoId = c.callVideoMediaId;
        final services = Services.read(context);
        if (_callAudioId != null) {
          _callAudioName = (await services.media.repository.byId(_callAudioId!))?.originalName;
        }
        if (_callVideoId != null) {
          _callVideoName = (await services.media.repository.byId(_callVideoId!))?.originalName;
        }
      }
      if (!mounted) return;
      setState(() {
        _original = contact;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _changed([Object? _]) {
    if (!_dirty) setState(() => _dirty = true);
  }

  ContactFormCheck get _check => ContactFormCheck(
        displayName: _displayName.text,
        firstName: _firstName.text,
        lastName: _lastName.text,
        ownerMode: widget.ownerMode,
      );

  Future<void> _save() async {
    final check = _check;
    final error = check.error;
    if (error != null) {
      _snack(error);
      return;
    }
    setState(() => _saving = true);
    final services = Services.read(context);
    try {
      await services.contacts.save(
        deviceId: widget.deviceId,
        characterId: widget.characterId,
        displayName: widget.ownerMode ? null : check.resolvedDisplayName,
        draft: CharacterDraft(
          firstName: _firstName.text,
          lastName: _lastName.text,
          phone: _phone.text,
          statusText: _status.text,
          tone: _tone,
          description: _note.text,
          avatarMediaId: _avatarMediaId,
          callAudioMediaId: _callAudioId,
          callVideoMediaId: _callVideoId,
        ),
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('Контакт не сохранён: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Не удалось сохранить');
    }
  }

  Future<void> _pickPhoto() async {
    final items = await importMedia(context, MediaKind.photo);
    if (items.isEmpty || !mounted) return;
    setState(() {
      _avatarMediaId = items.first.id;
      _avatarPath = items.first.path;
      _dirty = true;
    });
  }

  Future<void> _pickCallMedia({required bool video}) async {
    final media = await AppNavigator.pickFromLibrary(
      video ? {MediaKind.video, MediaKind.videoNote} : {MediaKind.audio, MediaKind.voice},
    );
    if (media == null || !mounted) return;
    setState(() {
      if (video) {
        _callVideoId = media.id;
        _callVideoName = media.originalName ?? media.kind.label;
      } else {
        _callAudioId = media.id;
        _callAudioName = media.originalName ?? media.kind.label;
      }
      _dirty = true;
    });
  }

  void _removePhoto() {
    setState(() {
      _avatarMediaId = null;
      _avatarPath = null;
      _dirty = true;
    });
  }

  Future<void> _removeFromContacts() async {
    final original = _original;
    if (original == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Удалить из контактов?',
      message: '«${original.displayName}» исчезнет из контактов этого телефона. '
          'Переписка останется, в ней будет виден номер.',
      confirmLabel: 'Удалить',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final services = Services.read(context);
    try {
      await services.contacts.removeFromDevice(widget.deviceId, original.id);
      if (!mounted) return;
      _dirty = false;
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('Контакт не удалён: $error');
      if (mounted) _snack('Не удалось удалить контакт');
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showConfirmDialog(
      context,
      title: 'Выйти без сохранения?',
      message: 'Изменения будут потеряны.',
      confirmLabel: 'Выйти',
      destructive: true,
    );
    if (leave && mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String get _title {
    if (widget.ownerMode) return 'Мой профиль';
    if (_isNew) return 'Новый контакт';
    return _original?.saved == false ? 'Добавить в контакты' : 'Изменить контакт';
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final Widget body;
    if (_loading) {
      body = const LoadingState();
    } else if (_loadError != null) {
      body = ErrorState(message: 'Не удалось загрузить данные.', onRetry: () {
        setState(() {
          _loadError = null;
          _loading = true;
        });
        _load();
      });
    } else {
      body = _buildForm(context);
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: Text(_title, style: tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: _loading || _saving || _loadError != null ? null : _save,
              child: const Text('Готово'),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final rc = context.rc;
    final previewName = widget.ownerMode
        ? '${_firstName.text} ${_lastName.text}'.trim()
        : _check.resolvedDisplayName;
    const gap = SizedBox(height: Space.m);
    return ListView(
      padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.xl, Space.l, Space.xxl)),
      children: [
        Center(
          child: Avatar(
            name: previewName.isEmpty ? '?' : previewName,
            size: 88,
            tone: _tone,
            imagePath: _avatarPath,
          ),
        ),
        const SizedBox(height: Space.s),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Space.s,
          children: [
            TextButton.icon(
              onPressed: _saving ? null : _pickPhoto,
              icon: const Icon(AppIcons.addPhoto, size: 20),
              label: Text(_avatarMediaId == null ? 'Выбрать фото' : 'Другое фото'),
            ),
            if (_avatarMediaId != null)
              TextButton(
                onPressed: _saving ? null : _removePhoto,
                style: TextButton.styleFrom(foregroundColor: rc.textSecondary),
                child: const Text('Убрать фото'),
              ),
          ],
        ),
        if (_avatarMediaId == null) ...[
          const SizedBox(height: Space.xs),
          _TonePicker(
          selected: _tone,
          previewKey: previewName,
          onSelect: (tone) {
            setState(() => _tone = tone);
            _changed();
          },
          ),
        ],
        const SizedBox(height: Space.xl),
        if (!widget.ownerMode) ...[
          ReplikaTextField(
            controller: _displayName,
            label: 'Имя в контактах',
            helper: 'Так контакт подписан на этом телефоне: «Мама», «Работа»…',
            onChanged: (value) => setState(() => _dirty = true),
          ),
          gap,
        ],
        ReplikaTextField(
          controller: _firstName,
          label: 'Имя',
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => setState(() => _dirty = true),
        ),
        gap,
        ReplikaTextField(
          controller: _lastName,
          label: 'Фамилия',
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => setState(() => _dirty = true),
        ),
        gap,
        ReplikaTextField(
          controller: _phone,
          label: 'Телефон',
          keyboardType: TextInputType.phone,
          textCapitalization: TextCapitalization.none,
          helper: 'Номер для кадра — согласованный с площадкой.',
          onChanged: _changed,
        ),
        gap,
        ReplikaTextField(
          controller: _status,
          label: 'Статус',
          textCapitalization: TextCapitalization.none,
          onChanged: _changed,
        ),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            for (final preset in _statusPresets)
              ActionChip(
                label: Text(preset),
                onPressed: () {
                  _status.text = preset;
                  _changed();
                },
              ),
          ],
        ),
        gap,
        ReplikaTextField(
          controller: _note,
          label: 'Заметка для оператора',
          helper: 'В кадре не показывается.',
          maxLines: 4,
          onChanged: _changed,
        ),
        if (!widget.ownerMode) ...[
          const SectionLabel('Для постановочных звонков'),
          SettingsTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Голос собеседника',
            subtitle: _callAudioId == null ? 'Не выбран — в разговоре тишина' : (_callAudioName ?? 'Выбран'),
            onTap: () => _pickCallMedia(video: false),
          ),
          SettingsTile(
            icon: AppIcons.videoOutlined,
            title: 'Видео собеседника',
            subtitle: _callVideoId == null ? 'Не выбрано — в видеозвонке его аватар' : (_callVideoName ?? 'Выбрано'),
            onTap: () => _pickCallMedia(video: true),
          ),
          if (_callAudioId != null || _callVideoId != null)
            TextButton(
              onPressed: () => setState(() {
                _callAudioId = _callVideoId = _callAudioName = _callVideoName = null;
                _dirty = true;
              }),
              child: const Text('Убрать материалы звонков'),
            ),
        ],
        if (!widget.ownerMode && !_isNew && _original?.saved == true) ...[
          const SizedBox(height: Space.xl),
          Center(
            child: TextButton.icon(
              onPressed: _saving ? null : _removeFromContacts,
              style: TextButton.styleFrom(foregroundColor: rc.danger),
              icon: const Icon(AppIcons.removeContact),
              label: const Text('Удалить из контактов'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Выбор фирменного тона аватара.
class _TonePicker extends StatelessWidget {
  const _TonePicker({
    required this.selected,
    required this.previewKey,
    required this.onSelect,
  });

  final int? selected;
  final String previewKey;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final current = selected ?? AvatarTones.indexForKey(previewKey);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        for (var i = 0; i < AvatarTones.all.length; i++)
          Semantics(
            button: true,
            selected: i == current,
            label: 'Цвет ${i + 1}',
            child: InkResponse(
              onTap: () => onSelect(i),
              radius: 22,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AvatarTones.all[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i == current ? context.cs.onSurface : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
