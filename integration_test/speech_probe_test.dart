// Windows 语音识别探针（手动跑）：不碰 UI，直接打 SpeechInputService 全链路，
// 用来验证 Windows 桌面端 speech_to_text 插件能不能收音、能不能出文字。
//
// 跑法：
//   env ... flutter test integration_test/speech_probe_test.dart -d windows
// 前置：系统默认录音设备要对着声源（如 VB-Audio 虚拟麦克风）。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:local2api/services/speech_input_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('语音识别探针：收音 25 秒看识别结果', (tester) async {
    final svc = SpeechInputService();
    final ready = await svc.ensureReady();
    // ignore: avoid_print
    print('PROBE ready=$ready err=${svc.lastError}');
    if (ready != SpeechReady.available) {
      // ignore: avoid_print
      print('PROBE 引擎不可用，结束');
      return;
    }

    final localeId = await svc.resolveLocale(const Locale('zh', 'CN'));
    // ignore: avoid_print
    print('PROBE localeId=$localeId');

    final results = <String>[];
    await svc.start(
      localeId: localeId,
      pauseFor: const Duration(seconds: 60),
      listenFor: const Duration(seconds: 60),
      onResult: (text, isFinal) {
        results.add('[$isFinal] $text');
        // ignore: avoid_print
        print('PROBE result isFinal=$isFinal text=$text');
      },
      onError: (m) {
        // ignore: avoid_print
        print('PROBE error: $m');
      },
    );
    // ignore: avoid_print
    print('PROBE listening 开始，等 25 秒收音…');
    await Future<void>.delayed(const Duration(seconds: 25));
    await svc.stop();
    // ignore: avoid_print
    print('PROBE 结束，共 ${results.length} 条结果');
    for (final r in results) {
      // ignore: avoid_print
      print('PROBE RESULT $r');
    }
  });
}
