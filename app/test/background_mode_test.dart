import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arcanum/app/background_mode.dart';

import 'fakes.dart';

const _labels = TrayLabels(
  tooltip: 'Arcanum',
  open: 'Open Arcanum',
  lock: 'Lock',
  quit: 'Quit',
);

void main() {
  late FakeAppWindow window;
  late FakeSystemTray tray;
  late FakeLoginItem login;
  late MemoryBackgroundPrefsStore store;
  late int locks;
  late int quits;

  BackgroundMode make() => BackgroundMode(
    window: window,
    tray: tray,
    loginItem: login,
    store: store,
    onLock: () => locks++,
    onQuit: () async => quits++,
  );

  setUp(() {
    window = FakeAppWindow();
    tray = FakeSystemTray();
    login = FakeLoginItem();
    store = MemoryBackgroundPrefsStore();
    locks = 0;
    quits = 0;
  });

  test('closing the window hides it when the tray is available', () async {
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    expect(mode.trayAvailable, isTrue);
    expect(mode.keepRunning, isTrue);

    await window.show();
    await window.userCloses();
    expect(window.calls.last, 'hide');
    expect(window.visible, isFalse);
    expect(quits, 0);
  });

  test('closing quits as before when there is no tray', () async {
    tray = FakeSystemTray(supported: false);
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    expect(mode.trayAvailable, isFalse);
    expect(window.preventClose, isFalse);

    await window.userCloses();
    expect(window.calls, contains('closed'));
  });

  test('a tray that fails to appear counts as no tray', () async {
    tray = FakeSystemTray(createWorks: false);
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    expect(mode.trayAvailable, isFalse);
    expect(window.preventClose, isFalse);
  });

  test('turning keep-running off lets the close button quit', () async {
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    await mode.setKeepRunning(false);
    expect(window.preventClose, isFalse);
    expect((await store.read()).keepRunning, isFalse);

    await mode.setKeepRunning(true);
    expect(window.preventClose, isTrue);
  });

  test('keep-running off is remembered across restarts', () async {
    store.value = const BackgroundPrefs(keepRunning: false);
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    expect(mode.keepRunning, isFalse);
    expect(window.preventClose, isFalse);
  });

  test('the tray menu opens, locks and quits', () async {
    final mode = make();
    await mode.init(labels: _labels, startHidden: true);
    expect(tray.labels, _labels);

    tray.onAction!(TrayAction.open);
    await pumpEventQueue();
    expect(window.visible, isTrue);

    tray.onAction!(TrayAction.lock);
    expect(locks, 1);

    tray.onAction!(TrayAction.quit);
    await pumpEventQueue();
    expect(quits, 1);
    expect(tray.disposed, isTrue);
    expect(window.calls.last, 'destroy');
    expect(mode.trayAvailable, isTrue);
  });

  test('quit stops the bridge before the window goes', () async {
    final order = <String>[];
    final mode = BackgroundMode(
      window: window,
      tray: tray,
      loginItem: login,
      store: store,
      onLock: () {},
      onQuit: () async => order.add('bridge'),
    );
    await mode.init(labels: _labels, startHidden: false);
    await mode.quit();
    order.addAll(window.calls);
    expect(order, ['bridge', 'destroy']);
  });

  test(
    'a hidden start stays hidden only when the tray can bring it back',
    () async {
      final mode = make();
      await mode.init(labels: _labels, startHidden: true);
      expect(window.calls, isNot(contains('show')));

      window = FakeAppWindow();
      tray = FakeSystemTray(supported: false);
      await make().init(labels: _labels, startHidden: true);
      expect(window.calls, contains('show'));

      window = FakeAppWindow();
      tray = FakeSystemTray();
      store.value = const BackgroundPrefs(keepRunning: false);
      await make().init(labels: _labels, startHidden: true);
      expect(window.calls, contains('show'));
    },
  );

  test('launch at login follows the system and can be switched', () async {
    login.enabled = true;
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    expect(mode.launchAtLoginSupported, isTrue);
    expect(mode.launchAtLogin, isTrue);

    expect(await mode.setLaunchAtLogin(false), isTrue);
    expect(login.enabled, isFalse);
    expect(mode.launchAtLogin, isFalse);
  });

  test(
    'a failed login-item change is reported and not shown as done',
    () async {
      login = FakeLoginItem(works: false);
      final mode = make();
      await mode.init(labels: _labels, startHidden: false);
      expect(await mode.setLaunchAtLogin(true), isFalse);
      expect(mode.launchAtLogin, isFalse);
    },
  );

  test('labels can change after start (language switch)', () async {
    final mode = make();
    await mode.init(labels: _labels, startHidden: false);
    const it = TrayLabels(
      tooltip: 'Arcanum',
      open: 'Apri Arcanum',
      lock: 'Blocca',
      quit: 'Esci',
    );
    mode.setLabels(it);
    expect(tray.labels, it);
  });

  test('the file store survives a round trip and bad content', () async {
    final dir = await Directory.systemTemp.createTemp('arcanum_bg');
    addTearDown(() => dir.delete(recursive: true));
    final file = FileBackgroundPrefsStore('${dir.path}/background.json');
    expect((await file.read()).keepRunning, isTrue);

    await file.write(const BackgroundPrefs(keepRunning: false));
    expect((await file.read()).keepRunning, isFalse);

    await File(file.path).writeAsString('not json');
    expect((await file.read()).keepRunning, isTrue);
  });
}
