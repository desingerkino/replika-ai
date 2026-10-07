import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/live_query.dart';
import '../../app/media_store.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/icons.dart';
import '../../core/design/tokens.dart';
import '../../core/design/widgets/action_sheet.dart';
import '../../core/design/widgets/avatar.dart';
import '../../core/design/widgets/states.dart';
import '../../core/design/widgets/top_bar.dart';
import '../../data/db/tables.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../chats/chat_filter.dart';
import '../../design_system/glass_theme.dart';
import '../../design_system/glass_wallpaper.dart';
import 'chat_glass.dart';
import 'chat_rows.dart';
import 'composer.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';
import 'voice_mini_player.dart';
import '../../data/models/media_item.dart';
import '../calls/calls_screen.dart';
import '../../data/models/call_record.dart';
import '../media/media_kinds.dart';
import '../record/video_note_recorder.dart';
import '../record/voice_recording.dart';
import '../../core/design/adaptive.dart';


enum _MessageAction { reply, copy, favorite, toggleDeleted, delete }

enum _Attach { photoVideo, recordVideoNote, audio, voice, videoNote, library }

/// Открытый чат.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.revealMessageId});

  final String chatId;

  /// Сообщение, к которому нужно прокрутить при открытии (поиск, избранное).
  final String? revealMessageId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  /// Участники группы: id → как записаны на телефоне (null — не группа).
  Map<String, String>? _groupNames;
  Map<String, int>? _groupTones;
  int _groupCount = 0;

  final TextEditingController _composer = TextEditingController();
  final FocusNode _focus = FocusNode();

  AppServices? _services;
  Timer? _draftTimer;
  bool _started = false;
  bool _markingRead = false;
  String _savedDraft = '';
  String? _selectedMessageId;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _revealKey = GlobalKey();
  String? _revealId;
  String? _flashId;
  bool _pendingReveal = false;

  /// Сколько было непрочитанных в момент открытия — для плашки.
  int? _unreadAtOpen;
  QuotedMessage? _replyTo;
  ChatHeader? _header;
  bool _importing = false;

  /// Сообщения, уже показанные на экране: новые появляются с анимацией.
  Set<String>? _seenIds;

  /// Запись голосового жестом на микрофоне (создаётся при первом показе).
  VoiceRecordingController? _voice;
  bool _wasRecording = false;

  AppServices get _s => _services!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(_scheduleDraftSave);
    _revealId = widget.revealMessageId;
    _pendingReveal = _revealId != null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _services = Services.of(context);
    if (!_started) {
      _started = true;
      _services!.openChatId.value = widget.chatId;
      unawaited(_services!.notifications.clearChat(widget.chatId));
      _restoreDraft();
      _voice = VoiceRecordingController(
        capture: RecordVoiceCapture(newPath: () => _services!.media.newRecordingPath('.m4a')),
        register: (path, duration, waveform) =>
            _services!.media.registerVoice(path, duration: duration, waveform: waveform),
        onRecorded: _sendVoice,
        onProblem: (message) {
          if (mounted) _showSnack(message);
        },
      )..addListener(_voiceChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Приложение уходит в фон — черновик сохраняется сразу.
    if (state != AppLifecycleState.resumed) _saveDraftNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _composer.removeListener(_scheduleDraftSave);
    final open = _services?.openChatId;
    if (open != null && open.value == widget.chatId) open.value = null;
    _saveDraftNow();
    _voice?.removeListener(_voiceChanged);
    _voice?.dispose();
    _scroll.dispose();
    _composer.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- Черновик ----------

  Future<void> _restoreDraft() async {
    try {
      final draft = await _s.chats.draftOf(widget.chatId);
      if (!mounted || draft == null || draft.isEmpty || _composer.text.isNotEmpty) {
        return;
      }
      _savedDraft = draft;
      _composer.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
    } catch (error) {
      debugPrint('Черновик не прочитан: $error');
    }
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 700), _saveDraftNow);
  }

  void _saveDraftNow() {
    _draftTimer?.cancel();
    final text = _composer.text;
    if (text == _savedDraft) return;
    _savedDraft = text;
    unawaited(_persistDraft(text));
  }

  Future<void> _persistDraft(String text) async {
    try {
      await _s.chats.saveDraft(widget.chatId, text);
    } catch (error) {
      debugPrint('Черновик не сохранён: $error');
    }
  }

  // ---------- Отправка и прочтение ----------

  Future<void> _send(ChatHeader header) async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _draftTimer?.cancel();
    _savedDraft = '';
    final replyTo = _replyTo;
    setState(() {
      _replyTo = null;
      _unreadAtOpen = 0;
    });
    _composer.clear();
    try {
      await _s.messages.sendText(
        chatId: widget.chatId,
        senderId: header.ownerCharacterId,
        text: text,
        replyToId: replyTo?.messageId,
        sceneId: _s.engine.sceneIdForChat(widget.chatId),
        sentAt: _s.engine.sceneIdForChat(widget.chatId) == null ? null : _s.engine.sceneNow(),
      );
      // ИИ-собеседник (только в сборке «Реплика AI» и при включённом переключателе).
      unawaited(_s.autoReply.onOwnerMessage(widget.chatId));
      if (_scroll.hasClients) {
        unawaited(_scroll.animateTo(0, duration: Motion.normal, curve: Motion.curve));
      }
    } catch (error) {
      debugPrint('Сообщение не отправлено: $error');
      if (!mounted) return;
      if (_composer.text.isEmpty) _composer.text = text;
      setState(() => _replyTo = replyTo);
      _showSnack('Не удалось сохранить сообщение');
    }
  }

  void _markReadIfNeeded(ChatHeader header) {
    if (header.chat.unreadCount == 0 || _markingRead) return;
    _markingRead = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _s.chats.markRead(widget.chatId);
      } catch (error) {
        debugPrint('Не удалось отметить прочитанным: $error');
      } finally {
        _markingRead = false;
      }
    });
  }

  // ---------- Вложения ----------

  Future<void> _attach(ChatHeader header) async {
    FocusScope.of(context).unfocus();
    final choice = await showActionSheet<_Attach>(
      context,
      actions: const [
        SheetAction(value: _Attach.photoVideo, icon: AppIcons.attachPhotoVideo, label: 'Фото или видео'),
        SheetAction(value: _Attach.recordVideoNote, icon: AppIcons.attachVideoNoteRecord, label: 'Записать видеосообщение'),
        SheetAction(value: _Attach.voice, icon: AppIcons.microphone, label: 'Голосовое сообщение (файл)'),
        SheetAction(value: _Attach.videoNote, icon: AppIcons.attachVideoNoteFile, label: 'Видеосообщение (файл)'),
        SheetAction(value: _Attach.audio, icon: AppIcons.attachAudio, label: 'Аудиофайл'),
        SheetAction(value: _Attach.library, icon: AppIcons.attachLibrary, label: 'Из медиатеки'),
      ],
    );
    if (choice == null || !mounted) return;

    List<MediaItem> items;
    if (choice == _Attach.recordVideoNote) {
      final recorded = await recordVideoNote(context);
      items = recorded == null ? const [] : [recorded];
    } else if (choice == _Attach.library) {
      final picked = await AppNavigator.pickFromLibrary(MediaKind.values.toSet());
      items = picked == null ? const [] : [picked];
    } else {
      setState(() => _importing = true);
      try {
        items = await _s.media.pickAndImport(
          switch (choice) {
            _Attach.photoVideo => PickSource.media,
            _Attach.voice || _Attach.audio => PickSource.audio,
            _Attach.videoNote => PickSource.video,
            _Attach.library || _Attach.recordVideoNote => PickSource.any,
          },
          preferred: switch (choice) {
            _Attach.voice => MediaKind.voice,
            _Attach.videoNote => MediaKind.videoNote,
            _ => null,
          },
        );
      } catch (error) {
        debugPrint('Файл не добавлен: $error');
        items = const [];
        if (mounted) _showSnack('Не удалось добавить файл');
      } finally {
        if (mounted) setState(() => _importing = false);
      }
    }
    if (items.isEmpty || !mounted) return;

    // Текст из поля ввода становится подписью к первому файлу.
    final caption = _composer.text.trim();
    final replyTo = _replyTo;
    if (caption.isNotEmpty || replyTo != null) {
      _draftTimer?.cancel();
      _savedDraft = '';
      _composer.clear();
      setState(() => _replyTo = null);
    }
    try {
      for (var i = 0; i < items.length; i++) {
        await _s.messages.sendMedia(
          chatId: widget.chatId,
          senderId: header.ownerCharacterId,
          media: items[i],
          type: messageTypeFor(items[i].kind),
          caption: i == 0 ? caption : '',
          replyToId: i == 0 ? replyTo?.messageId : null,
          sceneId: _s.engine.sceneIdForChat(widget.chatId),
        sentAt: _s.engine.sceneIdForChat(widget.chatId) == null ? null : _s.engine.sceneNow(),
        );
      }
      if (mounted) setState(() => _unreadAtOpen = 0);
    } catch (error) {
      debugPrint('Медиа не отправлено: $error');
      if (mounted) _showSnack('Не удалось отправить файл');
    }
  }

  /// Запись началась: клавиатура убирается, воспроизведение останавливается.
  void _voiceChanged() {
    final voice = _voice;
    if (voice == null) return;
    if (voice.active && !_wasRecording) {
      _wasRecording = true;
      FocusScope.of(context).unfocus();
      unawaited(_s.audio.stop());
      HapticFeedback.lightImpact();
    } else if (!voice.active) {
      _wasRecording = false;
    }
  }

  /// Запись готова (отпустили палец или нажали «отправить» после фиксации).
  Future<void> _sendVoice(MediaItem item) async {
    final header = _header;
    if (header == null || !mounted) return;
    final replyTo = _replyTo;
    setState(() {
      _replyTo = null;
      _unreadAtOpen = 0;
    });
    try {
      await _s.messages.sendMedia(
        chatId: widget.chatId,
        senderId: header.ownerCharacterId,
        media: item,
        type: MessageType.voice,
        replyToId: replyTo?.messageId,
        sceneId: _s.engine.sceneIdForChat(widget.chatId),
        sentAt: _s.engine.sceneIdForChat(widget.chatId) == null ? null : _s.engine.sceneNow(),
      );
    } catch (error) {
      debugPrint('Голосовое не отправлено: $error');
      if (mounted) _showSnack('Не удалось отправить голосовое');
    }
  }

  // ---------- Ответ и переход к сообщению ----------

  String _authorOf(Message message) {
    final header = _header;
    if (header != null && message.senderId == header.ownerCharacterId) return 'Вы';
    return header?.peer.displayName ?? '';
  }

  QuotedMessage _quoteOf(Message message) => QuotedMessage(
        messageId: message.id,
        author: _authorOf(message),
        text: messagePreview(message) ?? '',
      );

  void _startReply(Message message) {
    setState(() => _replyTo = _quoteOf(message));
    _focus.requestFocus();
  }

  void _requestReveal(String messageId) {
    setState(() => _revealId = messageId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(messageId));
  }

  /// Прокручивает ленту, пока нужное сообщение не будет построено,
  /// затем выводит его в центр экрана и кратко подсвечивает.
  Future<void> _reveal(String messageId) async {
    for (var step = 0; step < 60; step++) {
      if (!mounted || _revealId != messageId) return;
      final target = _revealKey.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: Motion.slow,
          curve: Motion.curve,
        );
        if (!mounted) return;
        setState(() => _flashId = messageId);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (mounted && _flashId == messageId) setState(() => _flashId = null);
        return;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scroll.jumpTo(math.min(
        position.pixels + position.viewportDimension * 0.85,
        position.maxScrollExtent,
      ));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  // ---------- Меню сообщения ----------

  Future<void> _openMessageMenu(Message message) async {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() => _selectedMessageId = message.id);

    final canCopy = !message.deleted && message.text.trim().isNotEmpty;
    final action = await showActionSheet<_MessageAction>(
      context,
      header: _MessagePreview(message: message),
      actions: [
        if (!message.deleted)
          const SheetAction(
            value: _MessageAction.reply,
            icon: AppIcons.reply,
            label: 'Ответить',
          ),
        if (canCopy)
          const SheetAction(
            value: _MessageAction.copy,
            icon: AppIcons.copy,
            label: 'Копировать',
          ),
        SheetAction(
          value: _MessageAction.favorite,
          icon: message.favorite ? AppIcons.starOutline : AppIcons.star,
          label: message.favorite ? 'Убрать из избранного' : 'В избранное',
        ),
        SheetAction(
          value: _MessageAction.toggleDeleted,
          icon: message.deleted ? AppIcons.restore : AppIcons.markDeleted,
          label: message.deleted ? 'Вернуть текст' : 'Показать как удалённое',
        ),
        const SheetAction(
          value: _MessageAction.delete,
          icon: AppIcons.delete,
          label: 'Удалить из переписки',
          destructive: true,
        ),
      ],
    );

    if (!mounted) return;
    setState(() => _selectedMessageId = null);
    if (action == null) return;

    try {
      switch (action) {
        case _MessageAction.reply:
          _startReply(message);
        case _MessageAction.copy:
          await Clipboard.setData(ClipboardData(text: message.text));
          if (mounted) _showSnack('Текст скопирован');
        case _MessageAction.favorite:
          await _s.messages.setFavorite(message.id, !message.favorite);
        case _MessageAction.toggleDeleted:
          await _s.messages.setDeleted(message.id, !message.deleted);
        case _MessageAction.delete:
          await _s.messages.delete(message.id);
          if (mounted) {
            _showSnack(
              'Сообщение удалено',
              actionLabel: 'Вернуть',
              onAction: () => unawaited(_restore(message)),
            );
          }
      }
    } catch (error) {
      debugPrint('Действие с сообщением не выполнено: $error');
      if (mounted) _showSnack('Не удалось выполнить действие');
    }
  }

  Future<void> _restore(Message message) async {
    try {
      await _s.messages.restore(message);
    } catch (error) {
      debugPrint('Сообщение не восстановлено: $error');
    }
  }

  void _showSnack(String text, {String? actionLabel, VoidCallback? onAction}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 4),
      action: actionLabel == null
          ? null
          : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ));
  }

  // ---------- Интерфейс ----------

  @override
  Widget build(BuildContext context) {
    return LiveQuery<ChatHeader?>(
      tables: const {
        Tables.chats,
        Tables.characters,
        Tables.deviceContacts,
        Tables.media,
        Tables.devices,
        Tables.chatMembers,
      },
      queryKey: widget.chatId,
      load: () async {
        final header = await _s.chats.header(widget.chatId);
        // Группа: имена участников для пузырей и число участников в шапке.
        if (header != null && header.chat.isGroup) {
          // Вместе с удалёнными: их старые сообщения сохраняют имя и цвет.
          final members = await _s.chats.members(widget.chatId, includeRemoved: true);
          _groupNames = {for (final m in members) m.characterId: m.name};
          _groupTones = {for (final m in members) m.characterId: m.colorTone};
          _groupCount = members.where((m) => !m.removed).length;
        } else {
          _groupNames = null;
          _groupTones = null;
          _groupCount = 0;
        }
        return header;
      },
      builder: (context, snapshot) {
        final header = snapshot.data;
        if (header == null) {
          final Widget body;
          if (snapshot.error != null) {
            body = ErrorState(message: 'Не удалось открыть чат.', onRetry: snapshot.reload);
          } else if (snapshot.isLoading) {
            body = const LoadingState();
          } else {
            body = const EmptyState(
              icon: AppIcons.emptyChats,
              title: 'Чат не найден',
              message: 'Возможно, он был удалён.',
            );
          }
          return Scaffold(
            appBar: const ReplikaTopBar(leading: BackIconButton(), title: SizedBox.shrink()),
            body: body,
          );
        }

        _header = header;
        _unreadAtOpen ??= header.chat.unreadCount;
        _markReadIfNeeded(header);
        final peerId = header.chat.peerCharacterId;
        void openInfo() {
          if (header.chat.isGroup) {
            AppNavigator.openGroupInfo(widget.chatId);
          } else if (peerId != null) {
            AppNavigator.openProfile(deviceId: header.chat.deviceId, characterId: peerId);
          }
        }

        return Scaffold(
          backgroundColor: GlassTheme.of(context).background.first,
          body: GlassWallpaper(
            child: SafeArea(
              bottom: false,
              child: ContentWidth(
                child: Column(
                  children: [
                    ListenableBuilder(
                      listenable: _s.typing,
                      builder: (context, _) => ChatGlassHeader(
                        peer: header.peer,
                        typing: _s.typing.isTyping(widget.chatId),
                        subtitle: header.chat.isGroup ? membersLabel(_groupCount) : null,
                        onTitleTap: header.chat.isGroup || peerId != null ? openInfo : null,
                        onMore: header.chat.isGroup || peerId != null ? openInfo : null,
                        onCall: peerId == null
                            ? null
                            : () => startOutgoingCall(context,
                                deviceId: header.chat.deviceId,
                                characterId: peerId,
                                kind: CallKind.audio,
                                chatId: widget.chatId),
                        onVideo: peerId == null
                            ? null
                            : () => startOutgoingCall(context,
                                deviceId: header.chat.deviceId,
                                characterId: peerId,
                                kind: CallKind.video,
                                chatId: widget.chatId),
                      ),
                    ),
                    VoiceMiniPlayer(playback: _s.audio),
                    Expanded(child: _buildMessages(header)),
                    Composer(
                      controller: _composer,
                      focusNode: _focus,
                      onSend: () => _send(header),
                      reply: _replyTo,
                      onCancelReply: () => setState(() => _replyTo = null),
                      onAttach: () => _attach(header),
                      voice: _voice,
                      busy: _importing,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessages(ChatHeader header) {
    return LiveQuery<List<Message>>(
      tables: const {Tables.messages, Tables.media},
      queryKey: widget.chatId,
      load: () => _s.messages.forChat(widget.chatId),
      builder: (context, snapshot) {
        final messages = snapshot.data;
        if (messages == null) {
          return snapshot.error != null
              ? ErrorState(message: 'Не удалось загрузить сообщения.', onRetry: snapshot.reload)
              : const LoadingState();
        }
        if (_pendingReveal) {
          _pendingReveal = false;
          final id = _revealId;
          if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(id));
        }
        return ListenableBuilder(
          listenable: _s.typing,
          builder: (context, _) {
            final typing = _s.typing.isTyping(widget.chatId);
            if (messages.isEmpty && !typing) {
              return const EmptyState(
                icon: AppIcons.emptyChats,
                title: 'Сообщений пока нет',
                message: 'Напишите первое — оно сохранится на этом телефоне.',
              );
            }
            final byId = {for (final m in messages) m.id: m};
            final seen = _seenIds;
            final fresh = seen == null
                ? const <String>{}
                : {for (final m in messages) if (!seen.contains(m.id)) m.id};
            _seenIds = byId.keys.toSet();
            final rows = buildChatRows(
              messages,
              ownerId: header.ownerCharacterId,
              now: DateTime.now(),
              unreadCount: _unreadAtOpen ?? 0,
            );
            final extra = typing ? 1 : 0;
            return ListView.builder(
              controller: _scroll,
              reverse: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(0, Space.s, 0, Space.s),
              itemCount: rows.length + extra,
              itemBuilder: (context, index) {
                if (typing && index == 0) return const TypingBubble(key: ValueKey('typing'));
                final row = rows[rows.length - 1 - (index - extra)];
                return switch (row) {
                  DaySeparatorRow separator => DaySeparator(
                      key: ValueKey('day-${separator.day.millisecondsSinceEpoch}'),
                      label: separator.label,
                    ),
                  UnreadSeparatorRow _ => const _UnreadSeparator(key: ValueKey('unread')),
                  MessageRow messageRow => _buildBubble(messageRow, byId, fresh.contains(messageRow.message.id), header),
                };
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBubble(MessageRow row, Map<String, Message> byId, bool fresh, ChatHeader header) {
    final message = row.message;
    final quoted = message.replyToId == null ? null : byId[message.replyToId];
    final bubble = MessageBubble(
      key: ValueKey(message.id),
      row: row,
      selected: message.id == _selectedMessageId || message.id == _flashId,
      onLongPress: () => _openMessageMenu(message),
      onReply: message.deleted ? null : () => _startReply(message),
      quote: quoted == null ? null : _quoteOf(quoted),
      onQuoteTap: quoted == null ? null : () => _requestReveal(quoted.id),
      senderName: _groupNames?[message.senderId],
      senderTone: _groupTones?[message.senderId],
      avatar: row.outgoing ? null : _avatarFor(message, header),
    );
    final Widget shown = message.id != _revealId ? bubble : KeyedSubtree(key: _revealKey, child: bubble);
    return MessageEntrance(key: ValueKey('entrance-${message.id}'), animate: fresh, child: shown);
  }

  /// Маленький аватар отправителя (рядом с входящими фото, видео и файлами).
  Widget _avatarFor(Message message, ChatHeader header) {
    final groupName = _groupNames?[message.senderId];
    return Avatar(
      name: groupName ?? header.peer.displayName,
      size: 30,
      imagePath: groupName == null ? header.peer.avatarPath : null,
      tone: groupName == null ? header.peer.avatarTone : _groupTones?[message.senderId],
    );
  }
}

class _UnreadSeparator extends StatelessWidget {
  const _UnreadSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.pill),
            gradient: ChatGlass.outgoing,
          ),
          child: const Text(
            'Непрочитанные сообщения',
            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _MessagePreview extends StatelessWidget {
  const _MessagePreview({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Text(
      messagePreview(message) ?? '',
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: context.tt.bodyMedium?.copyWith(color: context.rc.textSecondary),
    );
  }
}

/// «1 участник», «3 участника», «5 участников».
String membersLabel(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  final word = mod10 == 1 && mod100 != 11
      ? 'участник'
      : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) ? 'участника' : 'участников');
  return '$n $word';
}
