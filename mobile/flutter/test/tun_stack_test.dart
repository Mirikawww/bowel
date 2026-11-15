import 'dart:convert';

import 'package:bowel/app/i18n.dart';
import 'package:bowel/app/state.dart';
import 'package:bowel/pages/frame.dart';
import 'package:bowel/pages/options.dart';
import 'package:bowel/pages/sheet.dart';
import 'package:bowel/ui/skin.dart';
import 'package:flutter/material.dart' show DefaultMaterialLocalizations, Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(AppState app) => Localizations(
      locale: const Locale('en'),
      delegates: const [DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
      child: MediaQuery(
        data: const MediaQueryData(size: Size(360, 760)),
        child: Skin(
          look: Look.of('paper', false),
          child: Frame(
            data: const FrameData(top: 0, barInset: 0, nativeBar: false, homeIndicator: 0, form: WindowForm.phone),
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Material(
                  type: MaterialType.transparency,
                  child: AnimatedBuilder(
                    animation: app,
                    builder: (_, _) => Stack(fit: StackFit.expand, children: [OptionsPage(app: app), SheetHost(app: app)]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final lang in ['zh', 'en', 'ja', 'zh-Hant']) {
    testWidgets('$lang: select MIPS, reopen settings, and switch back to gVisor', (tester) async {
      language = lang;
      addTearDown(() => language = 'zh');
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var saved = 'gvisor';
      final patches = <Map>[];
      const channel = MethodChannel('bowel/core');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final method = call.arguments['method'] as String;
        final args = jsonDecode(call.arguments['payload'] as String) as Map;
        if (method == 'settings') return jsonEncode({'tunStack': saved, 'canUpdateGeo': false});
        if (method == 'setSettings') {
          final patch = args['patch'] as Map;
          patches.add(patch);
          saved = patch['tunStack'] as String;
        }
        return 'null';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final app = AppState();
      addTearDown(app.dispose);
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();

      final stackTitle = tr('协议栈', 'Stack');
      await tester.scrollUntilVisible(find.text(stackTitle), 180, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(find.text(stackTitle)), alignment: .35);
      await tester.pumpAndSettle();
      await tester.tap(find.text(stackTitle));
      await tester.pumpAndSettle();
      expect(find.text('MIPS'), findsOneWidget);
      await tester.tap(find.text('MIPS'));
      await tester.pumpAndSettle();
      expect(patches, [{'tunStack': 'mips'}]);
      expect(saved, 'mips');

      // Recreate the page and read back what the bridge saved.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(app));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(stackTitle), 180, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(find.text(stackTitle)), alignment: .35);
      await tester.pumpAndSettle();
      expect(find.text('MIPS'), findsOneWidget);
      await tester.tap(find.text(stackTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gVisor'));
      await tester.pumpAndSettle();
      expect(patches.last, {'tunStack': 'gvisor'});
      expect(saved, 'gvisor');
      expect(tester.takeException(), isNull);
    });
  }
}
