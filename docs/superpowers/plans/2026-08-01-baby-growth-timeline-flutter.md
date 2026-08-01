# 宝宝成长时间轴 App（Flutter）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 Flutter 构建一个完全离线、同时支持 iPhone 和 Android 的宝宝成长记录 App，以统一时间轴呈现珍贵时刻、成长数据、日常活动和里程碑，并支持可校验的本地完整备份与安全恢复。

**Architecture:** 使用 go_router 组织首次资料、底部导航和记录详情路由，Riverpod 只负责依赖注入与页面状态；领域规则保持为纯 Dart。结构化数据由 sqflite repository 管理，媒体由文件服务复制到 App 私有目录，记录保存协调器负责 SQLite 事务与媒体补偿；备份服务在数据库关闭后生成一致快照，并通过临时目录、完整性校验和 rollback 目录完成恢复。

**Tech Stack:** Flutter stable、Dart 3、Material 3、flutter_riverpod、go_router、sqflite、sqflite_common_ffi、path_provider、path、uuid、image_picker、file_picker、share_plus、crypto、archive、flutter_image_compress、video_thumbnail、intl、freezed_annotation、json_annotation、build_runner、freezed、json_serializable、mocktail、flutter_test、integration_test。

## Global Constraints

- 第一版完全单机，无服务端、账号、云同步或联网依赖。
- 只支持一个宝宝；姓名和生日必填，头像和性别可选。
- 使用一套 Flutter/Dart 代码支持 iPhone 和 Android。
- 所有记录进入统一时间轴，并按发生时间倒序排列。
- 支持珍贵时刻、成长数据、日常活动和里程碑四类记录。
- 媒体必须复制到 App 私有目录，不能长期引用系统相册返回的临时路径。
- 备份恢复失败时不得改动当前数据。
- App 不提供医学诊断、成长异常判断或医疗建议。
- 日期分组使用设备本地时区，数据库时间统一保存为 UTC ISO 8601 字符串。
- 每个实现任务必须先运行目标测试并看到失败，再写最小实现并看到测试通过。
- 原生 iOS deployment target 固定为 13.0；Android minSdk 固定为 23。

## File Map

- `pubspec.yaml`：Flutter、运行时依赖、测试依赖及静态资源声明。
- `lib/main.dart`：初始化 Flutter binding、依赖容器与根 App。
- `lib/app/app.dart`：MaterialApp.router、主题和全局错误页。
- `lib/app/router.dart`：首次资料、三个 tab、记录新增/详情/编辑路由。
- `lib/app/providers.dart`：稳定服务接口的 Riverpod providers。
- `lib/app/bootstrap.dart`：目录、数据库、迁移与孤立媒体清理的启动编排。
- `lib/core/theme/app_theme.dart`：奶油白、柔和暖色、圆角和留白规范。
- `lib/core/errors/app_exception.dart`：可展示错误的稳定分类。
- `lib/domain/models/`：Baby、TimelineRecord、Attachment、四类详情与草稿类型。
- `lib/domain/validation/`：宝宝资料和四类记录的纯 Dart 校验。
- `lib/domain/date/`：月龄、本地日期键和时间轴分组。
- `lib/data/database/`：sqflite 打开、迁移、事务和关闭后操作。
- `lib/data/repositories/`：BabyRepository、RecordRepository 接口与 SQLite 实现。
- `lib/features/baby/`：首次资料、资料编辑、头像和月龄头部。
- `lib/features/timeline/`：列表状态、筛选、日期分组和卡片。
- `lib/features/records/`：类型选择、四类表单、详情、编辑和删除。
- `lib/features/media/`：选择器、私有文件存储、缩略图与孤立文件清理。
- `lib/features/backup/`：版本化清单、导出、检查与原子恢复。
- `test/`：纯 Dart、widget、repository contract 与服务单元测试。
- `integration_test/`：设备数据库、文件系统和核心流程集成测试。
- `docs/testing/flutter-device-smoke-test.md`：iPhone 与 Android 真机验收记录。

---

### Task 1: Flutter 工程骨架、主题与可测试导航壳

**Files:**
- Create: `pubspec.yaml`
- Create: `analysis_options.yaml`
- Create: `lib/main.dart`
- Create: `lib/app/app.dart`
- Create: `lib/app/router.dart`
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/features/timeline/presentation/timeline_page.dart`
- Create: `lib/features/records/presentation/add_record_page.dart`
- Create: `lib/features/baby/presentation/baby_page.dart`
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Podfile`
- Modify: `android/app/build.gradle.kts`
- Test: `test/app/app_shell_test.dart`

**Interfaces:**
- Produces: `BabyTimelineApp({required GoRouter router})`、`createRouter()`、`AppTheme.light`。
- Consumes: 无。

- [ ] **Step 1: 创建 Flutter 工程并声明依赖**

Run:

