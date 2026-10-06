import 'package:flutter_test/flutter_test.dart';
import 'package:replika/app/volume_keys.dart';

void main() {
  late List<VolumeCommand> commands;
  late VolumeKeyInterpreter keys;

  setUp(() {
    commands = [];
    keys = VolumeKeyInterpreter(
      onCommand: commands.add,
      holdForReset: const Duration(milliseconds: 60),
    );
  });

  test('во время дубля: вверх — «Далее», вниз — «Назад», громкость не меняется', () {
    expect(keys.keyDown(isUp: true, takeActive: true, sceneLoaded: true), isTrue);
    expect(keys.keyUp(isUp: true, takeActive: true), isTrue);
    expect(keys.keyDown(isUp: false, takeActive: true, sceneLoaded: true), isTrue);
    expect(keys.keyUp(isUp: false, takeActive: true), isTrue);
    expect(commands, [VolumeCommand.next, VolumeCommand.back]);
  });

  test('без дубля кнопки меняют громкость и ничего не запускают', () {
    expect(keys.keyDown(isUp: true, takeActive: false, sceneLoaded: true), isFalse);
    expect(keys.keyRepeat(isUp: true), isFalse);
    expect(keys.keyUp(isUp: true, takeActive: false), isFalse);
    expect(commands, isEmpty);
  });

  test('обе кнопки с удержанием — сброс, без «Далее» и «Назад»', () async {
    keys.keyDown(isUp: true, takeActive: true, sceneLoaded: true);
    keys.keyDown(isUp: false, takeActive: true, sceneLoaded: true);
    expect(keys.comboActive, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(keys.keyUp(isUp: false, takeActive: true), isTrue);
    expect(keys.keyUp(isUp: true, takeActive: true), isTrue);
    expect(commands, [VolumeCommand.reset]);
  });

  test('короткое нажатие обеих кнопок сброс не вызывает', () async {
    keys.keyDown(isUp: true, takeActive: true, sceneLoaded: true);
    keys.keyDown(isUp: false, takeActive: true, sceneLoaded: true);
    keys.keyUp(isUp: true, takeActive: true);
    keys.keyUp(isUp: false, takeActive: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(commands, isEmpty);
  });

  test('сброс доступен и вне дубля, если сцена выбрана', () async {
    expect(keys.keyDown(isUp: true, takeActive: false, sceneLoaded: true), isFalse);
    expect(keys.keyDown(isUp: false, takeActive: false, sceneLoaded: true), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    keys.keyUp(isUp: true, takeActive: false);
    keys.keyUp(isUp: false, takeActive: false);
    expect(commands, [VolumeCommand.reset]);
  });

  test('без выбранной сцены комбинация ничего не делает', () async {
    expect(keys.keyDown(isUp: true, takeActive: false, sceneLoaded: false), isFalse);
    expect(keys.keyDown(isUp: false, takeActive: false, sceneLoaded: false), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(commands, isEmpty);
  });

  test('после сворачивания приложения состояние кнопок сбрасывается', () async {
    keys.keyDown(isUp: true, takeActive: true, sceneLoaded: true);
    keys.clear();
    keys.keyDown(isUp: false, takeActive: true, sceneLoaded: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    keys.keyUp(isUp: false, takeActive: true);
    expect(commands, [VolumeCommand.back]);
  });
}
