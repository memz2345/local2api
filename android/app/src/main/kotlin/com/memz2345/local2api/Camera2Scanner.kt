package com.memz2345.local2api

import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera2 直连扫码通道（`com.memz2345.local2api/camera2`）。
 *
 * 为什么不用 mobile_scanner：它走 CameraX，而 CameraX 只枚举
 * `CameraManager.cameraIdList`。vivo / OPPO 一类厂商把超广角等辅助后置镜头
 * 从这张列表里摘掉了（实测：App 侧 cameraIdList 只有 0/1，CameraX
 * availableCameraInfos 同样只有 0/1），但 `getCameraCharacteristics` 读得到、
 * 有 CAMERA 权限时 `openCamera` 也打得开。所以这里**绕过枚举、按 id 直开
 * Camera2**，属于通用做法，不含任何厂商分支。
 *
 * 能力（全部与厂商无关）：
 * - `lenses`：遍历 "0".."9" 取特性（取不到的 id 就是没有），按 35mm 等效
 *   焦距分类（<20mm 广角 / 20–35mm 主摄 / >35mm 长焦），把被藏起来的镜头
 *   一并报出来（带 `listed` 标记）。
 * - `start`：开指定 id，预览走 Flutter 的 SurfaceProducer（Texture），
 *   另起一路 YUV ImageReader 喂 MLKit 解码。
 * - `setZoom` / `torch` / `stop`
 * 事件：`barcode`（value + format）、`error`。
 */
object Camera2Scanner {
    private const val CHANNEL = "com.memz2345.local2api/camera2"

    private var activity: android.app.Activity? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var producer: TextureRegistry.SurfaceProducer? = null
    private var scanner: com.google.mlkit.vision.barcode.BarcodeScanner? = null

    private val busy = AtomicBoolean(false)
    private var activeId: String? = null
    private var zoomRatio = 1f

