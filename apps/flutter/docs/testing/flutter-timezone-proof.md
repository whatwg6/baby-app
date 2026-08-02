# Flutter 跨时区证明

时间轴按设备本地日历日展示，但 SQLite 与领域模型统一保存 UTC instant。专门的
`test/domain/timezone_proof_test.dart` 使用手工核对的字面期望，不能用被测代码的
`toLocal()` 结果生成 expected。

合并前分别运行：

```bash
TZ=UTC flutter test test/domain/timezone_proof_test.dart
TZ=Asia/Shanghai flutter test test/domain/timezone_proof_test.dart
TZ=America/Los_Angeles flutter test test/domain/timezone_proof_test.dart
```

三条命令分别验证 UTC→本地日期和跨本地午夜分组。Los Angeles 命令还验证真实的
2026-03-08 DST spring-forward 边界：`09:59Z` 为 `01:59 -08:00`，`10:00Z`
直接变为 `03:00 -07:00`。

默认 `flutter test` 若没有显式设置上述任一 `TZ`，该专门 proof 会显示一条带原因的
`SKIP`，其余测试照常运行。这一 fallback 只保持日常全量测试可移植，不能替代三条
独立命令；未知 `TZ` 同样显式 skip，不会静默把当前主机结果冒充三环境证明。
