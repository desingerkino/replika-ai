import 'package:flutter/material.dart';

import '../../app/improv.dart';
import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/dialogs.dart';
import '../../core/design/widgets/form.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import '../../data/models/prepared_reply.dart';
import '../operator/action_summary.dart';
import '../operator/operator_theme.dart';

class _ImprovData {
  const _ImprovData({required this.chats, required this.replies, this.lastHeroText});

  final List<ChatListItem> chats;
  final List<PreparedReply> replies;
  final String? lastHeroText;
}

/// Импровизация: ответы собеседника вручную или из заготовок,
/// очередь ответов для управления из кадра кнопками громкости.
class ImprovScreen extends StatefulWidget {
  const ImprovScreen({super.key});

  @override
  State<ImprovScreen> createState() => _ImprovScreenState();
}

class _ImprovScreenState extends State<ImprovScreen> {
  final TextEditingController _text = TextEditingController();
  ReplyCategory? _category;
  bool _categoryTouched = false;
  int _typingMs = 2000;

  static const _typingOptions = [0, 1000, 2000, 3000, 5000];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<_ImprovData> _load(AppServices services, String deviceId) async {
    // Импровизация — ответы собеседника в личном чате; у группы собеседника нет.
    final chats = (await services.chats.listForDevice(deviceId)).where((c) => !c.chat.isGroup).toList();
    final improv = services.improv;
    if (improv.chatId == null || !chats.any((c) => c.chat.id == improv.chatId)) {
      final sceneChat = services.engine.info?.chatId;
      final preferred = chats.where((c) => c.chat.id == sceneChat).firstOrNull ?? chats.firstOrNull;
      improv.setChat(preferred?.chat.id);
    }
    String? lastHero;
    final chatId = improv.chatId;
    if (chatId != null) {
      final header = await services.chats.header(chatId);
      if (header != null) {
        final last = await services.messages.findTarget(chatId, 'lastOutgoing', header.ownerCharacterId);
        lastHero = last?.text;
      }
    }
    return _ImprovData(chats: chats, replies: await services.replies.list(), lastHeroText: lastHero);
  }

  QueuedReply _reply(String text, {bool fromOwner = false}) =>
      QueuedReply(text: text, typingMs: fromOwner ? 0 : _typingMs, fromOwner: fromOwner);

  Future<void> _sendNow(String text, {bool fromOwner = false}) async {
    final services = Services.read(context);
    final chatId = services.improv.chatId;
    if (chatId == null || text.trim().isEmpty) return;
    try {
      await services.improv.sendNow(chatId, _reply(text, fromOwner: fromOwner));
    } catch (error) {
      if (mounted) _snack('Не отправлено: $error');
    }
  }

