# Flutter 真机冒烟清单

验证日期：2026-08-02
验证分支：`feature/baby-growth-timeline-flutter`
自动化 / App code 基线：`6b63de51c760b47d22562eba129f222175538b47`
设备集成命令：`flutter test integration_test/core_flow_test.dart -d all`
设备状态：`No devices found` / `BLOCKED — device unavailable`

本环境没有可用的 iPhone、Android 真机、iOS Simulator 或 Android Emulator。下列结果均为阻塞，未声明通过；App commit 标记为未安装，因为没有设备可安装本次构建。

## iPhone

- 设备型号：N/A — device unavailable
- OS 版本：N/A — device unavailable
- App commit：NOT INSTALLED — device unavailable

1. 首次建立宝宝资料并显示正确月龄：`BLOCKED — device unavailable`
2. 新增四类记录并验证倒序、跨日与跨时区分组：`BLOCKED — device unavailable`
3. 编辑、筛选、删除，强杀 App 后数据仍在：`BLOCKED — device unavailable`
4. 导入一张照片和一个视频，重启后仍可访问：`BLOCKED — device unavailable`
5. 拒绝相册权限、手工移走测试媒体并验证占位、模拟空间不足提示：`BLOCKED — device unavailable`
6. 导出备份，清空数据，再完整恢复：`BLOCKED — device unavailable`
7. 尝试损坏、缺文件和版本 999 的备份，确认原数据保持不变：`BLOCKED — device unavailable`

## Android

- 设备型号：N/A — device unavailable
- OS 版本：N/A — device unavailable
- App commit：NOT INSTALLED — device unavailable

1. 首次建立宝宝资料并显示正确月龄：`BLOCKED — device unavailable`
2. 新增四类记录并验证倒序、跨日与跨时区分组：`BLOCKED — device unavailable`
3. 编辑、筛选、删除，强杀 App 后数据仍在：`BLOCKED — device unavailable`
4. 导入一张照片和一个视频，重启后仍可访问：`BLOCKED — device unavailable`
5. 拒绝相册权限、手工移走测试媒体并验证占位、模拟空间不足提示：`BLOCKED — device unavailable`
6. 导出备份，清空数据，再完整恢复：`BLOCKED — device unavailable`
7. 尝试损坏、缺文件和版本 999 的备份，确认原数据保持不变：`BLOCKED — device unavailable`

## 后续执行要求

获得设备后，在每个平台分别填写真实设备型号、OS 版本和已安装的 App commit，并把每项改为 `PASS` 或带复现信息的 `FAIL`。不得用模拟器结果替代真机记录，也不得把本页的阻塞状态解释为验收通过。
