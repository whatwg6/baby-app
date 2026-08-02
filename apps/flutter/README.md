# 宝宝成长记

一个完全离线的 Flutter 宝宝成长时间轴 App，支持 iPhone 与 Android。第一版面向单个家庭、单个宝宝，提供宝宝资料、四类成长记录（珍贵时刻、成长数据、日常活动、里程碑）、本地媒体、筛选、编辑/删除以及可校验的完整备份与恢复。

## 隐私与产品边界

- App 没有账号、服务端、云同步或网络上传；结构化数据与媒体都保存在设备本地。
- 媒体导入后复制到 App 私有支持目录，数据库只保存私有文件路径。不要把相册临时路径当作长期数据源。
- 本产品只用于家庭记录，不提供医学诊断、异常判断或治疗建议。输入范围校验仅用于防止明显误输。
- 卸载 App 前请主动导出备份；卸载通常会同时删除 App 私有数据。

## 环境要求

- Flutter 3.44.8 或兼容的 stable 版本
- Dart 3.12.2（项目约束为 `^3.12.2`）
- iOS 开发需要当前 Flutter 所支持的 Xcode；Android 开发需要 Android SDK 与可用模拟器或设备

安装依赖并生成代码：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## 启动

先用 `flutter devices` 获取目标 ID，然后运行：

```bash
flutter run -d <ios-device-or-simulator-id>
flutter run -d <android-device-or-emulator-id>
```

启动时会先恢复遗留的备份 rollback、打开并迁移 SQLite，再执行 staging、孤立媒体和过期导出清理。数据库打开或迁移失败时只显示“无法打开本地数据”和“重试”，不会进入业务路由。Flutter 未捕获错误只追加到 App 私有目录下的 `debug/app.log`，没有网络上报。

## 测试与构建

```bash
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --coverage
flutter test integration_test/core_flow_test.dart -d all
flutter build apk --debug
flutter build ios --debug --no-codesign
```

集成测试需要已连接且受项目支持的 iOS Simulator、Android Emulator 或真机；没有设备时 Flutter 会报告 `No devices found`，这不代表测试通过。真机验收状态见 [设备冒烟清单](docs/testing/flutter-device-smoke-test.md)。

## 备份格式

导出文件扩展名为 `.babygrowth.zip`，格式版本为 1。压缩包包含：

- `manifest.json`：格式、版本、创建时间、文件大小与 SHA-256 清单；
- `database/app.db`：关闭并 checkpoint 后的 SQLite 快照；
- `media/originals/`：数据库实际引用的原始媒体；
- `media/thumbnails/`：数据库实际引用的缩略图。

恢复前会限制条目数与大小，拒绝路径穿越、重复/缺失文件、哈希不符、损坏数据库以及不支持的版本。只有完整校验与迁移成功后才替换当前数据；失败时保留原数据。导出的分享文件位于 App 私有目录，启动时会清理超过 24 小时的历史导出。