```bash
flutter create --platforms=ios,android --org com.local --project-name baby_growth_timeline .
flutter pub add flutter_riverpod go_router sqflite path_provider path uuid image_picker file_picker share_plus crypto archive flutter_image_compress video_thumbnail intl freezed_annotation json_annotation
flutter pub add --dev build_runner freezed json_serializable mocktail sqflite_common_ffi
```

Expected: `flutter pub get` 成功；`ios/Podfile` 将 `platform :ios` 设为 `13.0`，`android/app/build.gradle.kts` 将 `minSdk` 设为 `23`。在 `ios/Runner/Info.plist` 写入 `NSPhotoLibraryUsageDescription`，文案为“选择宝宝照片和视频用于本地成长记录”；Android 使用系统 Photo Picker，不申请广泛媒体读取权限。

- [ ] **Step 2: 写导航壳失败测试**

```dart
testWidgets('shows three destinations and empty timeline', (tester) async {
  await tester.pumpWidget(BabyTimelineApp(router: createRouter(hasBaby: true)));
  await tester.pumpAndSettle();

  expect(find.text('时间轴'), findsOneWidget);
  expect(find.text('添加'), findsOneWidget);
  expect(find.text('宝宝'), findsOneWidget);
  expect(find.text('还没有成长记录'), findsOneWidget);
  expect(find.text('记录第一个瞬间'), findsOneWidget);
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/app/app_shell_test.dart`

Expected: FAIL，原因是 `BabyTimelineApp`、`createRouter` 或页面尚不存在。

- [ ] **Step 4: 实现主题、ShellRoute 与三个页面壳**

`AppTheme.light` 使用 Material 3，固定颜色：背景 `#FFF9F3`、卡片 `#FFFFFF`、主文字 `#352F2B`、次文字 `#857B73`、主强调 `#E58F78`、边框 `#EDE2D8`、危险色 `#B94747`；卡片圆角 20，页面水平间距 16。`StatefulShellRoute.indexedStack` 提供“时间轴 / 添加 / 宝宝”三个目的地，中央“添加”使用强调色图标。

- [ ] **Step 5: 验证测试、静态分析和双平台构建配置**

Run: `dart format --set-exit-if-changed lib test && flutter analyze && flutter test test/app/app_shell_test.dart`

Expected: 格式、分析和测试全部通过。

- [ ] **Step 6: 提交工程骨架**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml lib test ios android
git commit -m "feat(flutter): scaffold baby timeline app"
```

---

### Task 2: 领域模型、输入校验与日期规则

**Files:**
- Create: `lib/domain/models/baby.dart`
- Create: `lib/domain/models/attachment.dart`
- Create: `lib/domain/models/timeline_record.dart`
- Create: `lib/domain/models/record_draft.dart`
- Create: `lib/domain/validation/baby_validator.dart`
- Create: `lib/domain/validation/record_validator.dart`
- Create: `lib/domain/date/age_label.dart`
- Create: `lib/domain/date/timeline_grouping.dart`
- Create: `lib/core/errors/app_exception.dart`
- Test: `test/domain/validation_test.dart`
- Test: `test/domain/date_rules_test.dart`

**Interfaces:**
- Produces: `Baby`、`TimelineRecord`、`RecordDraft`、`RecordType`、`validateBabyDraft()`、`validateRecordDraft()`、`calculateAgeLabel()`、`groupRecordsByLocalDay()`。
- Consumes: intl、freezed_annotation、json_annotation。

- [ ] **Step 1: 写领域行为失败测试**

```dart
test('rejects future birthday and empty growth record', () {
  expect(
    () => validateBabyDraft(
      const BabyDraft(name: '安安', birthDate: '2099-01-01'),
      now: DateTime(2026, 8, 1),
    ),
    throwsA(isA<ValidationException>()),
  );
  expect(
    () => validateRecordDraft(RecordDraft.growth(occurredAt: DateTime(2026, 8, 1))),
    throwsA(isA<ValidationException>()),
  );
});

test('calculates age and groups newest local day first', () {
  expect(calculateAgeLabel(DateTime(2025, 6, 15), DateTime(2026, 8, 1)), '1岁1个月');
  expect(groupRecordsByLocalDay(records).map((group) => group.key), ['2026-08-01', '2026-07-31']);
});
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/domain`

Expected: FAIL，领域模块尚不存在。

- [ ] **Step 3: 定义不可变领域模型并生成代码**

```dart
enum RecordType { moment, growth, activity, milestone }
enum ActivityType { feeding, sleep, diaper }
enum MediaType { image, video }

@freezed
sealed class RecordDetails with _$RecordDetails {
  const factory RecordDetails.growth({double? heightCm, double? weightKg, double? headCm}) = GrowthDetails;
  const factory RecordDetails.activity({required ActivityType activityType, double? amount, int? durationMinutes}) = ActivityDetails;
  const factory RecordDetails.milestone({required String title, String? presetKey}) = MilestoneDetails;
}

@freezed
class BabyDraft with _$BabyDraft {
  const factory BabyDraft({
    required String name,
    required String birthDate,
    String? sex,
    String? avatarPath,
  }) = _BabyDraft;
}

