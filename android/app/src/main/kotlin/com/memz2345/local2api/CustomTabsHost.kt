package com.memz2345.local2api

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Chrome Custom Tabs 桥（Dart 侧见 `services/custom_tabs_service.dart`）。
 *
 * 为什么不用 ACTION_VIEW：系统默认浏览器可能是 WebView 壳，重前端页面
 * （SillyTavern / dsh web）在那种壳里体验很差。Custom Tabs 把链接交给用户
 * 装的 Chromium 系浏览器（Chrome / Edge / Brave / 三星…），复用它的内核与
 * Cookie，但外壳仍是「应用内的一个标签页」—— TiebaLite 就是这么干的。
 *
 * 只做三件事：有没有（isAvailable）、有哪几个（listBrowsers）、打开（open）。
 * 任何一步失败都吐 false / 空表，让 Dart 侧回退到系统浏览器。
 */
object CustomTabsHost {
    private const val TAG = "L2ACustomTabs"
    private const val CHANNEL = "com.memz2345.local2api/custom_tabs"

    /** 支持 Custom Tabs 的浏览器都会声明这个 Service（Chrome 自定义协议）。 */
    private const val ACTION_CUSTOM_TABS_CONNECTION =
        "android.support.customtabs.action.CustomTabsService"

    private var activity: Activity? = null

    fun install(host: Activity, messenger: BinaryMessenger) {
        activity = host
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            val act = activity
            if (act == null || act.isFinishing || act.isDestroyed) {
                result.error("no_activity", "Activity is gone", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                // 注意：不能用 CustomTabsClient.getPackageName() 判断 —— 它返回的是
                // 「系统默认浏览器里支持 CT 的那家」，默认浏览器本身不支持 CT
                // （比如裸 WebView 浏览器）时它会返回 null，但 Chrome 明明装着。
                "isAvailable" -> result.success(listBrowsers(act).isNotEmpty())
                "listBrowsers" -> result.success(listBrowsers(act))
                "open" -> {
                    val url = call.argument<String>("url").orEmpty()
                    if (url.isEmpty()) {
                        result.error("bad_args", "url is empty", null)
                        return@setMethodCallHandler
                    }
                    val pkg = call.argument<String>("package")
                    val toolbarColor = call.argument<Int>("toolbarColor")
                    val showTitle = call.argument<Boolean>("showTitle") ?: true
                    try {
                        open(act, url, pkg, toolbarColor, showTitle)
                        result.success(true)
                    } catch (t: Throwable) {
                        Log.w(TAG, "open failed: $t")
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        activity = null
    }

    /** 系统默认的 Custom Tabs 提供者（可能为 null = 一台都没装）。 */
    private fun defaultPackage(act: Activity): String? = try {
        CustomTabsClient.getPackageName(act, null)
    } catch (t: Throwable) {
        Log.w(TAG, "getPackageName failed: $t")
        null
    }

    /**
     * 装了 Custom Tabs 服务的浏览器。
     *
     * Android 11+ 的包可见性靠 manifest 里的 `<queries>`（本工程已加），
     * 这里不用 MATCH_ALL —— 那个会把被用户禁用的组件也捞出来。
     */
    private fun listBrowsers(act: Activity): List<Map<String, Any?>> {
        val pm = act.packageManager
        val intent = Intent(ACTION_CUSTOM_TABS_CONNECTION)
        val resolved = try { pm.queryIntentServices(intent, 0) } catch (t: Throwable) {
            Log.w(TAG, "queryIntentServices failed: $t")
            null
        } ?: return emptyList()

        val defaultPkg = defaultPackage(act)
        val seen = LinkedHashSet<String>()
        val out = ArrayList<Map<String, Any?>>()
        for (info in resolved) {
            val serviceInfo = info.serviceInfo ?: continue
            val pkg = serviceInfo.packageName ?: continue
            if (pkg == act.packageName) continue
            if (!seen.add(pkg)) continue
            val label = try {
                serviceInfo.loadLabel(pm).toString()
            } catch (t: Throwable) {
                pkg
            }
            out.add(
                mapOf(
                    "packageName" to pkg,
                    "label" to label,
                    "isDefault" to (pkg == defaultPkg),
                ),
            )
        }
        out.sortWith(
            compareByDescending<Map<String, Any?>> { it["isDefault"] == true }
                .thenBy { (it["label"] as? String ?: "").lowercase() },
        )
        return out
    }

    private fun open(
        act: Activity,
        url: String,
        pkg: String?,
        toolbarColor: Int?,
        showTitle: Boolean,
    ) {
        val builder = CustomTabsIntent.Builder()
            .setShowTitle(showTitle)
            .setUrlBarHidingEnabled(true)
            // 分享按钮在这个场景用不上，关掉省得挤地址栏
            .setShareState(CustomTabsIntent.SHARE_STATE_OFF)
        if (toolbarColor != null) {
            // Chrome 会自己挑对比度合适的图标色，深色/浅色主题都能用
            builder.setToolbarColor(toolbarColor)
        }
        val customTabsIntent = builder.build()
        if (!pkg.isNullOrEmpty()) {
            customTabsIntent.intent.setPackage(pkg)
        }
        Log.i(TAG, "open pkg=${pkg ?: "<default>"} url=$url")
        try {
            customTabsIntent.launchUrl(act, Uri.parse(url))
        } catch (t: Throwable) {
            if (pkg.isNullOrEmpty()) throw t
            // 选定的浏览器不认（被卸载 / 禁用）：退回系统默认提供者
            Log.w(TAG, "open with $pkg failed, retry default: $t")
            val retry = builder.build()
            retry.launchUrl(act, Uri.parse(url))
        }
    }
}
