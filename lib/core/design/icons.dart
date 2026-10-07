import 'package:flutter/material.dart';

/// Единый набор иконок. Все иконки ключевых экранов мессенджера берутся
/// отсюда: чтобы сменить значок, достаточно поменять значение в этом файле.
///
/// Большая часть — скруглённый стиль Material. Самые заметные в кадре значки
/// (нижняя навигация, «Назад», галочки статуса, отправка, поиск, трубка,
/// видео, микрофон, правка, состояния звонка) — собственные, из шрифта
/// assets/fonts/ReplikaIcons.ttf; он собирается скриптом
/// tool/build_icon_font.py, коды символов заданы там же.
abstract final class AppIcons {
  static const String _own = 'ReplikaIcons';

  static const IconData chats = IconData(0xE002, fontFamily: _own);
  static const IconData chatsActive = IconData(0xE003, fontFamily: _own);
  static const IconData contacts = IconData(0xE004, fontFamily: _own);
  static const IconData contactsActive = IconData(0xE005, fontFamily: _own);
  static const IconData search = IconData(0xE00B, fontFamily: _own);
  static const IconData searchOff = Icons.search_off_rounded;
  static const IconData back = IconData(0xE001, fontFamily: _own);
  static const IconData send = IconData(0xE00A, fontFamily: _own);
  static const IconData pin = Icons.push_pin_rounded;
  static const IconData pinOff = Icons.push_pin_outlined;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData markRead = Icons.mark_chat_read_rounded;
  static const IconData markUnread = Icons.mark_chat_unread_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData starOutline = Icons.star_outline_rounded;
  static const IconData clear = Icons.close_rounded;
  static const IconData tickSent = IconData(0xE008, fontFamily: _own);
  static const IconData tickDouble = IconData(0xE009, fontFamily: _own);
  static const IconData sending = Icons.schedule_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData muted = Icons.notifications_off_rounded;
  static const IconData retry = Icons.refresh_rounded;
  static const IconData restore = Icons.restore_rounded;
  static const IconData markDeleted = Icons.block_rounded;
  static const IconData emptyChats = Icons.forum_rounded;
  static const IconData emptyContacts = Icons.people_outline_rounded;
  static const IconData settings = IconData(0xE006, fontFamily: _own);
  static const IconData settingsActive = IconData(0xE007, fontFamily: _own);
  static const IconData reply = Icons.reply_rounded;
  static const IconData add = Icons.person_add_alt_rounded;
  static const IconData edit = IconData(0xE011, fontFamily: _own);
  static const IconData profile = Icons.account_circle_rounded;
  static const IconData message = Icons.chat_rounded;
  static const IconData phone = Icons.phone_rounded;
  static const IconData theme = Icons.contrast_rounded;
  static const IconData themeSystem = Icons.brightness_auto_rounded;
  static const IconData themeLight = Icons.light_mode_rounded;
  static const IconData themeDark = Icons.dark_mode_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData chevron = Icons.chevron_right_rounded;
  static const IconData removeContact = Icons.person_remove_rounded;

  // Поле ввода и вложения.
  static const IconData attachment = Icons.attach_file_rounded;
  static const IconData microphone = IconData(0xE010, fontFamily: _own);
  static const IconData microphoneOff = IconData(0xE012, fontFamily: _own);
  static const IconData attachPhotoVideo = Icons.photo_library_rounded;
  static const IconData attachVideoNoteRecord = Icons.radio_button_checked_rounded;
  static const IconData attachVideoNoteFile = Icons.video_camera_front_rounded;
  static const IconData attachAudio = Icons.music_note_rounded;
  static const IconData attachLibrary = Icons.perm_media_outlined;

  // Звонки и видео.
  static const IconData call = IconData(0xE00C, fontFamily: _own);
  static const IconData callOutlined = IconData(0xE00D, fontFamily: _own);
  static const IconData callEnd = IconData(0xE014, fontFamily: _own);
  static const IconData callMissed = IconData(0xE015, fontFamily: _own);
  static const IconData callIncoming = Icons.call_received_rounded;
  static const IconData callOutgoing = Icons.call_made_rounded;
  static const IconData video = IconData(0xE00E, fontFamily: _own);
  static const IconData videoOutlined = IconData(0xE00F, fontFamily: _own);
  static const IconData videoOff = IconData(0xE013, fontFamily: _own);
  static const IconData cameraFlip = IconData(0xE016, fontFamily: _own);

  // Чаты.
  static const IconData notificationsOn = Icons.notifications_active_outlined;
  static const IconData groupAdd = Icons.group_add_outlined;
  static const IconData plus = Icons.add_rounded;

  // Медиа в чате и просмотре.
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData volume = Icons.volume_up_rounded;
  static const IconData file = Icons.insert_drive_file_rounded;

  // Настройки и карточка контакта.
  static const IconData addPhoto = Icons.add_a_photo_rounded;
  static const IconData device = Icons.phone_android_rounded;
  static const IconData addons = Icons.extension_outlined;
  static const IconData lock = Icons.lock_outline_rounded;

  // Главный экран (светлое стекло).
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData emoji = Icons.mood_outlined;
  static const IconData waveform = Icons.graphic_eq_rounded;
  static const IconData photo = Icons.image_rounded;
  static const IconData group = Icons.groups_rounded;
  static const IconData archive = Icons.archive_outlined;
  static const IconData unarchive = Icons.unarchive_outlined;
}
