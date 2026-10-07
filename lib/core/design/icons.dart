import 'package:flutter/material.dart';

/// Единый набор иконок: только скруглённый стиль Material.
/// Все иконки ключевых экранов мессенджера берутся отсюда: чтобы сменить
/// набор, достаточно поменять значения в этом файле.
abstract final class AppIcons {
  static const IconData chats = Icons.chat_bubble_outline_rounded;
  static const IconData chatsActive = Icons.chat_bubble_rounded;
  static const IconData contacts = Icons.person_outline_rounded;
  static const IconData contactsActive = Icons.person_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData searchOff = Icons.search_off_rounded;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData send = Icons.arrow_upward_rounded;
  static const IconData pin = Icons.push_pin_rounded;
  static const IconData pinOff = Icons.push_pin_outlined;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData markRead = Icons.mark_chat_read_rounded;
  static const IconData markUnread = Icons.mark_chat_unread_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData starOutline = Icons.star_outline_rounded;
  static const IconData clear = Icons.close_rounded;
  static const IconData tickSent = Icons.check_rounded;
  static const IconData tickDouble = Icons.done_all_rounded;
  static const IconData sending = Icons.schedule_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData muted = Icons.notifications_off_rounded;
  static const IconData retry = Icons.refresh_rounded;
  static const IconData restore = Icons.restore_rounded;
  static const IconData markDeleted = Icons.block_rounded;
  static const IconData emptyChats = Icons.forum_rounded;
  static const IconData emptyContacts = Icons.people_outline_rounded;
  static const IconData settings = Icons.settings_outlined;
  static const IconData settingsActive = Icons.settings_rounded;
  static const IconData reply = Icons.reply_rounded;
  static const IconData add = Icons.person_add_alt_rounded;
  static const IconData edit = Icons.edit_rounded;
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
  static const IconData microphone = Icons.mic_rounded;
  static const IconData microphoneOff = Icons.mic_off_rounded;
  static const IconData attachPhotoVideo = Icons.photo_library_rounded;
  static const IconData attachVideoNoteRecord = Icons.radio_button_checked_rounded;
  static const IconData attachVideoNoteFile = Icons.video_camera_front_rounded;
  static const IconData attachAudio = Icons.music_note_rounded;
  static const IconData attachLibrary = Icons.perm_media_outlined;

  // Звонки и видео.
  static const IconData call = Icons.call_rounded;
  static const IconData callOutlined = Icons.call_outlined;
  static const IconData callEnd = Icons.call_end_rounded;
  static const IconData callMissed = Icons.phone_missed_rounded;
  static const IconData callIncoming = Icons.call_received_rounded;
  static const IconData callOutgoing = Icons.call_made_rounded;
  static const IconData video = Icons.videocam_rounded;
  static const IconData videoOutlined = Icons.videocam_outlined;
  static const IconData videoOff = Icons.videocam_off_rounded;
  static const IconData cameraSwitch = Icons.cameraswitch_rounded;

  // Чаты.
  static const IconData notificationsOn = Icons.notifications_active_outlined;
  static const IconData groupAdd = Icons.group_add_outlined;
}