@freezed
class RecordDraft with _$RecordDraft {
  const factory RecordDraft({
    required RecordType type,
    required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    @Default([]) List<RecordDraftAttachment> attachments,
  }) = _RecordDraft;
}

@freezed
sealed class RecordDraftAttachment with _$RecordDraftAttachment {
  const factory RecordDraftAttachment.picked({
    required String sourcePath,
    required MediaType mediaType,
  }) = PickedAttachment;
  const factory RecordDraftAttachment.existing({
    required String id,
    required MediaType mediaType,
    required String filePath,
    String? thumbnailPath,
  }) = ExistingAttachment;
}

@freezed
class NewAttachmentInput with _$NewAttachmentInput {
  const factory NewAttachmentInput({
    String? id,
    required MediaType mediaType,
    required String filePath,
    String? thumbnailPath,
  }) = _NewAttachmentInput;
}

@freezed
class NewRecordInput with _$NewRecordInput {
  const factory NewRecordInput({
    required RecordType type,
    required DateTime occurredAt,
    String? note,
    RecordDetails? details,
    @Default([]) List<NewAttachmentInput> attachments,
  }) = _NewRecordInput;
}
```

`TimelineRecord.occurredAt` 在领域层使用 `DateTime` UTC 值；界面展示和分组前调用 `toLocal()`。`RecordDraftAttachment` 用 sealed union 区分 `PickedAttachment(sourcePath, mediaType)` 与 `ExistingAttachment(id, filePath, thumbnailPath, mediaType)`。

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: 实现明确的校验边界**

宝宝姓名 trim 后不能为空，生日格式必须为 `yyyy-MM-dd` 且不得晚于本地今天。珍贵时刻要求文字或媒体至少一项；成长数据至少填写一项，身高 `20–250 cm`、体重 `0.2–300 kg`、头围 `10–100 cm`；活动类型必填，数量大于 0，时长为 `1–1440` 分钟；里程碑标题 trim 后不能为空。这些范围只拦截明显误输，错误文案不得暗示医疗结论。

- [ ] **Step 5: 实现月龄与跨时区日期分组**

`calculateAgeLabel()` 按自然年月计算，当前日小于出生日时借一个月；不足一月显示天数。`localDayKey(DateTime utc)` 先 `toLocal()` 再生成 `yyyy-MM-dd`；`groupRecordsByLocalDay()` 必须先按 UTC 发生时间倒序，再保持组内顺序。

- [ ] **Step 6: 运行生成、测试和分析**

Run: `dart run build_runner build --delete-conflicting-outputs && dart format lib test && flutter test test/domain && flutter analyze`

Expected: 生成无冲突，领域测试全部通过，静态分析无错误。

- [ ] **Step 7: 提交领域层**

```bash
git add lib/domain lib/core/errors test/domain
git commit -m "feat(flutter): define timeline domain rules"
```

---

### Task 3: SQLite 迁移、数据库生命周期与 Repository 合约

**Files:**
- Create: `lib/data/database/app_database.dart`
- Create: `lib/data/database/migrations.dart`
- Create: `lib/data/database/database_lifecycle.dart`
- Create: `lib/data/repositories/baby_repository.dart`
- Create: `lib/data/repositories/record_repository.dart`
- Create: `lib/data/repositories/sqlite_baby_repository.dart`
- Create: `lib/data/repositories/sqlite_record_repository.dart`
- Create: `test/support/repository_contract.dart`
- Create: `test/support/fixtures.dart`
- Test: `test/data/migrations_test.dart`
- Test: `test/data/sqlite_repository_test.dart`

**Interfaces:**
- Produces: `AppDatabase.open()`、`DatabaseLifecycle.withClosedDatabase()`、`BabyRepository`、`RecordRepository`、`RecordTransaction`。
- Consumes: Task 2 的领域模型、sqflite、sqflite_common_ffi。

- [ ] **Step 1: 写迁移和 repository 合约失败测试**

```dart
void recordRepositoryContract(Future<RecordRepository> Function() create) {
  test('creates, lists, updates and deletes a complete record', () async {
    final repository = await create();
    final created = await repository.create(momentInputFixture());
    expect((await repository.list()).single.id, created.id);
    await repository.update(created.id, momentInputFixture(note: '修改后'));
    expect((await repository.get(created.id))?.note, '修改后');
    final removed = await repository.delete(created.id);
    expect(removed, isNotEmpty);
    expect(await repository.get(created.id), isNull);
  });
}
```

迁移测试断言 `PRAGMA user_version = 1`、六张表存在、外键启用、详情表 `record_id` 唯一且删除主记录会级联删除详情与附件索引。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/data`

Expected: FAIL，数据库与 repository 尚不存在。

- [ ] **Step 3: 建立版本 1 schema**