  void _enqueue(String text, {bool fromOwner = false}) {
    if (text.trim().isEmpty) return;
    Services.read(context).improv.enqueue(_reply(text, fromOwner: fromOwner));
    _snack('В очереди: ${Services.read(context).improv.queue.length}');
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  Future<void> _pickChat(List<ChatListItem> chats) async {
    final improv = Services.read(context).improv;
    final id = await showActionSheet<String>(
      context,
      header: const Text('Чат для импровизации', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      actions: [
        for (final c in chats)
          SheetAction(
            value: c.chat.id,
            icon: Icons.chat_bubble_outline_rounded,
            label: c.displayName,
            selected: c.chat.id == improv.chatId,
          ),
      ],
    );
    if (id != null) {
      improv.setChat(id);
      setState(() => _categoryTouched = false);
    }
  }

  Future<void> _editReply({PreparedReply? reply}) async {
    final services = Services.read(context);
    final controller = TextEditingController(text: reply?.text ?? '');
    var category = reply?.category ?? _category ?? ReplyCategory.neutral;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(reply == null ? 'Новая заготовка' : 'Заготовка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReplikaTextField(controller: controller, label: 'Текст', maxLines: 4),
              const SizedBox(height: Space.m),
              Wrap(
                spacing: Space.s,
                runSpacing: Space.s,
                children: [
                  for (final c in ReplyCategory.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: c == category,
                      onSelected: (_) => setLocal(() => category = c),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (reply != null)
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('delete'),
                style: TextButton.styleFrom(foregroundColor: OperatorPalette.live),
                child: const Text('Удалить'),
              ),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.of(dialogContext).pop('save'), child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    // Контроллер не освобождаем сразу: поле ещё видно во время
    // анимации закрытия диалога.
    final text = controller.text;
    if (result == 'save') await services.replies.save(id: reply?.id, category: category, text: text);
    if (result == 'delete' && reply != null) await services.replies.delete(reply.id);
  }

  Future<void> _clearChat() async {
    final services = Services.read(context);
    final chatId = services.improv.chatId;
    if (chatId == null) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Убрать импровизацию?',
      message: 'Все ответы, отправленные из импровизации в этот чат, будут удалены. '
          'Базовая переписка и сообщения сцен не изменятся.',
      confirmLabel: 'Убрать',
      destructive: true,
    );
    if (!ok) return;
    final count = await services.messages.deleteImprov(chatId);
    if (mounted) _snack('Удалено сообщений: $count');
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Theme(
      data: operatorTheme,
      child: Scaffold(
        appBar: ReplikaTopBar(
          leading: const BackIconButton(),
          title: const Text('Импровизация', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Новая заготовка',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => _editReply(),
            ),
          ],
        ),
        body: ListenableBuilder(
          listenable: services.improv,
          builder: (context, _) => LiveQuery<_ImprovData>(
            tables: const {Tables.preparedReplies, Tables.messages, Tables.chats, Tables.deviceContacts},
            queryKey: '${services.currentDeviceId.value}|${services.improv.chatId}',
            load: () => _load(services, services.currentDeviceId.value),
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) {
                return snapshot.error != null
                    ? ErrorState(message: 'Не удалось открыть импровизацию.', onRetry: snapshot.reload)
                    : const LoadingState();
              }
              return _buildBody(services.improv, data);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ImprovController improv, _ImprovData data) {
    final chat = data.chats.where((c) => c.chat.id == improv.chatId).firstOrNull;
    final suggestions = suggestReplyCategories(data.lastHeroText ?? '');
    final category = _categoryTouched ? _category : suggestions.first;
    final replies = category == null ? data.replies : data.replies.where((r) => r.category == category).toList();
    const dim = TextStyle(color: OperatorPalette.textDim, fontSize: 13);

    return ListView(
      padding: listPadding(context, const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.xxxl)),
      children: [
        OperatorCard(
          onTap: data.chats.isEmpty ? null : () => _pickChat(data.chats),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: OperatorPalette.standby),
              const SizedBox(width: Space.m),
              Expanded(
                child: Text(
                  chat == null ? 'На телефоне нет чатов' : 'Чат: ${chat.displayName}',
                  style: const TextStyle(color: OperatorPalette.text, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: OperatorPalette.textDim),
            ],
          ),
        ),
        const SizedBox(height: Space.s),
        const Text(
          'ИИ-режим не подключён: ответы пишет оператор или выбирает из заготовок. '
          'Подсказка категории — по ключевым словам в реплике героя.',
          style: dim,
        ),
        if (data.lastHeroText != null && data.lastHeroText!.trim().isNotEmpty) ...[
          const SizedBox(height: Space.m),
          Text('Последняя реплика героя: «${data.lastHeroText!.trim()}»',
              style: const TextStyle(color: OperatorPalette.text)),
        ],
        const SectionLabel('Ответ собеседника'),
        ReplikaTextField(controller: _text, label: 'Текст ответа', maxLines: 5),
        const SizedBox(height: Space.s),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('«Печатает…»:', style: TextStyle(color: OperatorPalette.textDim)),
            for (final ms in _typingOptions)
              ChoiceChip(
                label: Text(ms == 0 ? 'нет' : secondsLabel(ms)),
                selected: _typingMs == ms,
                onSelected: (_) => setState(() => _typingMs = ms),
              ),
          ],
        ),
        const SizedBox(height: Space.m),
        PanelButton(
          label: improv.busy ? 'ПЕЧАТАЕТ…' : 'ОТПРАВИТЬ ОТ СОБЕСЕДНИКА',
          icon: Icons.send_rounded,
          color: OperatorPalette.ready,
          foreground: OperatorPalette.background,
          height: 64,
          onPressed: improv.busy || chat == null
              ? null
              : () async {
                  final text = _text.text;
                  _text.clear();
                  await _sendNow(text);
                },
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Expanded(
              child: PanelButton(
                label: 'В ОЧЕРЕДЬ',
                icon: Icons.queue_rounded,
                color: OperatorPalette.line,
                height: 52,
                onPressed: () {
                  _enqueue(_text.text);
                  _text.clear();
                },
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: PanelButton(
                label: 'ОТ ВЛАДЕЛЬЦА',
                icon: Icons.person_rounded,
                color: OperatorPalette.line,
                height: 52,
                onPressed: improv.busy || chat == null
                    ? null
                    : () async {
                        final text = _text.text;
                        _text.clear();
                        await _sendNow(text, fromOwner: true);
                      },
              ),
            ),
          ],
        ),
        const SectionLabel('Заготовки'),
        Wrap(
          spacing: Space.s,
          runSpacing: Space.s,
          children: [
            ChoiceChip(
              label: const Text('Все'),
              selected: category == null,
              onSelected: (_) => setState(() {
                _categoryTouched = true;
                _category = null;
              }),
            ),
            for (final c in ReplyCategory.values)
              ChoiceChip(
                label: Text(suggestions.first == c && !_categoryTouched ? '${c.label} · подсказка' : c.label),
                selected: category == c,
                onSelected: (_) => setState(() {
                  _categoryTouched = true;
                  _category = c;
                }),
              ),
          ],
        ),
        const SizedBox(height: Space.s),
        if (replies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.m),
            child: Text('В этой категории заготовок нет. Добавьте кнопкой вверху.', style: dim),
          ),
        for (final reply in replies)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: OperatorCard(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
              onTap: improv.busy || chat == null ? null : () => _sendNow(reply.text),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () => _editReply(reply: reply),
                      child: Text(reply.text,
                          style: const TextStyle(color: OperatorPalette.text, fontSize: 16)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'В очередь',
                    icon: const Icon(Icons.queue_rounded, color: OperatorPalette.standby),
                    onPressed: () => _enqueue(reply.text),
                  ),
                ],
              ),
            ),
          ),
        const Text('Нажатие — отправить сразу, значок — в очередь, долгое нажатие на текст — изменить.',
            style: dim),
        SectionLabel('Очередь (${improv.queue.length})'),
        if (improv.queue.isEmpty)
          const Text(
            'Соберите ответы заранее, нажмите «В КАДР С ОЧЕРЕДЬЮ» и отдайте телефон. '
            'В кадре громкость вверх отправляет следующий ответ с «печатает…», '
            'громкость вниз отменяет последний.',
            style: dim,
          ),
        for (var i = 0; i < improv.queue.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: OperatorCard(
              padding: const EdgeInsets.fromLTRB(Space.m, Space.xs, Space.xs, Space.xs),
              child: Row(
                children: [
                  Text('${i + 1}. ', style: const TextStyle(color: OperatorPalette.standby, fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      '${improv.queue.items[i].fromOwner ? 'Владелец: ' : ''}${improv.queue.items[i].text}',
                      style: const TextStyle(color: OperatorPalette.text),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Убрать из очереди',
                    icon: const Icon(Icons.close_rounded, color: OperatorPalette.textDim),
                    onPressed: () => improv.removeAt(i),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: Space.s),
        PanelButton(
          label: improv.armed ? 'ОЧЕРЕДЬ ВЗВЕДЕНА — В КАДР' : 'В КАДР С ОЧЕРЕДЬЮ',
          icon: Icons.smartphone_rounded,
          color: OperatorPalette.standby,
          foreground: OperatorPalette.background,
          height: 60,
          onPressed: chat == null || improv.queue.isEmpty
              ? null
              : () {
                  improv.arm(true);
                  AppNavigator.showInFrame(chat.chat.id);
                },
        ),
        const SizedBox(height: Space.s),
        Row(
          children: [
            Expanded(
              child: PanelButton(
                label: 'СНЯТЬ',
                color: OperatorPalette.line,
                height: 48,
                onPressed: improv.armed ? () => improv.arm(false) : null,
              ),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: PanelButton(
                label: 'ОЧИСТИТЬ',
                color: OperatorPalette.line,
                height: 48,
                onPressed: improv.queue.isEmpty ? null : improv.clearQueue,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xl),
        TextButton.icon(
          onPressed: chat == null ? null : _clearChat,
          style: TextButton.styleFrom(foregroundColor: OperatorPalette.live),
          icon: const Icon(Icons.cleaning_services_rounded),
          label: const Text('Убрать импровизацию из этого чата'),
        ),
        if (improv.armed)
          const Text(
            'Пока очередь взведена и дубль сцены не идёт, кнопки громкости управляют очередью, '
            'а не громкостью.',
            style: dim,
          ),
      ],
    );
  }
}
