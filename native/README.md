# native/bundle

这里是 `llamadart` 用的预编译运行库（Android arm64/x64、Windows x64，约 208MB），
随 `pubspec.yaml` 的 `hooks.user_defines.llamadart.llamadart_native_path` 一起
被原生构建读取。

**仓库里没有提交这份二进制**（GitHub 仓库保持轻量）。需要用 Android / Windows
原生 TTS 时，二选一：

1. 把已有的 `native/bundle/<平台>/` 从本机备份复制回来；
2. 临时删掉 `pubspec.yaml` 里 `llamadart_native_path` 这一行，让 `llamadart`
   的 build hook 按平台从上游 release 下载。

macOS 不需要这里的产物：`llamadart_llama_cpp_flutter` 在 Apple 平台走 SwiftPM
companion，hook 会忽略 `llamadart_native_path`（见 `third_party/llamadart/hook/build.dart`
的 `_emitAppleSpmAssetsIfEnabled`）。
