// lib/services/browser_web_shim.dart
//
// 注入进网页的「外壳补丁」（内置浏览器专用，Android / Windows 生效）。
//
// 为什么要在网页里动手：
//   WebView 里 `<select>` 的弹窗不是网页画的，是系统 `AlertDialog` +
//   `android.R.layout.select_dialog_singlechoice`；滚动条也是 View 自己的
//   `scrollbarThumbVertical`。两者都只认 **Activity 主题**。之前 Activity
//   用 `@android:style/Theme.Light.NoTitleBar`（Android 1.x 的老主题），
//   于是：
//     · `<select>` 弹出来是灰 radio + 细分割线 + 老滚动条的「安卓 2.x」样；
//     · 页面滚动条是 Holo 时代的窄条。
//   换主题只能到 Material 2，还改不动弹窗本身的结构。所以这里两层一起做：
//     1. `kBrowserChromeCss` —— 用 CSS 把滚动条换成 M3 细条（8px、圆头、
//        半透明，hover 加深）；
//     2. `kBrowserSelectShimJs` —— 拦下 `<select>` 的原生弹窗（mousedown
//        preventDefault 是 Chromium 里唯一可靠的办法），把选项丢给宿主，
//        由 Flutter 用 Material 3 / miuix 的底部选择器画，选完再回填
//        `selectedIndex` 并补发 input/change 事件。
//
// 注意：这里只拦单选的普通下拉（`multiple` / `size > 1` 交回原生），
// 选项超过 [kBrowserSelectMaxOptions] 也交回原生（Flutter 侧画不动那么长
// 的列表，原生反而更稳）。

import 'dart:convert';

/// 网页里一次 `<select>` 的选项快照。
class BrowserSelectOption {
  const BrowserSelectOption({
    required this.index,
    required this.label,
    this.group = '',
    this.disabled = false,
  });

  /// `<option>.index`（在 select 里的下标，含 optgroup 内的项）。
  final int index;
  final String label;
  final String group;
  final bool disabled;
}

/// 网页抛给宿主的「选择请求」。
class BrowserSelectRequest {
  const BrowserSelectRequest({
    required this.id,
    required this.options,
    required this.selectedIndex,
    this.label = '',
  });

  /// 一次请求的幂等 id（回填时原样带回）。
  final String id;
  final List<BrowserSelectOption> options;
  final int selectedIndex;

  /// 能猜到的字段名（`aria-label` / `label[for]` / 外层 `<label>`），可能为空。
  final String label;

  /// 解析 JS 侧 JSON。字段不合法就返回 null（当作没收到）。
  static BrowserSelectRequest? tryParse(Object? json) {
    if (json is! Map) return null;
    if (json['type'] != 'select') return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final rawOptions = json['options'];
    if (rawOptions is! List) return null;
    final options = <BrowserSelectOption>[];
    for (final item in rawOptions) {
      if (item is! Map) continue;
      final index = item['index'];
      if (index is! int) continue;
      final label = item['label'];
      final group = item['group'];
      options.add(
        BrowserSelectOption(
          index: index,
          label: label is String ? label : '',
          group: group is String ? group : '',
          disabled: item['disabled'] == true,
        ),
      );
    }
    if (options.isEmpty) return null;
    final selected = json['index'];
    final label = json['label'];
    return BrowserSelectRequest(
      id: id,
      options: options,
      selectedIndex: selected is int ? selected : -1,
      label: label is String ? label : '',
    );
  }
}

/// 选项上限：超过就交回原生弹窗（Flutter 表格子画 200 行没意义）。
const int kBrowserSelectMaxOptions = 200;

/// 解析 JS 通道推来的消息（Android 是 String，iOS 是 Map）。
Object? decodeBrowserShimMessage(Object? raw) {
  if (raw is String) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  return raw;
}

