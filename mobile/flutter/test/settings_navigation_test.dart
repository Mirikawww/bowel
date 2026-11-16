import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bowel/app/i18n.dart';
import 'package:bowel/app/state.dart';
import 'package:bowel/main.dart';
import 'package:bowel/pages/frame.dart';
import 'package:bowel/pages/options.dart';
import 'package:bowel/pages/routing.dart';
import 'package:bowel/pages/settings.dart';
import 'package:bowel/pages/sheet.dart';
import 'package:bowel/pages/tailnet.dart';
import 'package:bowel/ui/atoms.dart';
import 'package:bowel/ui/skin.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations, Material, MaterialType;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _shotKey = ValueKey('settings-shot');
final _prefs = <String, String>{};
final _shellCalls = <String>[];

Widget _host(AppState app, {bool dark = false, double textScale = 1}) => Localizations(
      locale: const Locale('en'),
      delegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      child: MediaQuery(
        data: MediaQueryData(size: const Size(360, 760), platformBrightness: dark ? Brightness.dark : Brightness.light, textScaler: TextScaler.linear(textScale)),
        child: Skin(
          look: Look.of(app.skin, app.wantsDark(dark ? Brightness.dark : Brightness.light)),
          child: Frame(
            data: const FrameData(top: 0, barInset: 0, nativeBar: false, homeIndicator: 0, form: WindowForm.phone),
            child: Material(
              type: MaterialType.transparency,
              child: RepaintBoundary(
                key: _shotKey,
                child: AnimatedBuilder(
                  animation: app,
                  builder: (_, _) => Stack(fit: StackFit.expand, children: [SettingsPage(app: app), SheetHost(app: app)]),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, String title) async {
  final finder = find.text(title);
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 180, scrollable: find.byType(Scrollable).first);
    await Scrollable.ensureVisible(tester.element(finder), alignment: .35);
    await tester.pumpAndSettle();
  }
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel(tr('返回', 'Back')).last);
  await tester.pumpAndSettle();
}

Border? _rowBorder(WidgetTester tester, String title) {
  final boxes = tester.widgetList<DecoratedBox>(find.ancestor(of: find.text(title), matching: find.byType(DecoratedBox)));
  final row = boxes.singleWhere((box) => box.child is Container && (box.child as Container).constraints?.minHeight == 48);
  return (row.decoration as BoxDecoration).border as Border?;
}

Future<void> _shot(WidgetTester tester, String name) async {
  final dir = Platform.environment['BOWEL_SETTINGS_SHOTS'];
  if (dir == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void _androidTest(String name, WidgetTesterCallback body) => testWidgets(name, body, variant: TargetPlatformVariant.only(TargetPlatform.android));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('OPPO Sans')..addFont(rootBundle.load('assets/fonts/OPPOSans4.0.ttf'))).load();
  });

  setUp(() {
    language = 'zh';
    _prefs.clear();
    _shellCalls.clear();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('bowel/shell'), (call) async {
      _shellCalls.add(call.method);
      if (call.method == 'setPref') _prefs[call.arguments['key'] as String] = call.arguments['value'] as String;
      if (call.method == 'listApps') return [{'id': 'example.app', 'name': 'Example'}, {'id': 'second.app', 'name': 'Second'}];
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('bowel/core'), (call) async {
      final method = call.arguments['method'];
      if (method == 'settings') return jsonEncode({'tunStack': 'gvisor', 'canUpdateGeo': false});
      if (method == 'tailnet') return jsonEncode({'state': 'idle'});
      if (method == 'routing') return jsonEncode({'groups': [], 'nodes': []});
      return 'null';
    });
  });

  tearDown(() {
    language = 'zh';
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('bowel/shell'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('bowel/core'), null);
  });

  Future<AppState> mount(WidgetTester tester, {bool dark = false, double textScale = 1}) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState();
    addTearDown(app.dispose);
    await tester.pumpWidget(_host(app, dark: dark, textScale: textScale));
    await tester.pumpAndSettle();
    return app;
  }

  for (final lang in languages) {
    _androidTest('$lang: Android settings home has direct language, core and About entries without General', (tester) async {
      language = lang;
      await mount(tester, dark: lang == 'ja', textScale: 1.3);
      await _shot(tester, 'home-$lang');
      for (final title in [tr('外观', 'Appearance'), tr('路由与规则', 'Routes and rules'), tr('语言', 'Language'), tr('内核选项', 'Core options'), tr('分应用代理', 'Per-app proxy'), 'Tailscale', tr('关于与开源许可', 'About and licenses')]) {
        expect(find.text(title).hitTestable(), findsOneWidget);
      }
      expect(find.byType(Toggle), findsNothing);
      expect(_rowBorder(tester, tr('语言', 'Language'))?.bottom.style, BorderStyle.solid);
      expect(_rowBorder(tester, tr('关于与开源许可', 'About and licenses')), isNull);
      expect(find.text(languageNames[language]!), findsOneWidget);
      final homeTexts = tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().where((text) => text.isNotEmpty).toList();
      expect(homeTexts, orderedEquals([
        tr('设置', 'Settings'), tr('语言', 'Language'), languageNames[language]!,
        tr('外观', 'Appearance'), tr('内核选项', 'Core options'), tr('路由与规则', 'Routes and rules'),
        tr('分应用代理', 'Per-app proxy'), 'Tailscale', tr('关于与开源许可', 'About and licenses'),
      ]));
      for (final title in ['VPN', tr('始终开启 VPN', 'Always-on VPN'), tr('接管', 'Connection'), tr('颜色模式', 'Color mode'), tr('主题色', 'Theme color'), tr('通用', 'General')]) {
        expect(find.text(title), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  _androidTest('per-app proxy and Tailscale open directly from settings home', (tester) async {
    await mount(tester);
    await _open(tester, tr('分应用代理', 'Per-app proxy'));
    expect(find.byType(AppsPage), findsOneWidget);
    expect(_rowBorder(tester, 'Example')?.bottom.style, BorderStyle.solid);
    expect(_rowBorder(tester, 'Second'), isNull);
    await tester.enterText(find.byType(EditableText), 'Example');
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(_rowBorder(tester, 'Example'), isNull);
    await _back(tester);
    expect(find.text(tr('内核选项', 'Core options')), findsOneWidget);
    await _open(tester, 'Tailscale');
    expect(find.byType(TailnetPage), findsOneWidget);
    expect(_rowBorder(tester, tr('内置 Tailscale', 'Built-in Tailscale')), isNull);
    await _back(tester);
    expect(find.text(tr('外观', 'Appearance')), findsOneWidget);
    expect(find.text('VPN'), findsNothing);
    expect(_shellCalls, isNot(contains('openVPNSettings')));
  });

  _androidTest('appearance controls still save from the second level', (tester) async {
    final app = await mount(tester, dark: true);
    await _open(tester, tr('外观', 'Appearance'));
    await _shot(tester, 'appearance-dark');
    await _open(tester, tr('颜色模式', 'Color mode'));
    await _open(tester, tr('深色', 'Dark'));
    expect(app.appearance, 'dark');
    expect(_prefs['appearance'], 'dark');
    await _open(tester, tr('边框', 'Borders'));
    await _open(tester, tr('弯曲', 'Twisted'));
    expect(app.twisted, isTrue);
    expect(_prefs['borders'], 'twisted');
    await _back(tester);
    await _open(tester, tr('外观', 'Appearance'));
    expect(find.text(tr('弯曲', 'Twisted')), findsOneWidget);
    expect(find.text(tr('主题色', 'Theme color')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _androidTest('routing pages return to their category and deep links still work', (tester) async {
    final app = await mount(tester);
    await _open(tester, tr('路由与规则', 'Routes and rules'));
    expect(_rowBorder(tester, tr('路由组', 'Route groups'))?.bottom.style, BorderStyle.solid);
    expect(_rowBorder(tester, tr('我的规则', 'My rules')), isNull);
    await _open(tester, tr('路由组', 'Route groups'));
    expect(find.byType(RoutesPage), findsOneWidget);
    await _back(tester);
    await _open(tester, tr('我的规则', 'My rules'));
    expect(find.byType(MyRulesPage), findsOneWidget);
    await _back(tester);
    await _back(tester);
    app.openRoutesPage!();
    await tester.pumpAndSettle();
    expect(find.byType(RoutesPage), findsOneWidget);
    await _back(tester);
    expect(find.text(tr('内核选项', 'Core options')), findsOneWidget);
  });

  _androidTest('language, core options and About open directly from settings home', (tester) async {
    await mount(tester);
    expect(find.text(tr('通用', 'General')), findsNothing);
    await _open(tester, tr('语言', 'Language'));
    await _open(tester, 'English');
    expect(language, 'en');
    expect(find.text('General'), findsNothing);
    await _open(tester, 'Core options');
    expect(find.byType(OptionsPage), findsOneWidget);
    await _back(tester);
    await _open(tester, 'About and licenses');
    expect(find.byType(AboutPage), findsOneWidget);
    await _back(tester);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(Toggle), findsNothing);
  });

  _androidTest('core option sections retain internal dividers without a trailing divider', (tester) async {
    await mount(tester);
    await _open(tester, tr('内核选项', 'Core options'));
    final first = tr('日志级别', 'Log level');
    expect(_rowBorder(tester, first)?.bottom.style, BorderStyle.solid);
    final last = tr('TLS 指纹', 'TLS fingerprint');
    await tester.scrollUntilVisible(find.text(last), 180, scrollable: find.byType(Scrollable).first);
    expect(_rowBorder(tester, last), isNull);
    final stack = tr('协议栈', 'Stack');
    await tester.scrollUntilVisible(find.text(stack), 180, scrollable: find.byType(Scrollable).first);
    expect(_rowBorder(tester, stack), isNull);
    expect(tester.takeException(), isNull);
  });

  _androidTest('Android system Back unwinds nested settings before leaving the tab', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppState()..tab = 3;
    addTearDown(app.dispose);
    await tester.pumpWidget(BowelApp(app: app, ready: Future<void>.value()));
    await tester.pumpAndSettle();
    await _open(tester, tr('路由与规则', 'Routes and rules'));
    await _open(tester, tr('我的规则', 'My rules'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(tr('路由组', 'Route groups')), findsOneWidget);
    expect(app.tab, 3);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(tr('外观', 'Appearance')), findsOneWidget);
    expect(find.text('VPN'), findsNothing);
    expect(app.tab, 3);
  });

  testWidgets('iOS retains its existing inline settings and reconnect control', (tester) async {
    await mount(tester);
    expect(find.text('VPN'), findsOneWidget);
    expect(find.text(tr('断线后自动接管', 'Reconnect automatically')), findsOneWidget);
    expect(find.byType(Toggle), findsNWidgets(2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
