#!/usr/bin/env python3
# 一次性给 4 份 arb 追加「长按说话」弹层的文案（模板 zh_CN 补 @-metadata）。
import io
import json
import os

BASE = os.path.join(os.path.dirname(__file__), '..', 'lib', 'l10n')

NEW = {
    'app_zh_CN.arb': {
        "voiceHoldToTalk": "按住说话",
        "@voiceHoldToTalk": {"description": "录音弹层的底栏提示（未按下时）"},
        "voiceReleaseToSend": "松开结束",
        "@voiceReleaseToSend": {"description": "录音弹层的底栏提示（按住中）"},
        "voiceListeningHint": "正在聆听…",
        "@voiceListeningHint": {"description": "收音中还没有识别文本时的提示"},
        "voiceRecognizing": "识别中…",
        "@voiceRecognizing": {"description": "松手后等最后一版定稿的提示"},
        "voiceNothingHeard": "没听清，再按住说一次",
        "@voiceNothingHeard": {"description": "松手后一条结果都没拿到"},
        "chatSimCallPeer": "和 {name} 通话",
        "@chatSimCallPeer": {
            "description": "通话选择弹层里语音选项的摘要（当前角色名）",
            "placeholders": {"name": {"type": "String"}},
        },
    },
    'app_zh.arb': {
        "voiceHoldToTalk": "按住说话",
        "voiceReleaseToSend": "松开结束",
        "voiceListeningHint": "正在聆听…",
        "voiceRecognizing": "识别中…",
        "voiceNothingHeard": "没听清，再按住说一次",
        "chatSimCallPeer": "和 {name} 通话",
    },
    'app_zh_TW.arb': {
        "voiceHoldToTalk": "按住說話",
        "voiceReleaseToSend": "放開結束",
        "voiceListeningHint": "正在聆聽…",
        "voiceRecognizing": "辨識中…",
        "voiceNothingHeard": "沒聽清楚，再按住說一次",
        "chatSimCallPeer": "和 {name} 通話",
    },
    'app_en.arb': {
        "voiceHoldToTalk": "Hold to talk",
        "voiceReleaseToSend": "Release to finish",
        "voiceListeningHint": "Listening…",
        "voiceRecognizing": "Recognizing…",
        "voiceNothingHeard": "Nothing heard, hold and try again",
        "chatSimCallPeer": "Call {name}",
    },
}


def load(path):
    with io.open(path, 'r', encoding='utf-8') as f:
        return json.load(f, object_pairs_hook=lambda pairs: dict(pairs))


for name, adds in NEW.items():
    path = os.path.join(BASE, name)
    with io.open(path, 'r', encoding='utf-8') as f:
        raw = f.read()
    data = json.loads(raw)
    for k, v in adds.items():
        if k in data:
            print(f'{name}: {k} 已存在，跳过')
            continue
        data[k] = v
    # 保持缩进 2、不转义中文，与现有文件一致。
    out = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(out)
    print(f'{name}: +{len(adds)} keys')