/// 注入脚本：滚动条样式 + `<select>` 拦截 + 回填入口。
///
/// 幂等：重复注入（单页应用换路由 / onPageStarted + onPageFinished 各一次）
/// 只会重挂一次样式，不会叠加监听器。
const String kBrowserShimJs = r'''
(function () {
  if (window.__L2A_SHIM__) {
    try { window.__L2A_installCss && window.__L2A_installCss(); } catch (e) {}
    return;
  }
  window.__L2A_SHIM__ = true;

  // ---- 1. 滚动条：系统老样式 → M3 细条 ----
  var CSS = [
    '::-webkit-scrollbar{width:8px;height:8px}',
    '::-webkit-scrollbar-track,::-webkit-scrollbar-corner{background:transparent}',
    '::-webkit-scrollbar-thumb{background:rgba(124,124,128,.42);border-radius:99px;',
    'border:2px solid transparent;background-clip:content-box}',
    '::-webkit-scrollbar-thumb:hover,::-webkit-scrollbar-thumb:active{',
    'background:rgba(124,124,128,.66);background-clip:content-box}',
    'html{scrollbar-width:thin;scrollbar-color:rgba(124,124,128,.45) transparent}'
  ].join('');

  window.__L2A_installCss = function () {
    try {
      var old = document.getElementById('l2a-shim-style');
      if (old && old.parentNode) old.parentNode.removeChild(old);
      var style = document.createElement('style');
      style.id = 'l2a-shim-style';
      style.textContent = CSS;
      (document.head || document.documentElement).appendChild(style);
    } catch (e) {}
  };
  window.__L2A_installCss();

  // ---- 2. 与宿主通信（安卓 JS 通道 / WebView2 / iOS 三套都试一遍） ----
  function post(obj) {
    var text = null;
    try { text = JSON.stringify(obj); } catch (e) { return false; }
    try {
      if (window.L2ASelect && window.L2ASelect.postMessage) {
        window.L2ASelect.postMessage(text);
        return true;
      }
      if (window.chrome && window.chrome.webview) {
        window.chrome.webview.postMessage(text);
        return true;
      }
      if (window.webkit && window.webkit.messageHandlers &&
          window.webkit.messageHandlers.L2ASelect) {
        window.webkit.messageHandlers.L2ASelect.postMessage(obj);
        return true;
      }
    } catch (e) {}
    return false;
  }

  var seq = 0;
  var pending = {};

  // 收集选项（走 children，optgroup 的 label 当分组名；options 集合会把它压平）
  function collect(select) {
    var out = [];
    var kids = select.children;
    for (var i = 0; i < kids.length; i++) {
      var node = kids[i];
      if (node.tagName === 'OPTGROUP') {
        var group = (node.label || '').trim();
        for (var j = 0; j < node.children.length; j++) {
          var inner = node.children[j];
          if (inner.tagName !== 'OPTION') continue;
          out.push({
            index: inner.index,
            label: (inner.label || inner.textContent || '').trim(),
            group: group,
            disabled: !!inner.disabled
          });
        }
      } else if (node.tagName === 'OPTION') {
        out.push({
          index: node.index,
          label: (node.label || node.textContent || '').trim(),
          group: '',
          disabled: !!node.disabled
        });
      }
    }
    return out;
  }

  function labelOf(select) {
    var text = select.getAttribute('aria-label') || select.getAttribute('title') || '';
    if (!text && select.id) {
      try {
        var lab = document.querySelector('label[for="' + select.id.replace(/"/g, '\\"') + '"]');
        if (lab && lab.textContent) text = lab.textContent;
      } catch (e) {}
    }
    if (!text) {
      var p = select.parentElement;
      var depth = 0;
      while (p && p !== document.body && depth < 6) {
        if (p.tagName === 'LABEL' && p.textContent) { text = p.textContent; break; }
        p = p.parentElement;
        depth++;
      }
    }
    text = (text || '').replace(/\s+/g, ' ').trim();
    if (text.length > 48) text = text.slice(0, 48);
    return text;
  }

  function findSelect(node) {
    var n = node;
    while (n && n.nodeType === 1) {
      if (n.tagName === 'SELECT') return n;
      n = n.parentElement;
    }
    // 点的是包着 select 的 <label>：把点击算到 select 头上
    if (node && node.closest) {
      var lab = node.closest('label');
      if (lab && lab.control && lab.control.tagName === 'SELECT') return lab.control;
    }
    return null;
  }

  function isPlainSelect(select) {
    if (!select || select.disabled) return false;
    if (select.multiple) return false;
    if (select.size && select.size > 1) return false;
    return true;
  }

  // 通道在不在（安卓 JS 通道 / WebView2 / iOS 三选一）
  function channelReady() {
    return !!(
      (window.L2ASelect && window.L2ASelect.postMessage) ||
      (window.chrome && window.chrome.webview) ||
      (window.webkit && window.webkit.messageHandlers &&
       window.webkit.messageHandlers.L2ASelect)
    );
  }

  // 能不能接管：**必须先判断再 preventDefault** —— 接管不了就放原生走，
  // 否则点击被吞、原生弹窗又被拦，select 直接变成死的。
  function canHandle(select) {
    if (!isPlainSelect(select)) return false;
    if (!channelReady()) return false;
    var count = select.options ? select.options.length : 0;
    return count > 0 && count <= 200;
  }

  function openFor(select) {
    if (!canHandle(select)) return false;
    // 同一次点击的 mousedown / mouseup / click 三连只开一次
    if (select.__l2aStamp && Date.now() - select.__l2aStamp < 400) return true;
    var options = collect(select);
    if (!options.length) return false;
    var id = String(++seq) + '-' + Date.now();
    select.__l2aStamp = Date.now();
    try { select.setAttribute('data-l2a-select', id); } catch (e) {}
    pending[id] = select;
    var ok = post({
      type: 'select',
      id: id,
      label: labelOf(select),
      index: select.selectedIndex,
      options: options
    });
    if (!ok) {
      delete pending[id];
      try { select.removeAttribute('data-l2a-select'); } catch (e) {}
      return false;
    }
    return true;
  }

  // 宿主（Flutter）选完后回填。index < 0 = 取消。
  window.__l2aSelectResolve = function (id, index) {
    var select = pending[id];
    delete pending[id];
    if (!select) return;
    try { select.removeAttribute('data-l2a-select'); } catch (e) {}
    if (typeof index === 'number' && index >= 0 && index < select.options.length) {
      if (select.selectedIndex !== index) {
        select.selectedIndex = index;
        try {
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
        } catch (e) {}
      }
    }
  };

  function onMouse(event) {
    var select = findSelect(event.target);
    if (!select) return;
    if (!canHandle(select)) return;
    // 关键：mousedown 的 preventDefault 会掐掉 WebView 的原生 select 弹窗
    if (event.cancelable) event.preventDefault();
    if (event.type === 'mousedown') openFor(select);
  }

  var types = ['mousedown', 'mouseup', 'click'];
  for (var i = 0; i < types.length; i++) {
    document.addEventListener(types[i], onMouse, true);
  }
})();
''';
