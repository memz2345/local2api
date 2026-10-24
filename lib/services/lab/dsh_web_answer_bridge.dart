// lib/services/lab/dsh_web_answer_bridge.dart
//
// 把「通知里输入的回答」送进正在开的 dsh web 页面。
//
// 为什么不能只走 RPC：ask_user_question 默认是**阻塞式**的，答案只能通过
// 页面上那条 live waterfall 提交；`userQuestions/answer` RPC 只接受已经
// 转成 `continued` 的问题。所以通知回复优先在 in-app 浏览器里把提问卡片
// 填好并点提交（等同用户手点），RPC 只作为 continued 问题的兜底。
//
// 只在 dsh web 页面上生效：controller 的地址必须和 DshService 的端口一致。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../browser_controller.dart';
import 'dsh_service.dart';

class DshWebAnswerBridge {
  DshWebAnswerBridge._();

  static final List<BrowserController> _controllers = <BrowserController>[];

  static void attach(BrowserController controller) {
    if (!_controllers.any((c) => identical(c, controller))) {
      _controllers.add(controller);
    }
  }

  static void detach(BrowserController controller) {
    _controllers.removeWhere((c) => identical(c, controller));
  }

  static BrowserController? get _controller {
    for (final controller in _controllers.reversed) {
      if (_isDshPage(controller)) return controller;
    }
    return null;
  }

  static bool get available => _controller?.windowsController != null;

  static bool _isDshPage(BrowserController controller) {
    final dsh = DshService.instance;
    final page = Uri.tryParse(controller.url);
    final base = Uri.tryParse(dsh.url);
    if (page == null || base == null) return false;
    return page.host == base.host && page.port == base.port;
  }

  /// 在 dsh 页面上填入 [text] 并点提交。返回是否真的点了提交。
  ///
  /// 两步走：先 input（React 受控 textarea 必须用 native setter 才认），
  /// 等一拍让提交按钮从 disabled 变可用，再点。
  static Future<bool> submit(String text) async {
    final controller = _controller;
    if (controller == null || !_isDshPage(controller)) return false;
    Future<String> run(String script) async {
      final windows = controller.windowsController;
      if (windows != null) return '${await windows.executeScript(script)}';
      final mobile = controller.mobileController;
      if (mobile != null) {
        return '${await mobile.runJavaScriptReturningResult(script)}';
      }
      return '';
    }

    try {
      final filled = await run('''
        (() => {
          const visible = (e) => e && e.offsetParent !== null;
          const areas = [...document.querySelectorAll('textarea')]
            .filter(visible);
          if (!areas.length) return 'no-textarea';
          const area = areas[areas.length - 1];
          const setter = Object.getOwnPropertyDescriptor(
            HTMLTextAreaElement.prototype, 'value').set;
          setter.call(area, ${jsonEncode(text)});
          const input = typeof InputEvent === 'function'
            ? new InputEvent('input', {
                bubbles: true, inputType: 'insertText',
                data: ${jsonEncode(text)},
              })
            : new Event('input', { bubbles: true });
          area.dispatchEvent(input);
          area.dispatchEvent(new Event('change', { bubbles: true }));
          area.focus();
          return 'filled';
        })()
      ''');
      if (!filled.contains('filled')) {
        debugPrint('[dsh-answer] fill failed: $filled');
        return false;
      }
      for (var attempt = 0; attempt < 4; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final clicked = await run(r'''
          (() => {
            const visible = (e) => e && e.offsetParent !== null;
            const areas = [...document.querySelectorAll('textarea')]
              .filter(visible);
            const area = areas[areas.length - 1];
            const scope = (area &&
              (area.closest('form,[class*="card"],[class*="Card"]') ||
               area.parentElement?.parentElement?.parentElement)) || document;
            const buttons = [...scope.querySelectorAll('button,[role="button"]')]
              .filter((b) => visible(b) && !b.disabled);
            const exact = /^(提交|发送|Submit|Send|回答|Answer)$/i;
            let submit = buttons.find(
              (b) => exact.test((b.textContent || '').trim()));
            if (!submit) {
              submit = buttons.find(
                (b) => /提交|submit|发送|send|回答|answer/i
                  .test(b.textContent || ''));
            }
            if (!submit) return 'no-submit';
            submit.click();
            return 'submitted';
          })()
        ''');
        if (clicked.contains('submitted')) return true;
        debugPrint('[dsh-answer] click attempt $attempt: $clicked');
      }
      return false;
    } catch (e) {
      debugPrint('[dsh-answer] inject failed: $e');
      return false;
    }
  }
}
