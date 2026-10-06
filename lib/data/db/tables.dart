/// Имена таблиц локальной базы.
abstract final class Tables {
  static const String media = 'media';
  static const String characters = 'characters';
  static const String devices = 'devices';
  static const String deviceContacts = 'device_contacts';
  static const String chats = 'chats';
  static const String chatMembers = 'chat_members';
  static const String messages = 'messages';
  static const String scenes = 'scenes';
  static const String sceneCharacters = 'scene_characters';
  static const String sceneActions = 'scene_actions';
  static const String takes = 'takes';
  static const String calls = 'calls';
  static const String preparedReplies = 'prepared_replies';
  static const String settings = 'settings';

  static const Set<String> all = {
    media, characters, devices, deviceContacts, chats, chatMembers, messages,
    scenes, sceneCharacters, sceneActions, takes, calls, preparedReplies, settings,
  };
}
