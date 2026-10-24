// Windows 语音识别探针 v2（手动跑）：直接打 SpeechToText 引擎，带时间戳，
// 验证「首条结果延迟 / 是否连续出结果 / cancel 后能否重新 listen」——
// 这三件事决定模拟页与通话页的真实体感。
//
// 跑法：
//   env ... flutter test integration_test/speech_probe2_test.dart -d windows
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('探针 v2：时序 + 连续 listen', (tester) async {
    final stt = SpeechToText();
    final t0 = DateTime.now();
    int ms() => DateTime.now().difference(t0).inMilliseconds;

    final ok = await stt.initialize(
      onStatus: (s) {
        // ignore: avoid_print
        print('PROBE2 [$ms ms] status=$s');
      },
      onError: (e) {
        // ignore: avoid_print
        print('PROBE2 [$ms ms] error=${e.errorMsg} permanent=${e.permanent}');
      },
    );
    // ignore: avoid_print
    print('PROBE2 [$ms ms] init=$ok');

    Future<void> listenRound(String tag) async {
      final r = await stt.listen(
        onResult: (r) {
          // ignore: avoid_print
          print(
            'PROBE2 [$ms ms] $tag result final=${r.finalResult} '
            'text=${r.recognizedWords}',
          );
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 60),
          pauseFor: const Duration(seconds: 60),
        ),
      );
      // ignore: avoid_print
      print('PROBE2 [$ms ms] $tag listen()=$r');
    }

    await listenRound('R1');
    await Future<void>.delayed(const Duration(seconds: 15));

    // 模拟通话页：定稿后 cancel，稍后重新 listen。
    // ignore: avoid_print
    print('PROBE2 [$ms ms] --- cancel #1 ---');
    await stt.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    await listenRound('R2');
    await Future<void>.delayed(const Duration(seconds: 15));

    // 再来一轮：这次用 stop（模拟模拟页「再点一下停止」）。
    // ignore: avoid_print
    print('PROBE2 [$ms ms] --- stop #2 ---');
    await stt.stop();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    await listenRound('R3');
    await Future<void>.delayed(const Duration(seconds: 12));

    // ignore: avoid_print
    print('PROBE2 [$ms ms] done, isListening=${stt.isListening}');
    await stt.cancel();
  });
}