创建 `baby`、`records`、`growth_details`、`activity_details`、`milestone_details`、`attachments`。`records.type` 与详情表类型由 repository 校验；所有主键使用 UUID 文本；时间保存 UTC ISO 8601；`records.occurred_at DESC` 建索引；详情和附件外键使用 `ON DELETE CASCADE`。

- [ ] **Step 4: 定义 repository 与数据库生命周期接口**

```dart
abstract interface class RecordTransaction {
  Future<TimelineRecord> create(NewRecordInput input);
  Future<TimelineRecord> update(String id, NewRecordInput input);
  Future<List<Attachment>> delete(String id);
}

abstract interface class RecordRepository implements RecordTransaction {
  Future<List<TimelineRecord>> list({Set<RecordType> types = const {}});
  Future<TimelineRecord?> get(String id);
  Future<T> inTransaction<T>(Future<T> Function(RecordTransaction tx) work);
}

abstract interface class DatabaseLifecycle {
  Future<T> withClosedDatabase<T>(Future<T> Function(String databasePath) work);
  Future<void> reopen();
}
```

- [ ] **Step 5: 实现 SQLite 映射和非嵌套事务**

公开 `create/update/delete` 各自包一层 `inTransaction()`；传给回调的 transaction adapter 直接使用当前 `Transaction`，避免嵌套。更新记录时按输入重建对应详情并同步附件索引；删除先读取附件列表再删主记录。UI 不得接触 SQL row 或 Database 对象。

`withClosedDatabase()` 顺序固定为 `PRAGMA wal_checkpoint(TRUNCATE)` → close → 执行回调 → finally reopen 并运行迁移；即使回调失败也必须尝试恢复连接。

- [ ] **Step 6: 运行 repository 合约、分析与格式检查**

Run: `dart format lib test && flutter test test/data && flutter analyze`

Expected: 迁移、CRUD、筛选、级联删除和事务回滚测试全部通过。

- [ ] **Step 7: 提交数据层**

```bash
git add lib/data test/data test/support
git commit -m "feat(flutter): add sqlite repositories"
```

---

### Task 4: 宝宝资料建立、编辑与月龄头部

**Files:**
- Create: `lib/features/baby/application/baby_controller.dart`
- Create: `lib/features/baby/presentation/baby_setup_page.dart`
- Create: `lib/features/baby/presentation/baby_form.dart`
- Create: `lib/features/baby/presentation/baby_header.dart`
- Modify: `lib/features/baby/presentation/baby_page.dart`
- Modify: `lib/app/router.dart`
- Test: `test/features/baby/baby_form_test.dart`
- Test: `test/features/baby/baby_header_test.dart`

**Interfaces:**
- Produces: `BabyController`、`BabyForm({Baby? initialValue, required Future<void> Function(BabyDraft) onSave})`、`BabyHeader`。
- Consumes: `BabyRepository`、`validateBabyDraft()`、`calculateAgeLabel()`。

- [ ] **Step 1: 写资料与月龄 widget 失败测试**

```dart
await tester.enterText(find.byKey(const Key('baby-name')), '安安');
await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
await tester.tap(find.text('保存'));
await tester.pump();
verify(() => onSave(const BabyDraft(name: '安安', birthDate: '2025-06-15'))).called(1);
expect(find.text('1岁1个月'), findsOneWidget);
```

补充测试空姓名、未来生日、编辑回填和保存失败后保留输入。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/baby`

Expected: FAIL，资料组件和 controller 不存在。

- [ ] **Step 3: 实现 BabyController 与表单**

`BabyController` 暴露 `AsyncValue<Baby?>`、`load()`、`save(BabyDraft)`、`reload()`；表单字段错误显示在对应输入下，保存中禁用提交。生日使用 date picker，测试仍可通过 controller 注入固定日期。

- [ ] **Step 4: 接通首次路由和宝宝页**

启动完成且 repository 无宝宝时重定向 `/baby/setup`；资料保存后进入 `/timeline`。已有资料时禁止再次创建第二个宝宝，只能在“宝宝”页编辑。头部展示头像占位、姓名和实时计算的月龄。

- [ ] **Step 5: 运行测试和静态分析**

Run: `dart format lib test && flutter test test/features/baby && flutter analyze`

Expected: 所有资料与月龄测试通过。

- [ ] **Step 6: 提交宝宝资料功能**

```bash
git add lib/features/baby lib/app/router.dart test/features/baby
git commit -m "feat(flutter): add baby profile flow"
```

---

### Task 5: 统一时间轴、筛选与记录详情

**Files:**
- Create: `lib/features/timeline/application/timeline_controller.dart`
- Create: `lib/features/timeline/presentation/timeline_filters.dart`
- Create: `lib/features/timeline/presentation/timeline_card.dart`
- Create: `lib/features/timeline/presentation/timeline_section.dart`
- Modify: `lib/features/timeline/presentation/timeline_page.dart`
- Create: `lib/features/records/presentation/record_detail_page.dart`
- Modify: `lib/app/router.dart`
- Test: `test/features/timeline/timeline_page_test.dart`
- Test: `test/features/records/record_detail_test.dart`

**Interfaces:**
- Produces: `TimelineController`、`TimelineFilters`、`TimelineCard`、`RecordDetailPage(recordId)`。
- Consumes: `RecordRepository.list()`、`groupRecordsByLocalDay()`、`BabyHeader`。

- [ ] **Step 1: 写时间轴和详情失败测试**

使用 fake repository 放入照片时刻、成长数据和睡眠记录，断言“今天/昨天/具体日期”分组、发生时间倒序、类型筛选、清除筛选、卡片摘要和空状态。详情测试断言成长值带 `cm/kg` 单位，文件缺失时显示“媒体文件不可用”。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/timeline test/features/records/record_detail_test.dart`

