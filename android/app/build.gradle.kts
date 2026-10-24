plugins {
    id("com.android.application")
    id("kotlin-android")
    // Compose 编译器插件，版本必须与 settings.gradle.kts 里的 Kotlin 一致
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.memz2345.local2api"
    // 原生底栏的 Compose + backdrop 依赖栈要求 compileSdk 36+（对齐 NaviFlash 用 37）
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    // TTS 导出编码器（libttsexport.so：SILK v3 + LAME MP3，纯 C，自 NaviFlash
    // 移植）。对话模拟的「下载」把朗读音频转成 mp3 / silk / slk 靠它。
    // 随 Flutter 的 ABI 一起构建；不额外锁 abiFilters，release 的 ABI 策略
    // 保持原样。
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        applicationId = "com.memz2345.local2api"
        minSdk = flutter.minSdkVersion
        // 目标 SDK 显式钉 37（不跟 flutter.targetSdkVersion 走，那个还是 36）
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                // 纯 C 工程，不需要 C++ STL
                arguments += listOf("-DANDROID_STL=none")
            }
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 2026.09.00 = Compose 1.12.1：backdrop（液态玻璃库）要求 androidx
    // compose 1.12，Kotlin 2.4.10 配套（与 NaviFlash 相同组合）
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.3")
    // 液态玻璃（Kyant0/AndroidLiquidGlass）：真折射/模糊/高光的 Compose
    // 效果库，原生底栏直接用它的 drawBackdrop
    implementation("io.github.kyant0:backdrop:2.0.1")
    implementation("io.github.kyant0:shapes:1.2.1")

    // ComposeView 宿主（原生底栏/tooltip）需要显式装 ViewTree 生命周期三件套
    // （FlutterActivity 不是 ComponentActivity，视图树上没有）
    // CameraX：扫码（mobile_scanner 底座）用的就是它；探针要枚举 CameraX
    // 侧的可见摄像头（判断厂商隐藏头到底能不能被 CameraX 选中）。版本号与
    // mobile_scanner 7.4.2 解析出的 1.6.1 对齐。
    implementation("androidx.camera:camera-camera2:1.6.1")
    implementation("androidx.camera:camera-lifecycle:1.6.1")
    // 条码解码（与 mobile_scanner 同版本，复用同一份 bundled 模型）
    implementation("com.google.mlkit:barcode-scanning:17.3.0")

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("androidx.savedstate:savedstate-ktx:1.2.1")

    // Shizuku（实验室以 shell 身份拉起 node，绕开 targetSdk 29+ 的 W^X）：
    // api = 客户端 API；provider = 启动时从 Shizuku 管理器拉 binder 的桥；
    // aidl = IShizukuService（Shizuku.newProcess 已私有化，经它直调
    // newProcess 拿 IRemoteProcess）
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
    implementation("dev.rikka.shizuku:aidl:13.1.5")

    // Custom Tabs（内置浏览器的外部打开走 Chromium 系浏览器，TiebaLite 同款）
    implementation("androidx.browser:browser:1.8.0")
}

flutter {
    source = "../.."
}

// ── Flutter 3.44 的坑：release 编译时 GeneratedPluginRegistrant.java 里残留
//    dev 插件（integration_test）→ javac 报「程序包
//    dev.flutter.plugins.integration_test 不存在」。
//
// 成因：`flutter pub get`（以及 IDE 的 pub 同步）按 **debug 口径**重写注册表，
// 把 dev_dependencies 里的 integration_test 也写进去；而 release 的插件列表
// 会过滤 dev 依赖，Gradle 依赖里没有它 → release Java 编译必然找不到这个包。
// （见 flutter_tools 的 packages.dart 里 releaseMode 被写死 false 那段 TODO。）
//
// 这里在 release / profile 的 Java 编译前把这段注册剔掉，让 `flutter build apk`
// 不依赖「上一次是谁写的注册表」，可重复。
fun stripDevOnlyPluginRegistrations() {
    val registrant = file(
        "src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
    )
    if (!registrant.exists()) return
    val text = registrant.readText()
    if (!text.contains("dev.flutter.plugins.integration_test")) return
    val cleaned = text.replace(
        Regex(
            """\n\s*try \{\n\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.[^\n]*\n\s*\} catch \(Exception e\) \{\n\s*Log\.e\(TAG, [^\n]*\n\s*\}""",
        ),
        "",
    )
    registrant.writeText(cleaned)
    logger.lifecycle(
        "GeneratedPluginRegistrant: 已剔除 release 里不存在的 integration_test 注册",
    )
}

tasks.matching {
    it.name == "compileReleaseJavaWithJavac" ||
        it.name == "compileProfileJavaWithJavac"
}.configureEach {
    doFirst { stripDevOnlyPluginRegistrations() }
}

