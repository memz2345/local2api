#!/usr/bin/env python3
# 一次性给 4 个 arb 追加新文案（模板 app_zh_CN.arb 还要补 @-metadata）。
import io, json, sys, os

BASE = os.path.join(os.path.dirname(__file__), '..', 'lib', 'l10n')

NEW = {
  'app_zh_CN.arb': {
    "contextRingTap": "点击查看上下文详情",
    "contextDetailTitle": "上下文占用",
    "contextDetailPercent": "占上下文 {percent}%",
    "contextDetailUsed": "{used} / {total} tokens",
    "contextDetailFromUsage": "取自上一轮响应的 usage（精确值）",
    "contextDetailEstimated": "按字数与图片粗估（上游没回 usage）",
    "contextDetailOutput": "最大输出 {limit} tokens",
    "contextDetailOutputNone": "最大输出未声明",
    "contextDetailModel": "请求模型 {model}",
    "contextDetailMessages": "{count} 条消息 · {images} 张图片",
    "contextDetailClose": "知道了",
    "chatSimSendImages": "发送图片",
    "chatSimSendTextOnly": "仅发文字",
    "chatSimSendImagesTip": "图片会作为多模态内容一起发给模型；纯文本车道报错时切到「仅发文字」，图就只留在界面上。",
    "chatSimImagesOn": "图片会随消息发出",
    "chatSimImagesOff": "图片只在本地展示，不发给模型",
    "chatSimAttachCamera": "拍照",
    "chatSimAttachFailed": "读取附件失败：{error}",
    "chatSimVoiceNoPermission": "没有麦克风权限，无法语音输入",
    "chatSimVoiceOpenSettings": "去设置",
    "chatSimVoiceFailed": "语音输入失败：{error}",
  },
  'app_zh.arb': {
    "contextRingTap": "点击查看上下文详情",
    "contextDetailTitle": "上下文占用",
    "contextDetailPercent": "占上下文 {percent}%",
    "contextDetailUsed": "{used} / {total} tokens",
    "contextDetailFromUsage": "取自上一轮响应的 usage（精确值）",
    "contextDetailEstimated": "按字数与图片粗估（上游没回 usage）",
    "contextDetailOutput": "最大输出 {limit} tokens",
    "contextDetailOutputNone": "最大输出未声明",
    "contextDetailModel": "请求模型 {model}",
    "contextDetailMessages": "{count} 条消息 · {images} 张图片",
    "contextDetailClose": "知道了",
    "chatSimSendImages": "发送图片",
    "chatSimSendTextOnly": "仅发文字",
    "chatSimSendImagesTip": "图片会作为多模态内容一起发给模型；纯文本车道报错时切到「仅发文字」，图就只留在界面上。",
    "chatSimImagesOn": "图片会随消息发出",
    "chatSimImagesOff": "图片只在本地展示，不发给模型",
    "chatSimAttachCamera": "拍照",
    "chatSimAttachFailed": "读取附件失败：{error}",
    "chatSimVoiceNoPermission": "没有麦克风权限，无法语音输入",
    "chatSimVoiceOpenSettings": "去设置",
    "chatSimVoiceFailed": "语音输入失败：{error}",
  },
  'app_zh_TW.arb': {
    "contextRingTap": "點擊查看上下文詳情",
    "contextDetailTitle": "上下文佔用",
    "contextDetailPercent": "佔上下文 {percent}%",
    "contextDetailUsed": "{used} / {total} tokens",
    "contextDetailFromUsage": "取自上一輪回應的 usage（精確值）",
    "contextDetailEstimated": "按字數與圖片粗估（上游沒回 usage）",
    "contextDetailOutput": "最大輸出 {limit} tokens",
    "contextDetailOutputNone": "最大輸出未宣告",
    "contextDetailModel": "請求模型 {model}",
    "contextDetailMessages": "{count} 則訊息 · {images} 張圖片",
    "contextDetailClose": "知道了",
    "chatSimSendImages": "發送圖片",
    "chatSimSendTextOnly": "僅發文字",
    "chatSimSendImagesTip": "圖片會作為多模態內容一起發給模型；純文字車道報錯時切到「僅發文字」，圖就只留在介面上。",
    "chatSimImagesOn": "圖片會隨訊息發出",
    "chatSimImagesOff": "圖片只在本地展示，不發給模型",
    "chatSimAttachCamera": "拍照",
    "chatSimAttachFailed": "讀取附件失敗：{error}",
    "chatSimVoiceNoPermission": "沒有麥克風權限，無法語音輸入",
    "chatSimVoiceOpenSettings": "去設定",
    "chatSimVoiceFailed": "語音輸入失敗：{error}",
  },
  'app_en.arb': {
    "contextRingTap": "Tap to see context usage",
    "contextDetailTitle": "Context usage",
    "contextDetailPercent": "{percent}% of the context",
    "contextDetailUsed": "{used} / {total} tokens",
    "contextDetailFromUsage": "From the last response's usage (exact)",
    "contextDetailEstimated": "Estimated from text and images (no usage returned)",
    "contextDetailOutput": "Max output {limit} tokens",
    "contextDetailOutputNone": "Max output not declared",
    "contextDetailModel": "Request model {model}",
    "contextDetailMessages": "{count} messages · {images} images",
    "contextDetailClose": "Got it",
    "chatSimSendImages": "Send images",
    "chatSimSendTextOnly": "Text only",
    "chatSimSendImagesTip": "Images are sent as multimodal content. Switch to text only when a text-only lane rejects the request.",
    "chatSimImagesOn": "Images will be sent with the message",
    "chatSimImagesOff": "Images stay local and are not sent",
    "chatSimAttachCamera": "Take a photo",
    "chatSimAttachFailed": "Failed to read attachment: {error}",
    "chatSimVoiceNoPermission": "Microphone permission is required for voice input",
    "chatSimVoiceOpenSettings": "Open settings",
    "chatSimVoiceFailed": "Voice input failed: {error}",
  },
}