Expected: FAIL，controller、卡片或详情页面不存在。

- [ ] **Step 3: 实现 TimelineController**

```dart
@freezed
class TimelineState with _$TimelineState {
  const factory TimelineState({
    @Default([]) List<TimelineRecord> records,
    @Default({}) Set<RecordType> selectedTypes,
    @Default(false) bool isLoading,
    String? errorMessage,
  }) = _TimelineState;
}
```

空筛选集合表示全部类型。刷新失败时保留现有 records 并显示“无法读取记录，请重试”；新增、编辑、删除完成后调用 `reload()`。

- [ ] **Step 4: 实现视觉分层和详情路由**

珍贵时刻使用大图卡片；成长、活动使用紧凑卡片；里程碑使用标题优先卡片。每张卡显示本地发生时间、类型图标和摘要。`/records/:id` 查不到记录显示“记录不存在”，异常时提供重试，正常时提供编辑和删除入口。

- [ ] **Step 5: 运行 widget 测试、golden 基线和分析**

为 390×844 逻辑像素生成 `test/goldens/timeline_mixed.png`，固定字体缩放 1.0；golden 只验证卡片层级和留白，不比较动态图片内容。

Run: `flutter test test/features/timeline test/features/records/record_detail_test.dart && flutter analyze`

Expected: 列表、筛选、详情和 golden 测试通过。

- [ ] **Step 6: 提交时间轴功能**

```bash
git add lib/features/timeline lib/features/records/presentation/record_detail_page.dart lib/app/router.dart test/features/timeline test/features/records test/goldens
git commit -m "feat(flutter): render unified growth timeline"
```

---

### Task 6: 四类记录创建与编辑

**Files:**
- Create: `lib/features/records/application/record_editor_controller.dart`
- Create: `lib/features/records/presentation/record_type_picker.dart`
- Create: `lib/features/records/presentation/record_editor_page.dart`
- Create: `lib/features/records/presentation/forms/moment_fields.dart`
- Create: `lib/features/records/presentation/forms/growth_fields.dart`
- Create: `lib/features/records/presentation/forms/activity_fields.dart`
- Create: `lib/features/records/presentation/forms/milestone_fields.dart`
- Modify: `lib/features/records/presentation/add_record_page.dart`
- Modify: `lib/app/router.dart`
- Test: `test/features/records/record_editor_test.dart`

**Interfaces:**
- Produces: `RecordTypePicker`、`RecordEditorPage({required RecordType type, String? recordId})`、`RecordEditorController.submit()`。
- Consumes: `validateRecordDraft()`；Task 7 的媒体保存协调器接入前，仅允许无新媒体的记录保存。

- [ ] **Step 1: 写四类表单失败测试**

