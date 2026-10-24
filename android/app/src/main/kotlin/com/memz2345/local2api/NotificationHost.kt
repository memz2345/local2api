package com.memz2345.local2api

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Android 通知桥（Dart 侧见 `services/android_notifications.dart`）。
 *
 * 两件事：
 *
 * 1. **Android 16（API 36）的「以进度为中心的通知」**
 *    `Notification.ProgressStyle`：把一段任务画成带分段（segments）与里程碑点
 *    （points）的进度条，可以申请升级成「实时更新」（Live Update）—— 置顶在
 *    通知抽屉、锁屏和状态栏 chip 上。升级是**显式请求**才有的：
 *    `setRequestPromotedOngoing(true)` + manifest 里的
 *    `POST_PROMOTED_NOTIFICATIONS` + ongoing + 有标题 + 无自定义视图 +
 *    非 colorized + 渠道 importance 不是 MIN。少一条就静默降级成普通通知，
 *    不报错 —— 所以 `show` 的返回值里带 `promoted`（系统实际给没给）。
 *
 * 2. **带回复的通知**：`RemoteInput` 收用户输入的文字，经广播回到本类，
 *    再 `invokeMethod("onReply")` 交给 Dart。应用进程没起来时（用户只点了
 *    通知里的回复，而 App 已被杀）回复先落到 SharedPreferences，下次
 *    `drainPending` 时补发 —— 不然这条回复就丢了。
 *
 * 低于 API 36 的设备走 `setProgress(max, current, indeterminate)`，样式退化
 * 但语义一致；Dart 侧不用分支。
 */
object NotificationHost {
    private const val TAG = "L2ANotification"
    private const val CHANNEL = "com.memz2345.local2api/notifications"

    /** 任务进度（进行中的那条，ongoing）。 */
    private const val CHANNEL_TASKS = "lab_tasks"
    /** 结果 / 提问（可清除，会提示）。 */
    private const val CHANNEL_RESULTS = "lab_results"

    private const val ACTION_REPLY = "com.memz2345.local2api.NOTIFY_REPLY"
    private const val ACTION_CLICK = "com.memz2345.local2api.NOTIFY_ACTION"
    private const val ACTION_DISMISS = "com.memz2345.local2api.NOTIFY_DISMISS"
    const val REMOTE_INPUT_KEY = "l2a_reply"
    const val EXTRA_ROUTE = "com.memz2345.local2api.route"
    const val EXTRA_NOTIFY_ID = "l2a_notify_id"
    const val EXTRA_ACTION_KEY = "l2a_action_key"

    private const val PREFS = "l2a_notifications"
    private const val PREF_PENDING = "pending_events"

    /** Dart 侧没起来时，回复/点击先攒在这里（JSON 数组的字符串形式）。 */
    private const val MAX_PENDING = 32

    private var activity: Activity? = null
    private var appContext: Context? = null
    private var events: MethodChannel? = null

    /** 通知把应用拉起来时带的路由（冷启动也要能取到，所以放静态）。 */
    @Volatile
    var launchRoute: String? = null
        private set

