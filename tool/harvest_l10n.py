# 从 naviflash 的 ARB 批量搬运 local2api 移植页面所需的 l10n 键
import json, re, subprocess, sys

FILES = [
    "lib/screens/display_settings_screen.dart",
    "lib/screens/theme_selector_screen.dart",
    "lib/screens/font_weight_screen.dart",
    "lib/screens/display_scale_page.dart",
    "lib/widgets/custom_toast.dart",
    "lib/widgets/app_toast.dart",
    "lib/widgets/more_menu_sheet.dart",
    "lib/widgets/morph_card.dart",
    "lib/widgets/morph_widgets.dart",
    "lib/widgets/expressive_app_bar.dart",
    "lib/widgets/liquid_glass_menu_button.dart",
    "lib/widgets/long_press_glass_tab_switcher.dart",
    "lib/widgets/color_palette.dart",
    "lib/widgets/page_background.dart",
    "lib/widgets/frosted_sheet.dart",
    "lib/widgets/collapsible_side_bar.dart",
    "lib/ui/logs_page.dart",
    "lib/ui/upstream_edit_page.dart",
]
NAV = "G:/192/naviflash/lib/l10n"
MINE = "lib/l10n"
# 额外手工键（settings_page 新入口）
EXTRA = ["settingsDisplaySection", "settingsDisplayEntry"]

# 1. 收集键名（两种引用形式：l10n.xxx / AppLocalizations.of(...).xxx）
keys = set(EXTRA)
for f in FILES:
    with open(f, encoding="utf-8") as fh:
        text = fh.read()
    keys |= set(re.findall(r"\bl10n\.([a-zA-Z0-9_]+)", text))
    keys |= set(re.findall(r"AppLocalizations\.of\([^)]*\)\.([a-zA-Z0-9_]+)", text))
keys = sorted(keys)
print(f"need {len(keys)} keys")

# 2. 读 naviflash 的四份 ARB
def load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)

nav_zh = load(f"{NAV}/app_zh_CN.arb")
nav_en = load(f"{NAV}/app_en.arb")
nav_tw = load(f"{NAV}/app_zh_TW.arb")
nav_zhbase = load(f"{NAV}/app_zh.arb")

# 3. 搬运并写回
def merge(dst_path, src, keys):
    dst = load(dst_path)
    missing = []
    for k in keys:
        if k in src:
            dst[k] = src[k]
            meta = "@" + k
            if meta in src:
                dst[meta] = src[meta]
        else:
            missing.append(k)
    with open(dst_path, "w", encoding="utf-8") as fh:
        json.dump(dst, fh, ensure_ascii=False, indent=2)
    return missing

m1 = merge(f"{MINE}/app_zh_CN.arb", nav_zh, keys)
m2 = merge(f"{MINE}/app_en.arb", nav_en, keys)
m3 = merge(f"{MINE}/app_zh_TW.arb", nav_tw, keys)
m4 = merge(f"{MINE}/app_zh.arb", nav_zhbase, keys)

print("missing zh:", m1)
print("missing en:", m2)
print("missing tw:", m3)
print("missing zhbase:", m4)
