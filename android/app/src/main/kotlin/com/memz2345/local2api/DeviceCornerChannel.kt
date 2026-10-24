package com.memz2345.local2api

import android.app.Activity
import android.os.Build
import android.util.Log
import android.view.RoundedCorner
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 设备**物理屏幕**四角的圆角半径探测。
 *
 * 通道：com.memz2345.local2api/device_corners
 * 方法：
 *   getCornerRadius() -> map { radiusDp: Double, source: String }
 *
 * 用途：iOS 风格页面切换（新页面从尾侧滑入 + 全程圆角卡片）里，新页面左上 /
 * 左下那两个圆角在观感上就是**屏幕的圆角**；圆角值贴合屏幕本身的圆角时，
 * 滑入过程看起来才像「一张卡片从屏幕边缘被推进来」，而不是随便一个半径。
 *
 * 取值链（取到 > 0 即返回，全部失败返回 0 → Dart 侧回退到用户手动值）：
 *   1. `WindowInsets.getRoundedCorner(position)`（Android 12 / API 31+ 官方 API）。
 *      取窗口 insets 里四个角的最大值。
 *   2. `Display.getRoundedCorner(position)`（同 API 31+；部分 ROM 只在
 *      Display 上给值、WindowInsets 返回 null，反之亦然，两个都试）。
 *   3. 框架私有 dimen 资源（`config_roundedCornerRadius` 等）。Android 12 之前
 *      没有公开 API，只能碰运气读资源；读不到就老实返回 0。
 *
 * 单位：返回 **dp（逻辑像素）** —— 物理值拿到的是 px，除以 `displayMetrics.density`
 * 得到 dp；Flutter 的逻辑像素在 Android 上就等于 dp。
 *
 * 注意：不做「状态栏高度 ≈ 圆角」这类猜测。猜错的代价是给方角屏平白加上圆角，
 * 比读不到（回退手动值）更糟。
 */
object DeviceCornerChannel {

    private const val CHANNEL_NAME = "com.memz2345.local2api/device_corners"
    private const val TAG = "DeviceCorner"

    private var channel: MethodChannel? = null

    private val CORNER_POSITIONS = intArrayOf(
        RoundedCorner.POSITION_TOP_LEFT,
        RoundedCorner.POSITION_TOP_RIGHT,
        RoundedCorner.POSITION_BOTTOM_LEFT,
        RoundedCorner.POSITION_BOTTOM_RIGHT,
    )

    /** Android 12 之前各 ROM 用过的私有资源名（存在即用，不存在无副作用）。 */
    private val RADIUS_RESOURCES = arrayOf(
        "config_roundedCornerRadius",
        "config_roundedCornerTopRadius",
        "config_roundedCornerBottomRadius",
        "config_mainBuiltInDisplayRoundedCornerRadius",
    )

    fun install(activity: Activity, messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, CHANNEL_NAME)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCornerRadius" -> {
                    val (radiusDp, source) = detect(activity)
                    // 排查用：`adb logcat -s DeviceCorner`
                    Log.i(
                        TAG,
                        "屏幕圆角 ${radiusDp}dp（来源 $source）" +
                            " insets=${insetsPx(activity)}" +
                            " display=${displayPx(activity)}" +
                            " res=${resourcePx(activity)}" +
                            " density=${activity.resources.displayMetrics.density}"
                    )
                    result.success(
                        mapOf("radiusDp" to radiusDp, "source" to source)
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /** 返回 (dp 半径, 来源标签)；探测不到时 (0.0, "none")。 */
    private fun detect(activity: Activity): Pair<Double, String> {
        val windowInsetsPx = insetsPx(activity)
        if (windowInsetsPx > 0) return toDp(activity, windowInsetsPx) to "windowInsets"

        val displayPx = displayPx(activity)
        if (displayPx > 0) return toDp(activity, displayPx) to "display"

        val resourcePx = resourcePx(activity)
        if (resourcePx > 0) return toDp(activity, resourcePx) to "resource"

        return 0.0 to "none"
    }

    fun insetsPx(activity: Activity): Int =
        runCatching { fromWindowInsets(activity) }.getOrDefault(0)

    fun displayPx(activity: Activity): Int =
        runCatching { fromDisplay(activity) }.getOrDefault(0)

    fun resourcePx(activity: Activity): Int =
        runCatching { fromResource(activity) }.getOrDefault(0)

    private fun toDp(activity: Activity, px: Int): Double {
        val density = activity.resources.displayMetrics.density
        val safeDensity = if (density > 0f) density.toDouble() else 1.0
        return px / safeDensity
    }

    /** 官方 API：从窗口 insets 取四角最大值（px）。 */
    private fun fromWindowInsets(activity: Activity): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0
        val insets = activity.windowManager.currentWindowMetrics.windowInsets
        return maxRadiusOf { insets.getRoundedCorner(it) }
    }

    /** Display 兜底：部分 ROM 只在 Display 上给值（px）。 */
    @Suppress("DEPRECATION")
    private fun fromDisplay(activity: Activity): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0
        val display = activity.display ?: return 0
        return maxRadiusOf { display.getRoundedCorner(it) }
    }

    private inline fun maxRadiusOf(cornerAt: (Int) -> RoundedCorner?): Int {
        var max = 0
        for (position in CORNER_POSITIONS) {
            val radius = runCatching { cornerAt(position)?.radius }.getOrNull() ?: 0
            if (radius > max) max = radius
        }
        return max
    }

    /** 私有资源兜底（Android 12 之前唯一可能的路子）。 */
    private fun fromResource(activity: Activity): Int {
        val res = activity.resources
        for (name in RADIUS_RESOURCES) {
            val id = res.getIdentifier(name, "dimen", "android")
            if (id == 0) continue
            val px = runCatching { res.getDimensionPixelSize(id) }.getOrDefault(0)
            if (px > 0) return px
        }
        return 0
    }
}
