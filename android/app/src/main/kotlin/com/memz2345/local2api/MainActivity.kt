package com.memz2345.local2api

import android.app.LocaleManager
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity（而不是 FlutterActivity）：local_auth 的 BiometricPrompt
// 要求宿主 Activity 是 androidx FragmentActivity（生物识别锁，Hail 同款）。
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.memz2345.local2api/locale"
    private val dynamicColorChannelName = "com.memz2345.local2api/dynamic_color"

    private var dynamicColorChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 长按图标 Shortcut 点进来（冷启动）：暂存动作，Dart 回前台取走分发
        ShortcutHost.handleIntent(intent)
        // 通知点击把应用拉起来：记下它带的路由，Dart 侧 getLaunchRoute 取
        NotificationHost.captureLaunchRoute(intent)
        val debuggable =
            (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val selftestOn = java.io.File(getExternalFilesDir(null), "selftest.on").exists()
        if (debuggable && selftestOn) {
            // 相机自检：只在 external files 里放了 selftest.on 标记时跑一次
            // （否则每次启动都碰相机，正常调试会被干扰）。
            android.os.Handler(mainLooper).postDelayed({
                Camera2Scanner.selfTest(this, requireNotNull(flutterEngine))
            }, 5000)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop：App 已在前台/后台时 Shortcut 点进来走这里
        ShortcutHost.handleIntent(intent)
        NotificationHost.captureLaunchRoute(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppLocales" -> {
                        // Android 13+：读系统「应用语言」设置
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val lm = getSystemService(LocaleManager::class.java)
                            val locales = lm.applicationLocales
                            val tags = (0 until locales.size()).map { locales.get(it).toLanguageTag() }
                            result.success(tags)
                        } else {
                            result.success(emptyList<String>())
                        }
                    }
                    "setAppLocale" -> {
                        // Android 13+：把 App 内选择写回系统（空 tag = 恢复跟随系统）
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val tag = call.argument<String>("tag")
                            val lm = getSystemService(LocaleManager::class.java)
                            lm.applicationLocales = if (tag.isNullOrEmpty()) {
                                LocaleList.getEmptyLocaleList()
                            } else {
                                LocaleList.forLanguageTags(tag)
                            }
                        }
                        result.success(null)
                    }
                    "getSystemHttpProxy" -> {
                        // 全局 HTTP 代理（"host:port" 或 null）：模拟器/内网
                        // 里给实验室下载用（dart:io 不会自动用 Android 全局代理）
                        val proxy = android.provider.Settings.Global.getString(
                            contentResolver,
                            android.provider.Settings.Global.HTTP_PROXY,
                        )
                        result.success(proxy)
                    }
                    else -> result.notImplemented()
                }
            }

        // 动态取色：壁纸/深色模式变化时通知 Dart 重新拉取 Material You 调色板
        dynamicColorChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            dynamicColorChannelName,
        )

        // 原生液态玻璃底栏 + 原生 tooltip（NaviFlash 同款平台通道实现）
        LiquidGlassBarHost.install(this, flutterEngine.dartExecutor.binaryMessenger)
        NativeTooltipHost.install(this, flutterEngine.dartExecutor.binaryMessenger)
        // 设备物理屏幕圆角：iOS 风格页面转场的圆角贴合屏幕本身
        DeviceCornerChannel.install(this, flutterEngine.dartExecutor.binaryMessenger)
        // 相机镜头探针：广角枚举排查用（channel + logcat L2ACamProbe）
        CameraLensProbe.install(this, flutterEngine.dartExecutor.binaryMessenger)
        CameraLensProbe.logOnce(this)
        // Camera2 直连扫码：厂商把超广角从 cameraIdList/CameraX 里藏了，
        // 只有按 id 直开 Camera2 才够得着（见 Camera2Scanner 的说明）。
        Camera2Scanner.install(this, flutterEngine)
        // Android 16 以进度为中心的通知（实验室任务进度 / 提问回复 / 结果）
        NotificationHost.install(this, flutterEngine.dartExecutor.binaryMessenger)
        // Shizuku：实验室以 shell 身份拉起 node（release 上 W^X 禁直接 exec）
        ShizukuHost.install(this, flutterEngine.dartExecutor.binaryMessenger)
        // Chrome Custom Tabs：内置浏览器的「外部打开」交给 Chromium 系浏览器
        CustomTabsHost.install(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            dynamicColorChannel?.invokeMethod("onColorsChanged", null)
        }
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            dynamicColorChannel?.invokeMethod("onColorsChanged", null)
        }
    }

    override fun onDestroy() {
        LiquidGlassBarHost.dispose()
        NativeTooltipHost.dispose()
        DeviceCornerChannel.dispose()
        ShortcutHost.dispose()
        ShizukuHost.dispose()
        CustomTabsHost.dispose()
        super.onDestroy()
    }
}
