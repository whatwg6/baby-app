# 宝宝成长时间轴

一款本地优先的宝宝成长记录 App。第一版支持宝宝资料、月龄显示，以及瞬间、成长、日常活动和里程碑四类记录的新增、查看、编辑、筛选与删除；照片和视频保存在 App 私有目录中，并可随本地备份一起导出和恢复。

## 数据与产品范围

- 完全离线：没有账号、服务器上传、云同步、广告或远程分析。数据库和媒体均保存在设备的 App 私有目录。
- 系统相册选择器、文件选择器和分享面板只用于用户主动选择或导出文件，不改变离线数据范围。
- 本产品用于家庭成长记录，不提供医学诊断，也不能替代医生或其他专业医疗建议。

## 环境与安装

需要 Node.js、pnpm，以及 Expo 支持的 iOS 或 Android 原生开发环境。安装依赖：

```bash
pnpm install
npx expo install --check
```

本项目使用 Expo development build。构建并启动对应平台：

```bash
pnpm ios
pnpm android
```

原生 development build 已安装时，可单独启动 Metro：

```bash
pnpm start
```

## 测试与静态构建

```bash
pnpm test -- --coverage
pnpm typecheck
npx expo install --check
npx expo export --platform ios --output-dir dist/ios
npx expo export --platform android --output-dir dist/android
```

`scripts/run-jest.cjs` 仅处理 pnpm 在 `pnpm test -- --coverage` 中保留的首个独立 `--`，其余测试路径、Jest 参数、输出与退出状态均原样传递。

真机验证状态记录在 [`docs/testing/device-smoke-test.md`](docs/testing/device-smoke-test.md)。静态导出成功不等同于真机验收。

## 备份格式与恢复安全

导出的备份是 ZIP 归档，包含：

- `manifest.json`：固定格式标识 `baby-growth-backup`、版本、创建时间、文件大小信息和 SHA-256 完整性摘要。
- `database/app.db`：执行 WAL checkpoint 并关闭连接后取得的一致 SQLite 快照。
- `media/`：数据库实际引用的头像、照片、视频与缩略图。

恢复前会校验归档路径、大小、版本、哈希和 SQLite 完整性。损坏或不兼容的备份不会覆盖现有数据；替换失败会尝试从 rollback 副本恢复。

如果 rollback 也无法安全完成，App 会先在 Documents 中写入独立于 SQLite、WAL 和 SHM 文件集的 recovery sentinel，再进入“本地数据恢复不完整，数据库已保持关闭”的阻塞状态，移除全部 repository 服务且不提供重试按钮。每次启动和重开数据库前都会检查该 sentinel，因此反复启动不能绕过阻塞。此时应保留 App 私有数据并进行受控恢复；只有人工或支持人员确认 SQLite、WAL 和 SHM 已形成一致文件集后，才可以移除 sentinel，不能先删 sentinel 再尝试打开数据库。