分别验证：空珍贵时刻不能保存；成长数据接受单个合法值并拒绝负数；活动类型必填并拒绝 0 分钟；里程碑标题必填；发生时间默认为注入的当前时间且可修改；编辑时完整回填原值。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/records/record_editor_test.dart`

Expected: FAIL，编辑器与分类型字段不存在。

- [ ] **Step 3: 实现记录类型选择与分类型字段**

选择器固定输出四种 `RecordType`。共同表单拥有发生时间、备注和附件列表；四个 fields widget 只修改对应 `RecordDetails`。数值输入使用 decimal keyboard，但最终仍由 Task 2 validator 校验，不依赖键盘限制保证正确性。

- [ ] **Step 4: 接通新增、编辑与失败状态**

新增成功 `context.go('/timeline')`；编辑成功 `context.pop(true)` 并触发详情与时间轴刷新。提交期间禁用保存，repository 异常显示“保存失败，已有数据未受影响”，同时保留全部表单状态。

- [ ] **Step 5: 运行记录测试和分析**

Run: `dart format lib test && flutter test test/features/records/record_editor_test.dart && flutter analyze`

Expected: 四类记录新增与编辑 widget 测试全部通过。

- [ ] **Step 6: 提交记录编辑功能**

```bash
git add lib/features/records lib/app/router.dart test/features/records/record_editor_test.dart
git commit -m "feat(flutter): create and edit timeline records"
```

---

### Task 7: 媒体导入、私有存储与事务补偿

**Files:**
- Create: `lib/features/media/domain/media_service.dart`
- Create: `lib/features/media/data/local_media_service.dart`
- Create: `lib/features/media/application/save_record_with_media.dart`
- Create: `lib/features/media/presentation/media_picker.dart`
- Create: `lib/features/media/presentation/media_preview.dart`
- Modify: `lib/features/records/application/record_editor_controller.dart`
- Modify: `lib/features/records/presentation/forms/moment_fields.dart`
- Modify: `lib/features/records/presentation/forms/milestone_fields.dart`
- Modify: `lib/features/baby/presentation/baby_form.dart`
- Test: `test/features/media/local_media_service_test.dart`
- Test: `test/features/media/save_record_with_media_test.dart`
- Test: `test/features/media/media_picker_test.dart`

**Interfaces:**
- Produces: `MediaService.stage()`、`commit()`、`rollback()`、`remove()`、`removeOrphans()`、`saveRecordWithMedia()`。
- Consumes: image_picker、path_provider、flutter_image_compress、video_thumbnail、uuid、`RecordRepository.inTransaction()`。

- [ ] **Step 1: 写媒体生命周期与补偿失败测试**

```dart
final staged = await service.stage(
  const PickedMedia(sourcePath: '/picker/a.jpg', mediaType: MediaType.image),
);
expect(staged.stagingPath, contains('/staging/'));
final committed = await service.commit(staged);
expect(committed.filePath, contains('/media/'));
await service.rollback(staged);
verify(() => fileSystem.delete(any())).called(greaterThanOrEqualTo(1));
```

补充测试：不支持扩展名、复制时空间不足、媒体 commit 失败回滚 SQLite、SQLite commit 失败删除新文件、更新时保留 existing 附件、`removeOrphans()` 只删除未引用文件。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/media`

Expected: FAIL，媒体服务与保存协调器不存在。

- [ ] **Step 3: 实现 staging、正式落盘和缩略图**

```dart
abstract interface class MediaService {
  Future<StagedMedia> stage(PickedMedia input);
  Future<CommittedMedia> commit(StagedMedia staged);
  Future<void> rollback(StagedMedia staged);
  Future<void> remove(Iterable<String> paths);
  Future<void> removeOrphans(Set<String> referencedPaths);
}

class PickedMedia {
  const PickedMedia({required this.sourcePath, required this.mediaType});
  final String sourcePath;
  final MediaType mediaType;
}

class StagedMedia {
  const StagedMedia({
    required this.stagingPath,
    required this.finalPath,
    required this.mediaType,
    this.thumbnailStagingPath,
    this.thumbnailFinalPath,
  });
  final String stagingPath;
  final String finalPath;
  final MediaType mediaType;
  final String? thumbnailStagingPath;
  final String? thumbnailFinalPath;
}

class CommittedMedia {
  const CommittedMedia({required this.filePath, this.thumbnailPath});
  final String filePath;
  final String? thumbnailPath;
}
```

只允许 `jpg/jpeg/png/heic/webp/mp4/mov`；文件名使用 UUID 并保留规范化扩展名。图片生成最长边 1200px 的 JPEG 缩略图，视频使用 `video_thumbnail` 生成首帧。所有文件只存放在 application support 下的 `staging/`、`media/originals/`、`media/thumbnails/`。

- [ ] **Step 4: 实现记录保存的事务与文件补偿**

`saveRecordWithMedia()` 固定执行：stage 新媒体 → 进入 `RecordRepository.inTransaction()` → 用预定 final path 写记录及附件索引 → commit 所有媒体 → transaction callback 返回并提交数据库。stage/commit 失败则回滚 transaction 并清理 staging；数据库最终 commit 失败则删除本次已移入正式目录的文件。编辑删除的旧附件只在数据库提交成功后清理。

- [ ] **Step 5: 接通选择器、预览和宝宝头像**

相册权限拒绝显示“请在系统设置中允许访问照片”；用户取消不显示错误。珍贵时刻允许图片或视频，里程碑和头像只允许图片。头像替换也使用 stage/commit/rollback，成功保存新路径后再删除旧头像。媒体文件缺失或解码失败时显示“媒体文件不可用”占位，页面不得抛异常。

- [ ] **Step 6: 运行媒体、记录回归和分析**

Run: `dart format lib test && flutter test test/features/media test/features/records && flutter analyze`

Expected: 媒体生命周期、补偿、选择器和记录回归测试全部通过。

- [ ] **Step 7: 提交媒体功能**

```bash
git add lib/features/media lib/features/records lib/features/baby test/features/media
git commit -m "feat(flutter): persist media in private storage"
```

---

### Task 8: 删除、清空、版本化备份与原子恢复

**Files:**
- Create: `lib/features/records/presentation/delete_record_button.dart`
- Create: `lib/features/backup/domain/backup_manifest.dart`
- Create: `lib/features/backup/domain/backup_service.dart`
- Create: `lib/features/backup/data/local_backup_service.dart`
- Create: `lib/features/backup/presentation/backup_actions.dart`
- Modify: `lib/features/records/presentation/record_detail_page.dart`
- Modify: `lib/features/baby/presentation/baby_page.dart`
- Test: `test/features/records/delete_record_button_test.dart`
- Test: `test/features/backup/local_backup_service_test.dart`