# 模板里带占位符的键要声明 placeholders
PLACEHOLDERS = {
  "contextDetailPercent": ["percent"],
  "contextDetailUsed": ["used", "total"],
  "contextDetailOutput": ["limit"],
  "contextDetailModel": ["model"],
  "contextDetailMessages": ["count", "images"],
  "chatSimAttachFailed": ["error"],
  "chatSimVoiceFailed": ["error"],
}

DESCS = {
  "contextRingTap": "占用环的悬停提示（点开看详情）",
  "contextDetailTitle": "上下文详情弹窗标题",
  "contextDetailPercent": "弹窗里的百分比一行",
  "contextDetailUsed": "弹窗里的 token 用量一行",
  "contextDetailFromUsage": "数字来自上游 usage 时的说明",
  "contextDetailEstimated": "数字是本地估算时的说明",
  "contextDetailOutput": "声明了最大输出时的一行",
  "contextDetailOutputNone": "没声明最大输出时的一行",
  "contextDetailModel": "当前请求目标模型",
  "contextDetailMessages": "消息条数与图片张数",
  "contextDetailClose": "弹窗关闭按钮",
  "chatSimSendImages": "带图发送开关（开）",
  "chatSimSendTextOnly": "带图发送开关（关）",
  "chatSimSendImagesTip": "带图发送开关的说明",
  "chatSimImagesOn": "切到「发送图片」时的 toast",
  "chatSimImagesOff": "切到「仅发文字」时的 toast",
  "chatSimAttachCamera": "附件清单里的拍照项",
  "chatSimAttachFailed": "选图/读文件失败",
  "chatSimVoiceNoPermission": "麦克风权限被拒",
  "chatSimVoiceOpenSettings": "去系统设置开权限",
  "chatSimVoiceFailed": "识别过程报错",
}

INTRO = {
  'app_zh_CN.arb': "把这里的对话当成下游客户端发的一条请求，走本机代理的真实链路（路由 / 回退 / 指纹 / 请求日志）。前面的消息会一起带出去。图片会随消息发给模型（纯文本车道可切「仅发文字」），文件只在界面上展示；长按消息可直接删除。",
  'app_zh.arb': "把这里的对话当成下游客户端发的一条请求，走本机代理的真实链路（路由 / 回退 / 指纹 / 请求日志）。前面的消息会一起带出去。图片会随消息发给模型（纯文本车道可切「仅发文字」），文件只在界面上展示；长按消息可直接删除。",
  'app_zh_TW.arb': "把這裡的對話當成下游客戶端發的一條請求，走本機代理的真實鏈路（路由 / 回退 / 指紋 / 請求日誌）。前面的訊息會一起帶出去。圖片會隨訊息發給模型（純文字車道可切「僅發文字」），檔案只在介面上展示；長按訊息可直接刪除。",
  'app_en.arb': "Sends this conversation as a downstream client would, through the local proxy's real path (routing / failover / fingerprint / request log). Earlier messages are included. Images go out with the message (switch to text only for text-only lanes); file attachments stay display-only. Long-press a message to delete it.",
}


def esc(s):
    return json.dumps(s, ensure_ascii=False)


for fname, keys in NEW.items():
    path = os.path.join(BASE, fname)
    with io.open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    # 1) 换掉「附件仅本地展示」那句介绍
    old_intro_start = text.index('"chatSimIntro": "')
    old_intro_end = text.index('",', old_intro_start) + 1
    text = text[:old_intro_start] + '"chatSimIntro": ' + esc(INTRO[fname]) + text[old_intro_end:]
    # 2) 末尾追加新键（最后一个 } 之前）
    tail = text.rstrip()
    assert tail.endswith('}'), fname
    body = tail[:-1].rstrip()
    block = []
    for k, v in keys.items():
        block.append('  %s: %s' % (esc(k), esc(v)))
        if fname == 'app_zh_CN.arb':
            meta = {'description': DESCS.get(k, '')}
            ph = PLACEHOLDERS.get(k)
            if ph:
                meta['placeholders'] = {p: {'type': 'String'} for p in ph}
            block.append('  %s: %s' % (esc('@' + k), json.dumps(meta, ensure_ascii=False)))
    new_text = body + ',\n' + ',\n'.join(block) + '\n}\n'
    with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(new_text)
    json.loads(new_text)  # 自检
    print('ok', fname, len(keys))
