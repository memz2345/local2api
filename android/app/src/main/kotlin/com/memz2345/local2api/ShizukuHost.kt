package com.memz2345.local2api

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import moe.shizuku.server.IShizukuService
import moe.shizuku.server.IRemoteProcess
import rikka.shizuku.Shizuku

// Shizuku 桥：让实验室在 release（targetSdk 29+，W^X 禁 exec 数据目录）
// 上也能以 shell 身份拉起 node。协议见 lib/services/lab/shizuku_service.dart。
//
// 注意点：
//  · Shizuku.newProcess() 在 api 13.1.5 里已私有化，这里按官方内部实现
//    的同款路径直调 IShizukuService.newProcess（返回 IRemoteProcess，
//    带 waitFor/destroy/输入输出流，语义与 java.lang.Process 一致）；
//  · newProcess() 是同步 binder 调用，放线程池里跑，别卡主线程；
//  · 子进程的 stdout/stderr 必须立刻有人读（不读的话 node 写满 pipe 会
//    整个卡死），EventChannel 没人订阅时先把行缓存进队列，onListen 再
//    flush，避免 dart 侧订阅前的竞态丢行；
//  · IRemoteProcess 不暴露真实 pid，对外一律用 hashCode 当「进程句柄」
//    （dart 侧的 pid 就是这个句柄语义，kill 靠对象引用）。
object ShizukuHost {
    private const val channelName = "com.memz2345.local2api/shizuku"
    private const val requestCode = 9527

    private var channel: MethodChannel? = null
    private var messenger: BinaryMessenger? = null
    private val pool = Executors.newCachedThreadPool()
    private val procs = ConcurrentHashMap<Int, ShizukuProc>()