**Interfaces:**
- Produces: `BackupManifestV1`、`BackupService.export()`、`inspect()`、`restore()`、`DeleteRecordButton`、`clearAllData()`。
- Consumes: `DatabaseLifecycle`、`MediaService`、archive、crypto、file_picker、share_plus。

- [ ] **Step 1: 写删除、清空和备份失败测试**

删除测试断言取消不访问 repository，确认后先提交数据库删除再清理附件。清空测试断言输入宝宝姓名完全匹配后才启用确认。备份测试覆盖正确清单、缺文件、大小不符、SHA-256 不符、路径穿越、不支持版本、临时数据库损坏和恢复中途失败后旧数据仍可读取。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/features/backup test/features/records/delete_record_button_test.dart`

Expected: FAIL，备份服务和删除组件尚不存在。

- [ ] **Step 3: 定义稳定的版本 1 清单**

```dart
@freezed
class BackupManifestV1 with _$BackupManifestV1 {
  const factory BackupManifestV1({
    @Default('baby-growth-backup') String format,
    @Default(1) int version,
    required String createdAt,
    required BackupFileEntry database,
    required List<BackupFileEntry> media,
  }) = _BackupManifestV1;
}

@freezed
class BackupFileEntry with _$BackupFileEntry {
  const factory BackupFileEntry({required String path, required String sha256, required int size}) = _BackupFileEntry;
}

abstract interface class BackupService {
  Future<String> exportBackup();
  Future<BackupInspection> inspect(String archivePath);
  Future<void> restore(BackupInspection inspected);
  Future<void> removeExpiredExports(Duration maxAge);
}

class BackupInspection {
  const BackupInspection({
    required this.temporaryDirectory,
    required this.manifest,
  });
  final String temporaryDirectory;
  final BackupManifestV1 manifest;
}
```

数据库固定路径 `database/app.db`，包扩展名 `.babygrowth.zip`。清单和 zip entry 只接受 `/` 分隔的相对路径，拒绝空路径、绝对路径、反斜杠和任何 `..` segment。

- [ ] **Step 4: 实现一致性导出和完整校验**

导出通过 `DatabaseLifecycle.withClosedDatabase()` 在 WAL checkpoint 后复制数据库，再枚举 repository 引用的头像、原媒体和缩略图；逐项写入 size 与 SHA-256，最后创建 zip 并调用系统分享面板。分享失败保留导出包并显示其路径；下次启动删除超过 24 小时的临时导出。

`inspect()` 先解压到唯一临时目录，再验证 format/version、路径安全、文件集合、大小和哈希，最后用独立 sqflite 连接执行 `PRAGMA integrity_check` 并检查 `user_version <= 1`。

- [ ] **Step 5: 实现 rollback 目录驱动的原子恢复**

恢复顺序固定为：inspect 成功 → 关闭当前数据库 → 将当前数据库和 media 目录 rename 到唯一 rollback 目录 → 将已校验临时数据 rename 到正式位置 → reopen 并运行向前迁移 → 查询 baby 与 records 验证可读 → 删除 rollback。任一步失败都删除不完整的新数据、rename rollback 回正式位置并 reopen；rollback 自身失败时保留目录且展示可恢复路径，不再执行任何清理。

- [ ] **Step 6: 实现删除与清空交互**

记录弹窗文案固定为“删除这条记录？此操作无法撤销。”。清空弹窗要求输入当前宝宝姓名，文案明确“将删除宝宝资料、全部记录和媒体，此操作无法撤销”。清空通过数据库事务删除索引，提交后删除媒体；文件删除失败记录为 orphan cleanup，下次启动重试。

- [ ] **Step 7: 运行备份、删除、生成代码和分析**

Run: `dart run build_runner build --delete-conflicting-outputs && dart format lib test && flutter test test/features/backup test/features/records && flutter analyze`

Expected: 清单、路径安全、校验、恢复回滚、删除与清空测试全部通过。

- [ ] **Step 8: 提交数据安全功能**

```bash
git add lib/features/backup lib/features/records lib/features/baby test/features/backup test/features/records
git commit -m "feat(flutter): add verified backup and restore"
```

---

### Task 9: 启动装配、错误边界、集成测试与双平台验收

**Files:**
- Create: `lib/app/providers.dart`
- Create: `lib/app/bootstrap.dart`
- Create: `lib/app/bootstrap_error_page.dart`
- Modify: `lib/main.dart`
- Modify: `lib/app/app.dart`
- Test: `test/app/bootstrap_test.dart`
- Create: `integration_test/core_flow_test.dart`
- Create: `docs/testing/flutter-device-smoke-test.md`
- Create: `README.md`

**Interfaces:**
- Produces: `AppServices`、`bootstrapApp()`、Riverpod service providers。
- Consumes: Tasks 3、7、8 的 database、repository、media 和 backup 服务。

- [ ] **Step 1: 写启动编排失败测试**

```dart
test('bootstraps services in safe order', () async {
  await bootstrapApp(environment);
  verifyInOrder([
    () => directories.ensureCreated(),
    () => database.open(),
    () => database.migrate(),
    () => media.removeStagingFiles(),
    () => media.removeOrphans(any()),
    () => backup.removeExpiredExports(const Duration(hours: 24)),
  ]);
});
```

补充测试：迁移失败返回不可继续状态；孤立媒体清理失败只记录非致命错误；检测到 rollback 目录时先尝试恢复再打开数据库。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/app/bootstrap_test.dart`

