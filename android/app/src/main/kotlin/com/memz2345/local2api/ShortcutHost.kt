package com.memz2345.local2api

import android.app.Activity
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 安卓长按图标快捷入口（App Shortcuts，InstallerX-Revived 同款模式）。
 *
 * 三个入口全部走动态 Shortcut：Dart 侧（AppShortcuts）在启动与服务状态变化时
 * 重发清单（「启动/关闭服务」标签随运行状态换，文案由 Dart 的 l10n 现算）；
 * 点触后经 MainActivity（singleTop）带回 [EXTRA_SHORTCUT] extra 暂存在
 * [pending]，Dart 回到前台时通过 takePending 取走分发。
 */
object ShortcutHost {
    private const val CHANNEL = "com.memz2345.local2api/shortcuts"
    const val EXTRA_SHORTCUT = "shortcut"

    @Volatile
    private var pending: String? = null

    private var activity: Activity? = null

    fun install(activity: Activity, messenger: BinaryMessenger) {
        this.activity = activity
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    @Suppress("UNCHECKED_CAST")
                    val list =
                        call.argument<List<Map<String, Any>>>("shortcuts")
                            ?: emptyList()
                    publish(activity, list)
                    result.success(null)
                }
                "takePending" -> result.success(pending.also { pending = null })
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        activity = null
    }

    /** MainActivity.onCreate / onNewIntent 里调用：暂存 Shortcut 动作 id。 */
    fun handleIntent(intent: Intent?) {
        val id = intent?.getStringExtra(EXTRA_SHORTCUT) ?: return
        pending = id
    }

    private fun publish(activity: Activity, list: List<Map<String, Any>>) {
        // 走 androidx compat API：本机 SDK 的 android.jar 精简掉了
        // android.graphics.Icon（ShortcutManager 在、Icon 不在），
        // compat 栈从 androidx.core 解析，不受影响。
        val infos = list.mapNotNull { m ->
            val id = m["id"] as? String ?: return@mapNotNull null
            val label = m["label"] as? String ?: return@mapNotNull null
            val iconRes = when (m["icon"] as? String) {
                "chart" -> R.drawable.ic_shortcut_chart
                "compass" -> R.drawable.ic_shortcut_compass
                else -> R.drawable.ic_shortcut_power
            }
            val intent = Intent(activity, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra(EXTRA_SHORTCUT, id)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            ShortcutInfoCompat.Builder(activity, id)
                .setShortLabel(label)
                .setIcon(IconCompat.createWithResource(activity, iconRes))
                .setIntent(intent)
                .build()
        }
        ShortcutManagerCompat.setDynamicShortcuts(activity, infos)
    }
}