    fun install(activity: android.app.Activity, engine: FlutterEngine) {
        this.activity = activity
        this.engine = engine
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "lenses" -> result.success(lensesJson())
                    "start" -> start(call.argument("cameraId") ?: "0", result)
                    "setZoom" -> {
                        zoomRatio = (call.argument<Double>("ratio") ?: 1.0).toFloat()
                        log("setZoom -> $zoomRatio")
                        pushZoom()
                        result.success(null)
                    }
                    "torch" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        pushRequest { it.set(CaptureRequest.CONTROL_AE_MODE, CameraMetadata.CONTROL_AE_MODE_ON)
                            it.set(
                                CaptureRequest.FLASH_MODE,
                                if (on) CameraMetadata.FLASH_MODE_TORCH else CameraMetadata.FLASH_MODE_OFF,
                            )
                        }
                        result.success(null)
                    }
                    "stop" -> {
                        stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun dispose() {
        stop()
        channel?.setMethodCallHandler(null)
        channel = null
        engine = null
        activity = null
    }

    // ---- 枚举 ------------------------------------------------------------

    /** 遍历 0..9：不在 cameraIdList 里的镜头也一起报（厂商藏列表不藏能力）。 */
    private fun lensesJson(): String {
        val act = activity
        val cm = act?.getSystemService(CameraManager::class.java)
        val arr = JSONArray()
        if (cm == null) return arr.toString()
        val listed = cm.cameraIdList.toList()
        for (i in 0..9) {
            val id = i.toString()
            try {
                val c = cm.getCameraCharacteristics(id)
                val facing = c.get(CameraCharacteristics.LENS_FACING) ?: -1
                val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                val sensor = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                var eq = -1
                if (focal != null && focal.isNotEmpty() && sensor != null) {
                    val diag = kotlin.math.sqrt(
                        sensor.width * sensor.width + sensor.height * sensor.height,
                    )
                    eq = (focal[0] * 43.27f / diag).toInt()
                }
                val zoom = c.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                val o = JSONObject()
                o.put("id", id)
                o.put("facing", facing)
                o.put("eq35mm", eq)
                o.put("kind", kindOf(facing, eq))
                o.put("zoomMin", zoom?.lower?.toDouble() ?: 1.0)
                o.put("zoomMax", zoom?.upper?.toDouble() ?: 1.0)
                o.put("listed", id in listed)
                o.put("sensorOrientation", c.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val phys = c.physicalCameraIds
                    if (phys.isNotEmpty()) o.put("physicalIds", JSONArray(phys.toList()))
                }
                arr.put(o)
            } catch (_: Exception) {
                // 这个 id 不存在：正常，跳过
            }
        }
        return arr.toString()
    }

    private fun kindOf(facing: Int, eq35mm: Int): String {
        if (facing == CameraCharacteristics.LENS_FACING_FRONT) return "front"
        if (eq35mm <= 0) return "unknown"
        return when {
            eq35mm < 20 -> "wide"
            eq35mm <= 35 -> "normal"
            else -> "zoom"
        }
    }

    // ---- 开流 ------------------------------------------------------------

    private fun start(cameraId: String, result: MethodChannel.Result) {
        val act = activity
        val eng = engine
        if (act == null || eng == null) {
            Handler(android.os.Looper.getMainLooper()).post {
                result.error("no_activity", "activity/engine gone", null)
            }
            return
        }
        val cm = act.getSystemService(CameraManager::class.java)
        stop()
        log("start id=$cameraId")
        val t = HandlerThread("l2a-camera2").apply { start() }
        thread = t
        handler = Handler(t.looper)
        val h = handler!!
        try {
            val chars = cm.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val preview = pickSize(map?.getOutputSizes(Surface::class.java), 1280, 720)
            val analysis = pickSize(map?.getOutputSizes(android.graphics.ImageFormat.YUV_420_888), 1280, 720)
            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val deviceDeg = displayRotationDegrees(act)
            val facing = chars.get(CameraCharacteristics.LENS_FACING) ?: CameraCharacteristics.LENS_FACING_BACK
            val rotation = if (facing == CameraCharacteristics.LENS_FACING_BACK) {
                (sensorOrientation - deviceDeg + 360) % 360
            } else {
                (sensorOrientation + deviceDeg) % 360
            }

            cm.openCamera(
                cameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(c: CameraDevice) {
                        device = c
                        try {
                            // FlutterRenderer 的取纹理/release 都是 @UiThread，
                            // 而这里是 camera 回调线程 —— 必须回主线程拿。
                            val p = createProducer(eng)
                                ?: throw IllegalStateException("no surface producer")
                            p.setSize(preview.width, preview.height)
                            producer = p
                            val r = ImageReader.newInstance(
                                analysis.width,
                                analysis.height,
                                android.graphics.ImageFormat.YUV_420_888,
                                3,
                            )
                            reader = r
                            scanner = BarcodeScanning.getClient()
                            r.setOnImageAvailableListener(
                                { ir ->
                                    var image: Image? = null
                                    try {
                                        image = ir.acquireLatestImage()
                                            ?: return@setOnImageAvailableListener
                                        frames++
                                        if (!busy.compareAndSet(false, true)) return@setOnImageAvailableListener
                                        analyse(image, rotation, ir)
                                    } catch (_: Exception) {
                                        // 单帧失败不影响下一帧
                                    } finally {
                                        runCatching { image?.close() }
                                    }
                                },
                                h,
                            )
                            c.createCaptureSession(
                                listOf(p.surface, r.surface),
                                object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(s: CameraCaptureSession) {
                                        session = s
                                        pushRequest { req ->
                                            req.set(
                                                CaptureRequest.CONTROL_AF_MODE,
                                                CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                                            )
                                            req.set(
                                                CaptureRequest.CONTROL_AE_MODE,
                                                CaptureRequest.CONTROL_AE_MODE_ON,
                                            )
                                        }
                                        act.runOnUiThread {
                                            result.success(
                                                mapOf(
                                                    "textureId" to p.id(),
                                                    "width" to preview.width,
                                                    "height" to preview.height,
                                                    "rotation" to rotation,
                                                    "sensorOrientation" to sensorOrientation,
                                                    "deviceRotation" to deviceDeg,
                                                ),
                                            )
                                        }
                                    }

                                    override fun onConfigureFailed(s: CameraCaptureSession) {
                                        act.runOnUiThread {
                                            result.error("session_failed", "configure failed", null)
                                        }
                                    }
                                },
                                h,
                            )
                            activeId = cameraId
                        } catch (e: Exception) {
                            act.runOnUiThread { result.error("start_failed", "$e", null) }
                        }
                    }

                    override fun onDisconnected(c: CameraDevice) {
                        act.runOnUiThread { result.error("disconnected", "camera disconnected", null) }
                    }

                    override fun onError(c: CameraDevice, error: Int) {
                        act.runOnUiThread { result.error("camera_error", "error=$error", null) }
                    }
                },
                h,
            )
        } catch (e: Exception) {
            // MethodChannel.Result 只能回主线程（自检是从后台线程发起的）。
            act.runOnUiThread { result.error("start_failed", "$e", null) }
        }
    }

    /** 主线程取 SurfaceProducer（已经在主线程就直接调，别把自己锁死）。 */
    private fun createProducer(eng: FlutterEngine): TextureRegistry.SurfaceProducer? {
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
            return eng.renderer.createSurfaceProducer() as TextureRegistry.SurfaceProducer
        }
        var p: TextureRegistry.SurfaceProducer? = null
        val latch = java.util.concurrent.CountDownLatch(1)
        Handler(android.os.Looper.getMainLooper()).post {
            p = runCatching {
                eng.renderer.createSurfaceProducer() as TextureRegistry.SurfaceProducer
            }.getOrNull()
            latch.countDown()
        }
        latch.await(2, java.util.concurrent.TimeUnit.SECONDS)
        return p
    }

    /** 主线程释放 SurfaceProducer。 */
    private fun releaseProducer() {
        val p = producer ?: return
        producer = null
        if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
            runCatching { p.release() }
            return
        }
        Handler(android.os.Looper.getMainLooper()).post { runCatching { p.release() } }
    }

    private fun displayRotationDegrees(act: android.app.Activity): Int {
        val rotation = act.windowManager?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        return when (rotation) {
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    /** 诊断日志：落文件（vivo 过滤三方 logcat），追加写。 */
    private fun log(msg: String) {
        android.util.Log.i("L2ACam2", msg)
        runCatching {
            val f = java.io.File(activity?.getExternalFilesDir(null), "cam2_log.txt")
            f.appendText("${System.currentTimeMillis()} $msg\n")
        }
    }

    /** 在已配置的会话上重发一次重复请求（zoom / 手电 / 启动都走这里）。 */
    private fun pushRequest(apply: (CaptureRequest.Builder) -> Unit) {
        val d = device ?: run { log("push skip: no device"); return }
        val s = session ?: run { log("push skip: no session"); return }
        try {
            val builder = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            builder.addTarget(producer!!.surface)
            builder.addTarget(reader!!.surface)
            apply(builder)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val range = runCatching {
                    (activity?.getSystemService(CameraManager::class.java))
                        ?.getCameraCharacteristics(d.id)
                        ?.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                }.getOrNull()
                val min = range?.lower ?: 1f
                val max = range?.upper ?: 1f
                if (max > min) {
                    val applied = zoomRatio.coerceIn(min, max)
                    builder.set(CaptureRequest.CONTROL_ZOOM_RATIO, applied)
                    log("zoom req=$zoomRatio range=$min..$max applied=$applied id=${d.id}")
                } else {
                    log("zoom SKIPPED req=$zoomRatio range=${range} id=${d.id}")
                }
            } else {
                log("zoom SKIPPED: sdk<30")
            }
            s.setRepeatingRequest(builder.build(), null, handler)
        } catch (e: Exception) {
            // 以前这里全吞掉 —— 变焦没反应时什么都看不到，现在说话。
            log("push FAILED ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun pushZoom() = pushRequest { /* zoom 在 pushRequest 里统一写 */ }

    // ---- 解码 ------------------------------------------------------------

    /** 收到的帧数（自检用：验证会话真的在出帧）。 */
    @Volatile private var frames = 0
    @Volatile private var lastError: String? = null

    /**
     * 自检：后台开「最宽的那颗后置镜头」约 2 秒，把结果落到
     * `cam2_selftest.json`（vivo 过滤三方 logcat，落文件才看得见）。
     * 只在 debug 构建里由 MainActivity 调用。
     */
    fun selfTest(act: android.app.Activity, eng: FlutterEngine) {
        Thread {
            val cm = act.getSystemService(CameraManager::class.java)
            val out = JSONObject()
            try {
                val ids = cm.cameraIdList.toList()
                val candidates = (0..9).mapNotNull { i ->
                    val id = i.toString()
                    runCatching {
                        val c = cm.getCameraCharacteristics(id)
                        val facing = c.get(CameraCharacteristics.LENS_FACING)
                        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                        val sensor = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                        if (facing != CameraCharacteristics.LENS_FACING_BACK) return@runCatching null
                        if (focal == null || sensor == null) return@runCatching null
                        val diag = kotlin.math.sqrt(
                            sensor.width * sensor.width + sensor.height * sensor.height,
                        )
                        id to (focal[0] * 43.27f / diag)
                    }.getOrNull()
                }
                val widest = candidates.minByOrNull { it.second }
                out.put("candidates", JSONArray(candidates.map {
                    JSONObject().put("id", it.first).put("eq35mm", it.second.toInt())
                }))
                val target = widest?.first ?: "0"
                out.put("target", target)
                out.put("listed", target in ids)

                val started = java.util.concurrent.CountDownLatch(1)
                val view = java.util.concurrent.atomic.AtomicReference<Map<String, Any>>(null)
                val startThread = Thread {
                    start(target, object : MethodChannel.Result {
                        override fun success(r: Any?) {
                            if (r is Map<*, *>) {
                                @Suppress("UNCHECKED_CAST")
                                view.set(r as Map<String, Any>)
                            }
                            started.countDown()
                        }
                        override fun error(code: String, msg: String?, details: Any?) {
                            lastError = "$code $msg"
                            started.countDown()
                        }
                        override fun notImplemented() {
                            lastError = "notImplemented"
                            started.countDown()
                        }
                    })
                }
                startThread.isDaemon = true
                startThread.start()
                val ok = started.await(8, java.util.concurrent.TimeUnit.SECONDS)
                out.put("started", ok && view.get() != null)
                out.put("view", view.get()?.toString())
                out.put("error", lastError)
                Thread.sleep(2000)
                out.put("frames", frames)
                stop()
                out.put("afterStopFrames", frames)

                // 静态图解码自检：验证 MLKit 这条链路本身是通的
                // （与相机/旋转无关）。图由 adb push 进外部 files 目录。
                val qr = java.io.File(act.getExternalFilesDir(null), "qr_test.png")
                if (qr.exists()) {
                    val latch = java.util.concurrent.CountDownLatch(1)
                    val found = java.util.concurrent.atomic.AtomicReference<String?>(null)
                    BarcodeScanning.getClient()
                        .process(
                            InputImage.fromFilePath(act, android.net.Uri.fromFile(qr)),
                        )
                        .addOnSuccessListener { list ->
                            found.set(list.firstOrNull()?.rawValue)
                            latch.countDown()
                        }
                        .addOnFailureListener { latch.countDown() }
                    latch.await(5, java.util.concurrent.TimeUnit.SECONDS)
                    out.put("staticDecode", found.get())
                } else {
                    out.put("staticDecode", "no_qr_test_png")
                }
                runCatching {
                    java.io.File(act.getExternalFilesDir(null), "cam2_selftest.json")
                        .writeText(out.toString())
                }
            } catch (e: Exception) {
                out.put("fatal", "$e")
                runCatching {
                    java.io.File(act.getExternalFilesDir(null), "cam2_selftest.json")
                        .writeText(out.toString())
                }
            }
        }.apply { isDaemon = true; start() }
    }

    private fun analyse(image: Image, rotation: Int, reader: ImageReader) {
        val sc = scanner ?: return
        val input = InputImage.fromMediaImage(image, rotation)
        sc.process(input)
            .addOnSuccessListener { barcodes: List<Barcode> ->
                val value = barcodes.firstOrNull { !it.rawValue.isNullOrEmpty() }
                val v = value?.rawValue
                if (v != null) {
                    activity?.runOnUiThread {
                        channel?.invokeMethod(
                            "barcode",
                            mapOf("value" to v, "format" to (value.format)),
                        )
                    }
                }
            }
            .addOnCompleteListener { busy.set(false) }
    }

    // ---- 收摊 ------------------------------------------------------------

    fun stop() {
        activeId = null
        try {
            session?.close()
        } catch (_: Exception) {
        }
        session = null
        try {
            device?.close()
        } catch (_: Exception) {
        }
        device = null
        reader?.close()
        reader = null
        releaseProducer()
        scanner?.close()
        scanner = null
        busy.set(false)
        thread?.quitSafely()
        thread = null
        handler = null
    }

    /** 挑一个接近目标尺寸、且与目标长宽比一致的分辨率。 */
    private fun pickSize(sizes: Array<Size>?, targetW: Int, targetH: Int): Size {
        if (sizes == null || sizes.isEmpty()) return Size(targetW, targetH)
        val targetAspect = targetW.toFloat() / targetH
        return sizes
            .filter { it.width <= 1920 && it.height <= 1920 }
            .minByOrNull {
                kotlin.math.abs(it.width - targetW) + kotlin.math.abs(it.height - targetH) +
                    (kotlin.math.abs(it.width.toFloat() / it.height - targetAspect) * 1000).toInt()
            } ?: sizes[0]
    }
}