    fun install(host: Activity, messenger: BinaryMessenger) {
        activity = host
        appContext = host.applicationContext
        events = MethodChannel(messenger, CHANNEL + "_events")
        createChannels(host)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val ctx = appContext ?: host.applicationContext
            when (call.method) {
                "hasPermission" -> result.success(hasPermission(ctx))
                "requestPermission" -> {
                    val act = activity
                    if (act == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    if (hasPermission(ctx)) {
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        // 13 以下装完就有权限，没权限说明用户在设置里关了 → 跳设置
                        openNotificationSettings(ctx)
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        act.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4201)
                        result.success(true)
                    } catch (t: Throwable) {
                        Log.w(TAG, "requestPermission failed: $t")
                        result.success(false)
                    }
                }
                "canPostPromoted" -> result.success(canPostPromoted(ctx))
                "show" -> result.success(show(ctx, call))
                "cancel" -> {
                    val id = intArg(call, "id")
                    manager(ctx)?.cancel(id)
                    result.success(null)
                }
                "cancelAll" -> {
                    manager(ctx)?.cancelAll()
                    result.success(null)
                }
                "drainPending" -> result.success(drainPending(ctx))
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations(ctx))
                "requestIgnoreBatteryOptimizations" ->
                    result.success(requestIgnoreBatteryOptimizations(ctx))
                "openBatteryOptimizationSettings" -> {
                    safeStartActivity(
                        ctx,
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings(ctx)
                    result.success(null)
                }
                "getLaunchRoute" -> result.success(launchRoute)
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        activity = null
        events = null
    }

    /** 通知点击把应用拉起来时，把路由从 intent 里摘出来给 Dart 取。 */
    fun captureLaunchRoute(intent: Intent?) {
        val route = intent?.getStringExtra(EXTRA_ROUTE)
        if (!route.isNullOrEmpty()) launchRoute = route
    }

    // ---- 权限 / 渠道 ----

    private fun hasPermission(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return manager(ctx)?.areNotificationsEnabled() ?: true
        }
        return ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    /**
     * 系统允许本应用发「实时更新」（升级版通知）吗？
     *
     * API 36 以下一律 false。**必须用反射**：vivo 的 Android 16 把
     * `NotificationManager.canPostPromotedNotifications` 和
     * `Notification.Builder.setRequestPromotedOngoing` 都阉了 —— SDK_INT 报 36
     * 但 framework 里没这两个方法，直接调用就是 NoSuchMethodError（Error，
     * 不是 Exception，会把进程打死）。
     */
    private fun canPostPromoted(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return false
        val nm = manager(ctx) ?: return false
        return try {
            val method = NotificationManager::class.java
                .getMethod("canPostPromotedNotifications")
            (method.invoke(nm) as? Boolean) ?: false
        } catch (t: Throwable) {
            Log.i(TAG, "canPostPromotedNotifications 不可用（厂商 ROM 缺方法）")
            false
        }
    }

    /** 反射调 `Builder.setRequestPromotedOngoing(true)`；缺方法就静默降级。 */
    private fun requestPromoted(builder: Notification.Builder): Boolean = try {
        val method = Notification.Builder::class.java
            .getMethod("setRequestPromotedOngoing", java.lang.Boolean.TYPE)
        method.invoke(builder, true)
        true
    } catch (t: Throwable) {
        Log.i(TAG, "setRequestPromotedOngoing 不可用（厂商 ROM 缺方法）")
        false
    }

    private fun createChannels(ctx: Context) {
        val nm = manager(ctx) ?: return
        // importance 必须是 DEFAULT 及以上：MIN 的通知没有资格被升级成实时更新。
        val tasks = NotificationChannel(
            CHANNEL_TASKS,
            "实验室任务",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "实验室任务的执行进度与提问"
            setSound(null, null)
            enableVibration(false)
        }
        val results = NotificationChannel(
            CHANNEL_RESULTS,
            "实验室结果",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "任务结果、需要你回复的提问"
        }
        try {
            nm.createNotificationChannel(tasks)
            nm.createNotificationChannel(results)
        } catch (t: Throwable) {
            Log.w(TAG, "createNotificationChannel failed: $t")
        }
    }

    private fun manager(ctx: Context): NotificationManager? =
        ctx.getSystemService(NotificationManager::class.java)

    // ---- 发通知 ----

    /** 组装并发出/更新一条通知；返回给 Dart 的是这条通知的实际状态。 */
    private fun show(ctx: Context, call: io.flutter.plugin.common.MethodCall): Map<String, Any?> {
        val id = intArg(call, "id")
        val title = call.argument<String>("title").orEmpty()
        val text = call.argument<String>("text").orEmpty()
        val subText = call.argument<String>("subText")
        val bigText = call.argument<String>("bigText")
        val ongoing = call.argument<Boolean>("ongoing") ?: false
        val promoted = call.argument<Boolean>("promoted") ?: false
        val silent = call.argument<Boolean>("silent") ?: false
        val alertOnce = call.argument<Boolean>("alertOnce") ?: true
        val autoCancel = call.argument<Boolean>("autoCancel") ?: !ongoing
        val showWhen = call.argument<Boolean>("showWhen") ?: false
        val route = call.argument<String>("route")
        val channelId =
            if (call.argument<Boolean>("result") == true) CHANNEL_RESULTS else CHANNEL_TASKS

        val progressMax = intArg(call, "progressMax")
        val progress = intArg(call, "progress")
        val indeterminate = call.argument<Boolean>("indeterminate") ?: false
        val styledByProgress = call.argument<Boolean>("styledByProgress") ?: true

        val segments = readSegments(call.argument<List<Any?>>("segments"))
        val points = readPoints(call.argument<List<Any?>>("points"))

        val builder = Notification.Builder(ctx, channelId)
            .setSmallIcon(R.drawable.ic_stat_task)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(ongoing)
            .setAutoCancel(autoCancel)
            .setOnlyAlertOnce(alertOnce)
            .setShowWhen(showWhen)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setContentIntent(contentIntent(ctx, id, route))
            .setDeleteIntent(baseIntent(ctx, ACTION_DISMISS, id, null, route))

        if (!subText.isNullOrEmpty()) builder.setSubText(subText)
        if (silent) builder.setSound(null).setVibrate(null)

        // 只有真的要展示进度时才用 ProgressStyle。注意不能写
        // `|| !indeterminate` —— 那条对「没有进度」的通知也恒为 true，结果
        // 通知会莫名挂一条空进度条。
        val hasProgress = segments.isNotEmpty() || points.isNotEmpty() ||
            progressMax > 0 || indeterminate
        val useProgressStyle =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA && hasProgress
        if (useProgressStyle) {
            // 整段包 try/catch：厂商 ROM 可能保留 ProgressStyle 类却缺其中某个
            // 方法（vivo 就缺 setRequestPromotedOngoing），NoSuchMethodError /
            // NoClassDefFoundError 都是 Error，不接就是闪退。
            val styled = try {
                // ProgressStyle 没有 setProgressMax：总长 = 各分段长度之和。
                // 一个分段都没有时补一条整段，颜色用中性灰（底色深浅都看得见）。
                val segs = if (segments.isEmpty()) {
                    listOf(
                        Notification.ProgressStyle.Segment(
                            if (progressMax > 0) progressMax else 100,
                        ).setColor(0xFF8A8F98.toInt()),
                    )
                } else {
                    segments
                }
                val style = Notification.ProgressStyle()
                    .setStyledByProgress(styledByProgress)
                    .setProgress(progress)
                    .setProgressSegments(segs)
                    .setProgressTrackerIcon(
                        Icon.createWithResource(ctx, R.drawable.ic_stat_tracker),
                    )
                if (points.isNotEmpty()) style.setProgressPoints(points)
                if (indeterminate) style.setProgressIndeterminate(true)
                builder.setStyle(style)
                if (promoted && ongoing) requestPromoted(builder)
                true
            } catch (t: Throwable) {
                Log.w(TAG, "ProgressStyle 不可用，回退普通进度条：$t")
                false
            }
            if (!styled) {
                builder.setProgress(progressMax, progress, indeterminate)
                if (!bigText.isNullOrEmpty()) {
                    builder.setStyle(Notification.BigTextStyle().bigText(bigText))
                }
            }
        } else {
            // API 35 及以下：没有 ProgressStyle，退化成普通进度条 + 大段文字
            val max = if (progressMax > 0) progressMax else 0
            builder.setProgress(max, progress, indeterminate)
            if (!bigText.isNullOrEmpty()) {
                builder.setStyle(Notification.BigTextStyle().bigText(bigText))
            }
        }

        for (action in readActions(ctx, call.argument<List<Any?>>("actions"), id, route)) {
            builder.addAction(action)
        }

        val notification = builder.build()
        val nm = manager(ctx)
        if (nm == null) return mapOf("posted" to false, "promoted" to false)
        if (!hasPermission(ctx)) {
            Log.w(TAG, "POST_NOTIFICATIONS not granted, skip id=$id")
            return mapOf("posted" to false, "promoted" to false)
        }
        return try {
            nm.notify(id, notification)
            val actuallyPromoted =
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
                    (notification.flags and Notification.FLAG_PROMOTED_ONGOING) != 0
            if (promoted && !actuallyPromoted) {
                // hasPromotableCharacteristics 同样可能被厂商 ROM 阉掉 → 反射。
                val promotable = try {
                    Notification::class.java
                        .getMethod("hasPromotableCharacteristics")
                        .invoke(notification) as? Boolean
                } catch (t: Throwable) {
                    null
                }
                Log.i(TAG, "not promoted (hasPromotable=$promotable)")
            }
            mapOf("posted" to true, "promoted" to actuallyPromoted)
        } catch (t: Throwable) {
            Log.w(TAG, "notify failed: $t")
            mapOf("posted" to false, "promoted" to false)
        }
    }

    private fun readSegments(raw: List<Any?>?): List<Notification.ProgressStyle.Segment> {
        if (raw == null) return emptyList()
        val out = ArrayList<Notification.ProgressStyle.Segment>()
        for (item in raw) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) break
            if (item !is List<*> || item.isEmpty()) continue
            val length = (item[0] as? Number)?.toInt() ?: continue
            if (length <= 0) continue
            val seg = Notification.ProgressStyle.Segment(length)
            if (item.size > 1) (item[1] as? Number)?.toInt()?.let { seg.setColor(it) }
            out.add(seg)
        }
        return out
    }

    private fun readPoints(raw: List<Any?>?): List<Notification.ProgressStyle.Point> {
        if (raw == null) return emptyList()
        val out = ArrayList<Notification.ProgressStyle.Point>()
        for (item in raw) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) break
            if (item !is List<*> || item.isEmpty()) continue
            val position = (item[0] as? Number)?.toInt() ?: continue
            val point = Notification.ProgressStyle.Point(position)
            if (item.size > 1) (item[1] as? Number)?.toInt()?.let { point.setColor(it) }
            out.add(point)
        }
        return out
    }

    /**
     * 通知上的按钮。`reply=true` 的那条会挂 RemoteInput：用户在通知里直接
     * 打字回车 → 广播 → Dart（不用解锁进 App）。
     */
    private fun readActions(
        ctx: Context,
        raw: List<Any?>?,
        id: Int,
        route: String?,
    ): List<Notification.Action> {
        if (raw == null) return emptyList()
        val out = ArrayList<Notification.Action>()
        for (item in raw) {
            if (item !is Map<*, *>) continue
            val key = item["key"] as? String ?: continue
            val title = item["title"] as? String ?: continue
            val needsReply = item["reply"] == true
            val intent = baseIntent(ctx, ACTION_CLICK, id, key, route)
            if (needsReply) {
                // RemoteInput 没有 placeholder 这个 API（只有 setLabel / setChoices）：
                // 提示文字交给 Dart 侧拼进 title，这里只管标签与自由输入。
                val remoteInput = RemoteInput.Builder(REMOTE_INPUT_KEY)
                    .setLabel(item["replyLabel"] as? String ?: title)
                    .setAllowFreeFormInput(true)
                    .build()
                out.add(
                    Notification.Action.Builder(
                        Icon.createWithResource(ctx, R.drawable.ic_stat_task),
                        title,
                        intent,
                    )
                        .addRemoteInput(remoteInput)
                        .setAllowGeneratedReplies(true)
                        .build(),
                )
            } else {
                out.add(
                    Notification.Action.Builder(
                        Icon.createWithResource(ctx, R.drawable.ic_stat_task),
                        title,
                        intent,
                    ).build(),
                )
            }
        }
        return out
    }

    private fun baseIntent(
        ctx: Context,
        action: String,
        id: Int,
        key: String?,
        route: String?,
    ): PendingIntent {
        val intent = Intent(action).setPackage(ctx.packageName)
            .putExtra(EXTRA_NOTIFY_ID, id)
        if (key != null) intent.putExtra(EXTRA_ACTION_KEY, key)
        if (!route.isNullOrEmpty()) intent.putExtra(EXTRA_ROUTE, route)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        // S+ 必须显式声明可变性；RemoteInput 那条必须是 mutable（系统会往里塞结果）
        flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags or PendingIntent.FLAG_MUTABLE
        } else {
            flags
        }
        return PendingIntent.getBroadcast(ctx, id * 16 + (key?.hashCode() ?: 7), intent, flags)
    }

    private fun contentIntent(ctx: Context, id: Int, route: String?): PendingIntent {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(Intent.ACTION_MAIN).setPackage(ctx.packageName)
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        launch.putExtra(EXTRA_NOTIFY_ID, id)
        if (!route.isNullOrEmpty()) launch.putExtra(EXTRA_ROUTE, route)
        return PendingIntent.getActivity(
            ctx,
            id,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0,
        )
    }

    // ---- 事件回传 ----

    /**
     * 把事件交给 Dart；Dart 没起来（进程被杀后用户点了通知里的回复）就先存起来。
     *
     * `internal` 而不是 `private`：接收器在另一个类里，但它跟本文件同模块。
     */
    internal fun emit(ctx: Context, payload: Map<String, Any?>) {
        val channel = events
        if (channel == null) {
            stash(ctx, payload)
            return
        }
        try {
            channel.invokeMethod(
                "onEvent",
                payload,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(code: String, msg: String?, details: Any?) {
                        Log.w(TAG, "emit failed: $code $msg")
                        stash(ctx, payload)
                    }
                    override fun notImplemented() {
                        stash(ctx, payload)
                    }
                },
            )
        } catch (t: Throwable) {
            Log.w(TAG, "emit failed: $t")
            stash(ctx, payload)
        }
    }

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun stash(ctx: Context, payload: Map<String, Any?>) {
        try {
            val current = prefs(ctx).getString(PREF_PENDING, "[]") ?: "[]"
            val list = org.json.JSONArray(current)
            list.put(org.json.JSONObject(payload))
            while (list.length() > MAX_PENDING) list.remove(0)
            prefs(ctx).edit().putString(PREF_PENDING, list.toString()).apply()
        } catch (t: Throwable) {
            Log.w(TAG, "stash failed: $t")
        }
    }

    private fun drainPending(ctx: Context): List<Map<String, Any?>> {
        val raw = try {
            prefs(ctx).getString(PREF_PENDING, null)
        } catch (t: Throwable) {
            null
        } ?: return emptyList()
        prefs(ctx).edit().remove(PREF_PENDING).apply()
        val out = ArrayList<Map<String, Any?>>()
        try {
            val list = org.json.JSONArray(raw)
            for (i in 0 until list.length()) {
                val item = list.getJSONObject(i)
                val map = HashMap<String, Any?>()
                for (key in item.keys()) {
                    val value = item.get(key)
                    map[key] = if (value === org.json.JSONObject.NULL) null else value
                }
                out.add(map)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "drain failed: $t")
        }
        return out
    }

    // ---- 电池优化 ----

    private fun isIgnoringBatteryOptimizations(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = ctx.getSystemService(PowerManager::class.java) ?: return false
        return try {
            pm.isIgnoringBatteryOptimizations(ctx.packageName)
        } catch (t: Throwable) {
            false
        }
    }

    /**
     * 弹系统的「允许后台运行？」对话框（不需要装任何东西）。
     *
     * 注意：这个 ACTION 在部分 ROM 上会被拦（没有对应 Activity），所以失败时
     * 退回设置页；返回值只表示「有没有把界面弹出去」，不等于用户同意了。
     */
    private fun requestIgnoreBatteryOptimizations(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (isIgnoringBatteryOptimizations(ctx)) return true
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${ctx.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(ctx.packageManager) != null) {
                ctx.startActivity(intent)
                true
            } else {
                safeStartActivity(
                    ctx,
                    Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            }
        } catch (t: Throwable) {
            Log.w(TAG, "requestIgnoreBatteryOptimizations failed: $t")
            safeStartActivity(
                ctx,
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun openNotificationSettings(ctx: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${ctx.packageName}"))
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (!safeStartActivity(ctx, intent)) {
            Log.w(TAG, "cannot open notification settings")
        }
    }

    private fun safeStartActivity(ctx: Context, intent: Intent): Boolean = try {
        if (intent.resolveActivity(ctx.packageManager) != null) {
            if (ctx !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            true
        } else {
            false
        }
    } catch (t: Throwable) {
        Log.w(TAG, "startActivity failed: $t")
        false
    }

    private fun intArg(call: io.flutter.plugin.common.MethodCall, key: String): Int =
        (call.argument<Any>(key) as? Number)?.toInt() ?: 0

    /** 通知按钮 / 回复 / 清除的统一入口（给 [NotificationReceiver] 用）。 */
    internal fun handleBroadcast(context: Context, intent: Intent?) {
        val ctx = context.applicationContext ?: return
        val action = intent?.action ?: return
        val id = intent.getIntExtra(EXTRA_NOTIFY_ID, 0)
        val route = intent.getStringExtra(EXTRA_ROUTE)
        if (action == ACTION_DISMISS) {
            emit(ctx, mapOf("type" to "dismiss", "id" to id, "route" to route))
            return
        }
        val key = intent.getStringExtra(EXTRA_ACTION_KEY)
        val bundle: Bundle? = RemoteInput.getResultsFromIntent(intent)
        val reply = bundle?.getCharSequence(REMOTE_INPUT_KEY)?.toString()?.trim()
        if (!reply.isNullOrEmpty()) {
            // 收完就把那条撤掉：不这么做通知上的输入框会一直转圈
            manager(ctx)?.cancel(id)
        }
        emit(
            ctx,
            mapOf(
                "type" to if (reply.isNullOrEmpty()) "action" else "reply",
                "id" to id,
                "key" to key,
                "text" to reply,
                "route" to route,
            ),
        )
    }
}

/**
 * 通知上的按钮 / 回复 / 清除都落到这里。
 *
 * 静态注册（manifest 里 `exported=false`）：应用进程被杀后用户点通知里的
 * 「回复」，系统会把进程拉起来，这时 Flutter 引擎还没起来 —— 所以事件走
 * [NotificationHost.stash]，等 Dart 侧 `drainPending()` 来取。
 */
class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NotificationHost.handleBroadcast(context, intent)
    }
}
