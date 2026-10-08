import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/live_query.dart';
import '../../app/navigator.dart';
import '../../app/services.dart';
import '../../core/design/context.dart';
import '../../core/design/tokens.dart';
import '../../core/util/time_format.dart';
import '../../data/db/tables.dart';
import '../../data/models/message.dart';
import '../media/media_content.dart';
import '../media/media_kinds.dart';
import '../media/media_viewer.dart';

/// Вкладки общего содержимого переписки.
enum SharedTab {
  media('Медиа'),
  files('Файлы'),
  voice('Голосовые'),
  links('Ссылки');

  const SharedTab(this.label);
  final String label;
}

final RegExp _linkPattern = RegExp(r'(https?://[^\s]+|www\.[^\s]+|t\.me/[^\s]+)', caseSensitive: false);

/// Раскладывает сообщения по вкладкам профиля (новые сначала).
Map<SharedTab, List<Message>> splitShared(List<Message> messages) {
  final result = {for (final t in SharedTab.values) t: <Message>[]};
  for (final m in messages.reversed) {
    if (m.deleted) continue;
    switch (m.type) {
      case MessageType.photo || MessageType.video:
        if (m.media != null) result[SharedTab.media]!.add(m);
      case MessageType.file || MessageType.audio:
        if (m.media != null) result[SharedTab.files]!.add(m);
      case MessageType.voice || MessageType.videoNote:
        if (m.media != null) result[SharedTab.voice]!.add(m);
      default:
        if (_linkPattern.hasMatch(m.text)) result[SharedTab.links]!.add(m);
    }
  }
  return result;
}

/// Медиа, файлы, голосовые и ссылки из личного чата с контактом.
class SharedMediaSection extends StatefulWidget {
  const SharedMediaSection({super.key, required this.deviceId, this.characterId, this.chatId})
      : assert(characterId != null || chatId != null);

  final String deviceId;

  /// Личный чат с этим персонажем…
  final String? characterId;

  /// …или конкретный чат (группа).
  final String? chatId;

  @override
  State<SharedMediaSection> createState() => _SharedMediaSectionState();
}

class _SharedMediaSectionState extends State<SharedMediaSection> {
  SharedTab _tab = SharedTab.media;

  Future<(String?, Map<SharedTab, List<Message>>)> _load(AppServices services) async {
    final chatId = widget.chatId ??
        await services.chats.findDirect(deviceId: widget.deviceId, characterId: widget.characterId!);
    if (chatId == null) return (null, splitShared(const []));
    return (chatId, splitShared(await services.messages.forChat(chatId)));
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final rc = context.rc;
    final cs = context.cs;
    return LiveQuery<(String?, Map<SharedTab, List<Message>>)>(
      tables: const {Tables.messages, Tables.media, Tables.chats},
      queryKey: '${widget.deviceId}|${widget.characterId}|${widget.chatId}',
      load: () => _load(services),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return const SizedBox(height: 120);
        final (chatId, groups) = data;
        final items = groups[_tab]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Space.s),
            Container(
              height: 46,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rc.divider))),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.s),
                children: [
                  for (final tab in SharedTab.values)
                    InkWell(
                      onTap: () => setState(() => _tab = tab),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.m),
                        child: Stack(
                          children: [
                            Center(
                              child: Text(
                                groups[tab]!.isEmpty ? tab.label : '${tab.label} ${groups[tab]!.length}',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: tab == _tab ? FontWeight.w700 : FontWeight.w500,
                                  color: tab == _tab ? cs.primary : rc.textSecondary,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: tab == _tab ? cs.primary : Colors.transparent,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.xxl),
                child: Text(
                  switch (_tab) {
                    SharedTab.media => 'Фото и видео из переписки появятся здесь',
                    SharedTab.files => 'Файлов пока нет',
                    SharedTab.voice => 'Голосовых пока нет',
                    SharedTab.links => 'Ссылок пока нет',
                  },
                  textAlign: TextAlign.center,
                  style: context.tt.bodyMedium?.copyWith(color: rc.textSecondary),
                ),
              )
            else if (_tab == SharedTab.media)
              _MediaGrid(messages: items)
            else
              for (final m in items)
                _SharedRow(
                  message: m,
                  tab: _tab,
                  onTap: chatId == null ? null : () => AppNavigator.openChat(chatId, revealMessageId: m.id),
                ),
          ],
        );
      },
    );
  }
}

/// Сетка 3 в ряд с тонкими швами, как галерея.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.messages});

  final List<Message> messages;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final media = messages[i].media!;
        final video = messages[i].type == MessageType.video;
        return GestureDetector(
          onTap: () => video ? openVideoViewer(context, media) : openPhotoViewer(context, media),
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                if (video)
                  VideoFrame(media: media, width: constraints.maxWidth, height: constraints.maxHeight)
                else
                  Image.file(
                    File(media.path),
                    fit: BoxFit.cover,
                    cacheWidth: (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorBuilder: (context, error, stack) => ColoredBox(color: context.rc.surfaceMuted),
                  ),
                if (video)
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded, size: 14, color: MediaPalette.onMedia),
                          if (media.duration != null)
                            Text(formatDuration(media.duration!), style: const TextStyle(color: MediaPalette.onMedia, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SharedRow extends StatelessWidget {
  const _SharedRow({required this.message, required this.tab, this.onTap});

  final Message message;
  final SharedTab tab;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rc = context.rc;
    final cs = context.cs;
    final media = message.media;
    final (IconData icon, String title, String subtitle) = switch (tab) {
      SharedTab.files => (
          Icons.insert_drive_file_rounded,
          media?.originalName ?? 'Файл',
          [if (media?.sizeBytes != null) formatBytes(media!.sizeBytes!), formatChatListTime(message.sentAt, DateTime.now())]
              .join(' · '),
        ),
      SharedTab.voice => (
          message.type == MessageType.videoNote ? Icons.radio_button_checked_rounded : Icons.mic_rounded,
          message.type == MessageType.videoNote ? 'Видеосообщение' : 'Голосовое сообщение',
          [if (media?.duration != null) formatDuration(media!.duration!), formatChatListTime(message.sentAt, DateTime.now())]
              .join(' · '),
        ),
      _ => (
          Icons.link_rounded,
          _linkPattern.firstMatch(message.text)?.group(0) ?? message.text,
          message.text,
        ),
    };
    return InkWell(
      onTap: tab == SharedTab.voice && media != null && mediaFileExists(media) ? () => _play(context) : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s + 2),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
              child: Icon(icon, color: cs.primary, size: 22),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: tab == SharedTab.links ? cs.primary : null,
                  )),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: rc.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _play(BuildContext context) async {
    final media = message.media;
    if (media == null) return;
    if (message.type == MessageType.videoNote) {
      await openVideoViewer(context, media);
      return;
    }
    try {
      await Services.read(context).audio.toggle(media);
    } catch (_) {}
  }
}
