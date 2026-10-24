package com.memz2345.local2api

import android.annotation.SuppressLint
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * 相机镜头探针：把 App 进程里 `CameraManager.cameraIdList` 实际能看到的
 * 摄像头（朝向 / 35mm 等效焦距 / 传感器尺寸 / 变焦范围 / 是否逻辑多摄 /
 * 物理子镜头）全量报给 Dart（channel `com.memz2345.local2api/camera_probe`，
 * method `enumerate`），同时 `Log.i("L2ACamProbe")` 打一份到 logcat。
 *
 * 背景：vivo 等厂商把超广角等辅助后置镜头对普通应用隐藏（API1 只给 2 颗，
 * Camera2 的 cameraIdList 是否也藏要实测），mobile_scanner 的
 * `getSupportedLenses` 因此枚举不到 wide。这里就是给排查/兜底用的通用探针，
 * 不做任何厂商特判。
 */
@SuppressLint("PrivateApi")
object CameraLensProbe {
    private const val TAG = "L2ACamProbe"
    private const val CHANNEL = "com.memz2345.local2api/camera_probe"

    fun install(
        activity: android.app.Activity,
        messenger: BinaryMessenger,
    ) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enumerate" -> result.success(enumerateJson(activity))
                else -> result.notImplemented()
            }
        }
    }

    /** 枚举当前进程可见的所有摄像头，返回 JSON（logcat 与 channel 共用）。 */
    fun enumerateJson(activity: android.app.Activity): String {
        val cm = activity.getSystemService(CameraManager::class.java)
        val root = JSONObject()
        try {
            val ids = cm.cameraIdList
            root.put("visibleIds", JSONArray(ids.toList()))
            val devices = JSONArray()
            for (id in ids) {
                try {
                    devices.put(describe(cm, id))
                } catch (e: Exception) {
                    devices.put(JSONObject().put("id", id).put("error", "$e"))
                }
            }
            root.put("devices", devices)

            // 厂商隐藏探测：cameraIdList 不给 ≠ 完全封死。逐个试
            // "0".."9" 的 getCameraCharacteristics——很多设备「列表藏了、
            // 特性读得到」；能不能 openCamera 是另一关，这里先探特性。
            val hidden = JSONArray()
            for (i in 0..9) {
                val id = i.toString()
                if (id in ids) continue
                try {
                    val info = describe(cm, id)
                    info.put("listed", false)
                    // 决定性一问：不在 cameraIdList 里的头能不能真打开。
                    info.put("open", tryOpen(cm, id))
                    hidden.put(info)
                } catch (e: Exception) {
                    // 读不到特性就是真没有，正常情况，静默跳过。
                }
            }
            root.put("hiddenDevices", hidden)

            // CameraX 视角：mobile_scanner 只能选 CameraX 枚举出来的摄像头。
            // 这里看 availableCameraInfos 里有没有上面那批隐藏头。
            val camerax = JSONObject()
            try {
                        // CameraX 初始化会往主线程 post 任务，主线程上 .get()
                        // 必死锁 —— 丢到后台线程等。
                        val holder = java.util.concurrent.ArrayBlockingQueue<String>(1)
                        Thread {
                            holder.offer(cameraXIds(activity))
                        }.apply { isDaemon = true; start() }
                        val ids = holder.poll(6, java.util.concurrent.TimeUnit.SECONDS)
                        camerax.put("cameraIds", JSONArray(ids.toString().split(",")))
                        camerax.put("raw", ids)
            } catch (e: Exception) {
                camerax.put("error", "$e")
            }
            root.put("cameraX", camerax)
        } catch (e: Exception) {
            root.put("error", "$e")
        }
        return root.toString()
    }

    /** 启动时往 logcat 打一份，不依赖 Dart 侧主动调用。 */
    fun logOnce(activity: android.app.Activity) {
        try {
            val json = enumerateJson(activity)
            // 单条 log 有 4K 上限，按 3900 切。
            var i = 0
            while (i < json.length) {
                val end = minOf(i + 3900, json.length)
                Log.i(TAG, "probe[${i / 3900}]: ${json.substring(i, end)}")
                i = end
            }
            // vivo 等会过滤三方应用 logcat，落一份文件兜底（adb shell cat 可读）。
            runCatching {
                val dir = activity.getExternalFilesDir(null) ?: return
                java.io.File(dir, "cam_probe.json").writeText(json)
            }
        } catch (e: Exception) {
            Log.e(TAG, "probe failed", e)
        }
    }

    /** CameraX 枚举到的摄像头 id 列表（mobile_scanner 只能选这些）。 */
    private fun cameraXIds(activity: android.app.Activity): String {
        return try {
            val provider = androidx.camera.lifecycle.ProcessCameraProvider.getInstance(
                activity.applicationContext,
            ).get(5, java.util.concurrent.TimeUnit.SECONDS)
            provider.availableCameraInfos.joinToString(",") {
                androidx.camera.camera2.interop.Camera2CameraInfo.from(it).cameraId
            }
        } catch (e: Throwable) {
            "ERR:${e.javaClass.simpleName}"
        }
    }

    /**
     * 试着打开一颗摄像头：列表里没有 ≠ 打不开。厂商常见做法是「藏列表
     * 不藏能力」，这里开完立刻关，只留结论（ok / 异常类型 + 消息）。
     */
    private fun tryOpen(cm: CameraManager, id: String): JSONObject {
        val out = JSONObject().put("id", id)
        val thread = android.os.HandlerThread("probe-$id").apply { start() }
        val handler = android.os.Handler(thread.looper)
        val done = java.util.concurrent.Semaphore(0)
        var device: android.hardware.camera2.CameraDevice? = null
        try {
            cm.openCamera(
                id,
                object : android.hardware.camera2.CameraDevice.StateCallback() {
                    override fun onOpened(c: android.hardware.camera2.CameraDevice) {
                        device = c
                        out.put("ok", true)
                        done.release()
                    }

                    override fun onDisconnected(c: android.hardware.camera2.CameraDevice) {
                        out.put("ok", false).put("error", "disconnected")
                        done.release()
                    }

                    override fun onError(
                        c: android.hardware.camera2.CameraDevice,
                        error: Int,
                    ) {
                        out.put("ok", false).put("error", "error=$error")
                        done.release()
                    }
                },
                handler,
            )
            if (!done.tryAcquire(3, java.util.concurrent.TimeUnit.SECONDS)) {
                out.put("ok", false).put("error", "timeout")
            }
        } catch (e: Exception) {
            out.put("ok", false).put("error", "${e.javaClass.simpleName}: ${e.message}")
        } finally {
            runCatching { device?.close() }
            thread.quitSafely()
        }
        return out
    }

    private fun describe(cm: CameraManager, id: String): JSONObject {
        val c = cm.getCameraCharacteristics(id)
        val o = JSONObject()
        o.put("id", id)
        o.put("facing", c.get(CameraCharacteristics.LENS_FACING) ?: -1)
        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
        if (focal != null) o.put("focalLengths", JSONArray(focal.toList()))
        val sensor = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
        if (sensor != null) {
            o.put("sensorWidthMm", sensor.width.toDouble())
            o.put("sensorHeightMm", sensor.height.toDouble())
            // 35mm 等效焦距（对角线 43.27mm），与 mobile_scanner 同一套算法
            val diag = kotlin.math.sqrt(
                sensor.width * sensor.width + sensor.height * sensor.height,
            ).toDouble()
            if (focal != null && focal.isNotEmpty()) {
                o.put("eq35mm", (focal[0] * 43.27f / diag).toInt())
            }
        }
        val zoom = c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
        if (zoom != null) {
            o.put("zoomMin", zoom.lower.toDouble())
            o.put("zoomMax", zoom.upper.toDouble())
        }
        val caps = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
        if (caps != null) {
            // 1 = LOGICAL_MULTI_CAMERA
            o.put("logicalMultiCamera", caps.contains(1))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val phys = c.physicalCameraIds
            if (phys.isNotEmpty()) o.put("physicalIds", JSONArray(phys.toList()))
        }
        val minFocus = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE)
        if (minFocus != null) o.put("minFocusDistance", minFocus.toDouble())
        return o
    }
}