    // Flutter 平台通道（result / EventSink / invokeMethod）必须在主线程
    // 触达 Dart —— 工作线程直接调会静默丢消息（实测 Dart 端一个事件都
    // 收不到）。所有跨线程回调统一经这里 post 回主线程。
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post(block)
        }
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { code, grant ->
            if (code == requestCode) {
                onMain {
                    channel?.invokeMethod(
                        "permissionResult",
                        grant == PackageManager.PERMISSION_GRANTED,
                    )
                }
            }
        }

    class ShizukuProc(val process: IRemoteProcess) {
        private val lock = Any()
        private val pending = ArrayDeque<Map<String, Any?>>()
        private val sinks = mutableListOf<EventChannel.EventSink>()
        private var closed = false

        fun publish(event: Map<String, Any?>) {
            onMain {
                val deliver: List<EventChannel.EventSink>
                synchronized(lock) {
                    if (closed) return@onMain
                    if (sinks.isEmpty()) {
                        pending.addLast(event)
                        if (pending.size > 1000) pending.removeFirst()
                        return@onMain
                    }
                    deliver = sinks.toList()
                }
                for (sink in deliver) {
                    try {
                        sink.success(event)
                    } catch (_: Exception) {
                    }
                }
            }
        }

        fun attach(sink: EventChannel.EventSink) {
            val backlog: List<Map<String, Any?>>
            synchronized(lock) {
                sinks.add(sink)
                backlog = pending.toList()
                pending.clear()
            }
            for (event in backlog) {
                try {
                    sink.success(event)
                } catch (_: Exception) {
                }
            }
        }

        fun detach(sink: EventChannel.EventSink) {
            synchronized(lock) { sinks.remove(sink) }
        }

        fun close() {
            onMain {
                synchronized(lock) {
                    closed = true
                    for (sink in sinks) {
                        try {
                            sink.endOfStream()
                        } catch (_: Exception) {
                        }
                    }
                    sinks.clear()
                    // pending 必须保留：进程退出（waitFor done）可能先于 Dart
                    // 侧订阅 EventChannel，exit 事件此刻在 pending 里；清掉它
                    // Dart 的 completer 就永远等不到退出信号（20s 超时假死）。
                }
            }
        }
    }

    fun install(activity: Activity, binaryMessenger: BinaryMessenger) {
        messenger = binaryMessenger
        channel = MethodChannel(binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(ping())
                    "permission" -> result.success(granted())
                    "requestPermission" -> {
                        if (granted()) {
                            result.success(true)
                        } else if (!ping()) {
                            result.success(false)
                        } else {
                            Shizuku.removeRequestPermissionResultListener(permissionListener)
                            Shizuku.addRequestPermissionResultListener(permissionListener)
                            Shizuku.requestPermission(requestCode)
                            // 授权框结果异步回推 invokeMethod("permissionResult")。
                            result.success(false)
                        }
                    }
                    "start" -> {
                        val rawCmd: List<*> =
                            call.argument<List<*>>("cmd") ?: emptyList<Any>()
                        val cmd = rawCmd.map { "$it" }
                        val envMap = call.argument<Map<*, *>>("env")
                            ?: emptyMap<Any, Any>()
                        val cwd = call.argument<String>("cwd") ?: ""
                        val env = envMap.entries
                            .map { "${it.key}=${it.value}" }
                            .toTypedArray()
                        pool.execute {
                            try {
                                android.util.Log.i(
                                    "ShizukuHost",
                                    "start: granted=${granted()} cmd=$cmd cwd=$cwd",
                                )
                                if (!granted()) {
                                    result.error(
                                        "not_granted",
                                        "Shizuku permission not granted",
                                        null,
                                    )
                                    return@execute
                                }
                                val service = IShizukuService.Stub.asInterface(
                                    Shizuku.getBinder(),
                                )
                                val remote = service.newProcess(
                                    cmd.toTypedArray(),
                                    env,
                                    cwd.ifEmpty { null },
                                )
                                val handle = remote.hashCode()
                                android.util.Log.i(
                                    "ShizukuHost",
                                    "newProcess ok handle=$handle alive=${remote.alive()}",
                                )
                                val proc = ShizukuProc(remote)
                                procs[handle] = proc
                                onMain {
                                    registerProcChannel(binaryMessenger, handle)
                                }
                                pumpOutput(
                                    handle,
                                    proc,
                                    ParcelFileDescriptor.AutoCloseInputStream(
                                        remote.inputStream,
                                    ),
                                    "out",
                                )
                                pumpOutput(
                                    handle,
                                    proc,
                                    ParcelFileDescriptor.AutoCloseInputStream(
                                        remote.errorStream,
                                    ),
                                    "err",
                                )
                                pool.execute {
                                    val code = try {
                                        val c = remote.waitFor()
                                        android.util.Log.i(
                                            "ShizukuHost",
                                            "waitFor done handle=$handle code=$c",
                                        )
                                        c
                                    } catch (e: InterruptedException) {
                                        android.util.Log.i(
                                            "ShizukuHost",
                                            "waitFor interrupted handle=$handle",
                                        )
                                        -1
                                    }
                                    proc.publish(mapOf("event" to "exit", "code" to code))
                                    proc.close()
                                    // 注意：不从 procs 移除 —— Dart 可能还没
                                    // 订阅 EventChannel，句柄要留着让 onListen
                                    // 能 attach 并拿到缓存的 exit 事件（直到
                                    // Dart kill 或 app 退出统一清理）。
                                }
                                onMain { result.success(handle) }
                            } catch (e: Exception) {
                                result.error("start_failed", e.message, null)
                            }
                        }
                    }
                    "kill" -> {
                        val pid = call.argument<Int>("pid") ?: 0
                        try {
                            procs[pid]?.process?.destroy()
                        } catch (e: Exception) {
                            android.util.Log.i("ShizukuHost", "kill $pid failed: $e")
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun ping(): Boolean = try {
        Shizuku.pingBinder() && Shizuku.getVersion() >= 11
    } catch (_: Throwable) {
        false
    }

    private fun granted(): Boolean = try {
        ping() && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Throwable) {
        false
    }

    private fun registerProcChannel(msg: BinaryMessenger, handle: Int) {
        EventChannel(msg, "com.memz2345.local2api/shizuku/proc/$handle")
            .setStreamHandler(object : EventChannel.StreamHandler {
                private var attached: EventChannel.EventSink? = null

                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    attached = sink
                    procs[handle]?.attach(sink)
                }

                override fun onCancel(arguments: Any?) {
                    attached?.let { procs[handle]?.detach(it) }
                    attached = null
                }
            })
    }

    private fun pumpOutput(
        handle: Int,
        proc: ShizukuProc,
        stream: InputStream,
        name: String,
    ) {
        pool.execute {
            try {
                val reader = BufferedReader(
                    InputStreamReader(stream, Charsets.UTF_8),
                )
                while (true) {
                    val line = reader.readLine() ?: break
                    android.util.Log.i("ShizukuHost", "pump[$name] handle=$handle: $line")
                    proc.publish(mapOf("stream" to name, "line" to line))
                }
                android.util.Log.i("ShizukuHost", "pump[$name] eof handle=$handle")
            } catch (e: Exception) {
                android.util.Log.i("ShizukuHost", "pump[$name] error handle=$handle: $e")
            }
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        messenger = null
        for ((_, proc) in procs) {
            try {
                proc.process.destroy()
            } catch (_: Throwable) {
            }
        }
        procs.clear()
        pool.shutdownNow()
    }
}