Expected: FAIL，启动装配尚不存在。

- [ ] **Step 3: 实现依赖装配和启动错误页**

```dart
class AppServices {
  const AppServices({
    required this.database,
    required this.babies,
    required this.records,
    required this.media,
    required this.backup,
  });
  final DatabaseLifecycle database;
  final BabyRepository babies;
  final RecordRepository records;
  final MediaService media;
  final BackupService backup;
}
```

providers 只暴露以上稳定接口。初始化完成前显示品牌启动页；数据库打开或迁移失败时显示“无法打开本地数据”和“重试”，不得进入业务路由。Flutter framework uncaught error 记录到本地 debug log，不上传网络。

- [ ] **Step 4: 添加集成测试**

`integration_test/core_flow_test.dart` 使用临时数据库和真实临时文件目录依次验证：创建宝宝 → 新增四类记录 → 倒序与筛选 → 编辑 → 删除 → 重启容器后仍可读取 → 导出备份 → 清空 → 恢复 → 损坏备份被拒绝且当前数据不变。

Run: `flutter test integration_test/core_flow_test.dart -d all`

Expected: 在所有已连接的 iOS Simulator、Android Emulator 或真机上核心流程通过；没有设备时该步骤明确失败为 `No devices found`，不得当作测试通过。

- [ ] **Step 5: 运行完整自动化与发布构建检查**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
dart format --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --coverage
flutter build apk --debug
flutter build ios --debug --no-codesign
```

Expected: 代码生成无冲突；格式、分析与全部测试通过；Android APK 和无签名 iOS debug build 成功。

- [ ] **Step 6: 编写并执行真机冒烟清单**

`docs/testing/flutter-device-smoke-test.md` 为 iPhone 和 Android 分别记录设备型号、OS 版本、App commit 与以下结果：

1. 首次建立宝宝资料并显示正确月龄。
2. 新增四类记录并验证倒序、跨日与跨时区分组。
3. 编辑、筛选、删除，强杀 App 后数据仍在。
4. 导入一张照片和一个视频，重启后仍可访问。
5. 拒绝相册权限、手工移走测试媒体并验证占位、模拟空间不足提示。
6. 导出备份，清空数据，再完整恢复。
7. 尝试损坏、缺文件和版本 999 的备份，确认原数据保持不变。

没有可用真机时逐项写 `BLOCKED — device unavailable`，不得把真机验收声明为通过。

- [ ] **Step 7: 更新 README 并执行最终状态检查**

README 写明产品范围、完全离线、Flutter 版本要求、`flutter pub get`、iOS/Android 启动命令、代码生成、测试与构建命令、私有媒体目录原则、备份格式和“不提供医学诊断”的限制。

Run: `flutter analyze && flutter test --coverage && git status --short`

Expected: 分析和测试通过；Git 只显示本任务计划内的预期文件，不包含 build 产物。

- [ ] **Step 8: 提交启动与验收材料**

```bash
git add lib/app lib/main.dart integration_test README.md docs/testing/flutter-device-smoke-test.md
git commit -m "test(flutter): verify offline baby timeline flows"
```

---

## Final Acceptance

- [ ] 四类记录的新增、查看、编辑和删除均通过自动化测试。
- [ ] 时间轴按发生时间倒序，跨天、跨时区分组及类型筛选通过测试。
- [ ] 宝宝姓名和生日校验、生日修改后的月龄更新通过测试。
- [ ] 数值输入拒绝非数字、负数和规格内定义的明显误输范围，且不输出医学判断。
- [ ] 媒体导入后位于 App 私有目录，重启后仍可访问；缺失文件只显示占位。
- [ ] 媒体或数据库写入失败不会产生半条记录，失败文件会立即补偿或在下次启动清理。
- [ ] 备份包含数据库、原媒体、缩略图和版本清单；损坏、缺文件、路径不安全或版本不支持的包不得覆盖当前数据。
- [ ] `dart format --set-exit-if-changed`、`flutter analyze`、`flutter test --coverage`、Android debug build 和 iOS no-codesign debug build 全部成功。
- [ ] iPhone 与 Android 真机核心流程结果已记录；无设备时明确记录阻塞，不作通过声明。
- [ ] 工作区没有意外文件，每个任务都以独立、可审查的 commit 收尾。
