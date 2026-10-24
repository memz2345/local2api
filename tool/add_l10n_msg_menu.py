#!/usr/bin/env python3
"""往 4 个 .arb 里加对话模拟「长按菜单 / 下载音频」的文案。

用 json 读、按原顺序追加、再按 2 空格缩进写回（与现有文件格式一致），
避免手工插行把 JSON 弄坏。幂等：已存在的 key 会被覆盖成新值。
"""
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
L10N = ROOT / "lib" / "l10n"

PLACEHOLDER_KEYS = {
    "chatSimDownloadSaved": ("path", "另存为完成后回报的落盘路径"),
    "chatSimDownloadFailed": ("error", "合成 / 转码 / 存盘任一步的错误文案"),
}

ZH = {
    "chatSimMsgMenuTitle": "消息操作",
    "chatSimMsgSpeak": "朗读",
    "chatSimMsgStopSpeak": "停止朗读",
    "chatSimMsgRegenerate": "重新回答",
    "chatSimMsgDownload": "下载音频",
    "chatSimDownloadTitle": "下载音频",
    "chatSimDownloadFormat": "格式",
    "chatSimDownloadMp3Desc": "通用音频，兼容性最好",
    "chatSimDownloadSilkDesc": "SILK v3，微信 / QQ 的语音格式",
    "chatSimDownloadSlkDesc": "与 SILK 字节相同，只是扩展名不同",
    "chatSimDownloadTencent": "腾讯兼容（-tencent）",
    "chatSimDownloadTencentDesc": "文件头加 0x02、结尾不写哨兵包，微信 / QQ 才认",
    "chatSimDownloadAction": "下载",
    "chatSimDownloadBusy": "正在合成音频…",
    "chatSimDownloadCanceled": "已取消保存",
    "chatSimDownloadSaved": "已保存：{path}",
    "chatSimDownloadFailed": "导出失败：{error}",
}

ZH_TW = {
    "chatSimMsgMenuTitle": "訊息操作",
    "chatSimMsgSpeak": "朗讀",
    "chatSimMsgStopSpeak": "停止朗讀",
    "chatSimMsgRegenerate": "重新回答",
    "chatSimMsgDownload": "下載音訊",
    "chatSimDownloadTitle": "下載音訊",
    "chatSimDownloadFormat": "格式",
    "chatSimDownloadMp3Desc": "通用音訊，相容性最好",
    "chatSimDownloadSilkDesc": "SILK v3，微信 / QQ 的語音格式",
    "chatSimDownloadSlkDesc": "與 SILK 位元組相同，只是副檔名不同",
    "chatSimDownloadTencent": "騰訊相容（-tencent）",
    "chatSimDownloadTencentDesc": "檔案頭加 0x02、結尾不寫哨兵包，微信 / QQ 才認",
    "chatSimDownloadAction": "下載",
    "chatSimDownloadBusy": "正在合成音訊…",
    "chatSimDownloadCanceled": "已取消儲存",
    "chatSimDownloadSaved": "已儲存：{path}",
    "chatSimDownloadFailed": "匯出失敗：{error}",
}

EN = {
    "chatSimMsgMenuTitle": "Message actions",
    "chatSimMsgSpeak": "Read aloud",
    "chatSimMsgStopSpeak": "Stop reading",
    "chatSimMsgRegenerate": "Regenerate",
    "chatSimMsgDownload": "Download audio",
    "chatSimDownloadTitle": "Download audio",
    "chatSimDownloadFormat": "Format",
    "chatSimDownloadMp3Desc": "Universal audio, widest compatibility",
    "chatSimDownloadSilkDesc": "SILK v3 — the WeChat / QQ voice format",
    "chatSimDownloadSlkDesc": "Same bytes as SILK, different extension",
    "chatSimDownloadTencent": "Tencent compatible (-tencent)",
    "chatSimDownloadTencentDesc": (
        "Adds a 0x02 header byte and drops the trailing sentinel packet; "
        "WeChat / QQ will not play it otherwise"
    ),
    "chatSimDownloadAction": "Download",
    "chatSimDownloadBusy": "Synthesizing audio…",
    "chatSimDownloadCanceled": "Save canceled",
    "chatSimDownloadSaved": "Saved: {path}",
    "chatSimDownloadFailed": "Export failed: {error}",
}

FILES = {
    "app_zh_CN.arb": ZH,
    "app_zh.arb": ZH,
    "app_zh_TW.arb": ZH_TW,
    "app_en.arb": EN,
}


def main() -> int:
    for name, strings in FILES.items():
        path = L10N / name
        data = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=collections.OrderedDict,
        )
        for key, value in strings.items():
            data[key] = value
            if key in PLACEHOLDER_KEYS:
                ph, desc = PLACEHOLDER_KEYS[key]
                data[f"@{key}"] = collections.OrderedDict(
                    [
                        ("description", desc),
                        (
                            "placeholders",
                            collections.OrderedDict(
                                [(ph, collections.OrderedDict([("type", "String")]))]
                            ),
                        ),
                    ]
                )
        path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"{name}: {len(strings)} 条文案已写入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
