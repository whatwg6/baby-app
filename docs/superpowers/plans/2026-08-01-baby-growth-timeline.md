# 宝宝成长时间轴 App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个完全离线、同时支持 iPhone 和 Android 的宝宝成长记录 App，以统一时间轴呈现珍贵时刻、成长数据、日常活动和里程碑，并支持本地完整备份与恢复。

**Architecture:** 使用 Expo Router 组织页面，功能代码按 `baby`、`records`、`timeline`、`media`、`backup` 分区。SQLite 数据访问统一封装在 repository 中，UI 只能调用 TypeScript 接口；媒体保存在 App 私有目录，备份服务负责数据库和媒体的一致性打包与恢复。

**Tech Stack:** React Native、Expo、Expo Development Build、TypeScript、Expo Router、expo-sqlite、expo-file-system、expo-image-picker、expo-image-manipulator、expo-document-picker、expo-sharing、expo-crypto、react-native-zip-archive、Zod、Jest、jest-expo、React Native Testing Library。

## Global Constraints

- 第一版完全单机，无服务端、账号、云同步或联网依赖。
- 只支持一个宝宝；姓名和生日必填，头像和性别可选。
- 支持 iPhone 和 Android，一套 TypeScript 代码实现。
- 所有记录进入统一时间轴，并按发生时间倒序排列。
- 支持珍贵时刻、成长数据、日常活动和里程碑四类记录。
- 媒体必须复制到 App 私有目录，不能长期引用系统相册的临时 URI。
- 备份恢复失败时不得改动当前数据。
- App 不提供医学诊断或成长异常判断。
- 每个实现任务必须先看到目标测试失败，再写最小实现并看到测试通过。

## File Map

- `app/_layout.tsx`：初始化数据库与根导航。
- `app/index.tsx`：根据是否已建立宝宝资料决定跳转位置。
- `app/(tabs)/_layout.tsx`：时间轴、添加、宝宝三个底部入口。
- `app/(tabs)/timeline.tsx`：时间轴页面装配。
- `app/(tabs)/add.tsx`：记录类型选择。
- `app/(tabs)/baby.tsx`：宝宝资料与本地数据管理。
- `app/record/new.tsx`、`app/record/[id].tsx`：记录创建与详情路由。
- `app/baby/setup.tsx`：首次宝宝资料建立。
- `src/domain/types.ts`：跨模块共享的领域类型。
- `src/domain/validation.ts`：Zod 输入校验与表单到领域对象的转换。
- `src/domain/date.ts`：月龄、日期标题与时间轴分组。
- `src/data/database.ts`：SQLite 打开、事务与初始化。
- `src/data/migrations.ts`：版本化表结构。
- `src/data/repositories.ts`：repository 接口及 SQLite 实现。
- `src/features/baby/`：宝宝资料表单、展示和 hook。
- `src/features/records/`：四类记录表单、详情和删除。
- `src/features/timeline/`：查询、筛选、分组与卡片。
- `src/features/media/mediaService.ts`：媒体导入、正式落盘及清理。
- `src/features/backup/backupService.ts`：导出、校验和原子恢复。
- `src/test/`：测试辅助对象、内存 repository 和 fixtures。

---

### Task 1: Expo 工程骨架与可测试导航壳

**Files:**
- Create: `package.json`
- Create: `app.json`
- Create: `tsconfig.json`
- Create: `babel.config.js`
- Create: `jest.config.js`
- Modify: `.gitignore`
- Create: `app/_layout.tsx`
- Create: `app/index.tsx`
- Create: `app/(tabs)/_layout.tsx`
- Create: `app/(tabs)/timeline.tsx`
- Create: `app/(tabs)/add.tsx`
- Create: `app/(tabs)/baby.tsx`
- Create: `src/ui/theme.ts`
- Test: `src/__tests__/app-shell.test.tsx`

**Interfaces:**
- Produces: Expo Router 页面骨架；`theme` 导出 `colors`、`spacing`、`radius`。
- Consumes: 无。

- [ ] **Step 1: 创建 Expo TypeScript 工程配置并安装依赖**

创建最小 `package.json`，脚本固定为：

```json
{
  "name": "baby-growth-timeline",
  "version": "1.0.0",
  "private": true,
  "main": "expo-router/entry",
  "scripts": {
    "start": "expo start --dev-client",
    "ios": "expo run:ios",
    "android": "expo run:android",
    "typecheck": "tsc --noEmit",
    "test": "jest --runInBand"
  }
}
```

运行：

```bash
pnpm add expo expo-dev-client react react-native expo-router expo-sqlite expo-file-system expo-image-picker expo-image-manipulator expo-document-picker expo-sharing expo-crypto react-native-zip-archive zod
pnpm add -D typescript jest jest-expo @types/jest @testing-library/react-native react-test-renderer
npx expo install --fix
```

Expected: `pnpm-lock.yaml` 生成，`npx expo install --check` 返回依赖兼容。

`app.json` 固定启用 `expo-router`、`expo-image-picker` 和 `expo-document-picker` plugins，并设置 iOS bundle identifier `com.local.babygrowth`、Android package `com.local.babygrowth`。由于归档库包含原生模块，真机运行使用 Expo Development Build，不使用 Expo Go。`.gitignore` 增加 `node_modules/`、`.expo/`、`dist/`、`ios/`、`android/`，原生目录由 Expo prebuild 按需生成。

- [ ] **Step 2: 写导航壳失败测试**

```tsx
import { render, screen } from '@testing-library/react-native';
import TimelineScreen from '../../app/(tabs)/timeline';

test('shows the empty timeline action', () => {
  render(<TimelineScreen />);
  expect(screen.getByText('还没有成长记录')).toBeTruthy();
  expect(screen.getByText('记录第一个瞬间')).toBeTruthy();
});
```

- [ ] **Step 3: 运行测试确认失败**

Run: `pnpm test -- src/__tests__/app-shell.test.tsx`

Expected: FAIL，原因是 `TimelineScreen` 或目标文案尚不存在。

- [ ] **Step 4: 实现最小导航与主题**

`src/ui/theme.ts` 必须导出：

```ts
export const colors = {
  background: '#FFF9F3', card: '#FFFFFF', text: '#352F2B',
  muted: '#857B73', accent: '#E58F78', border: '#EDE2D8', danger: '#B94747',
} as const;
export const spacing = { xs: 4, sm: 8, md: 16, lg: 24, xl: 32 } as const;
export const radius = { sm: 10, md: 16, lg: 24 } as const;
```

创建三个 tab；时间轴页显示测试中的空状态，添加页显示“选择记录类型”，宝宝页显示“宝宝资料”。

- [ ] **Step 5: 验证测试、类型和 Expo 配置**

Run: `pnpm test -- src/__tests__/app-shell.test.tsx && pnpm typecheck && npx expo config --type public`

Expected: 测试 PASS、TypeScript 无错误、Expo config 正常输出 iOS/Android 配置。

- [ ] **Step 6: 提交工程骨架**

```bash
git add .gitignore package.json pnpm-lock.yaml app.json tsconfig.json babel.config.js jest.config.js app src/ui src/__tests__
git commit -m "feat: scaffold offline baby timeline app"
```

---

### Task 2: 领域类型、输入校验与日期规则

**Files:**
- Create: `src/domain/types.ts`
- Create: `src/domain/validation.ts`
- Create: `src/domain/date.ts`
- Test: `src/domain/__tests__/validation.test.ts`
- Test: `src/domain/__tests__/date.test.ts`

**Interfaces:**
- Produces: `RecordType`、`Baby`、`TimelineRecord`、`RecordDraft`、`NewRecordInput`、四类 detail 类型；`parseBabyInput()`、`parseRecordDraft()`、`calculateAgeLabel()`、`groupRecordsByDay()`。
- Consumes: Zod。

- [ ] **Step 1: 写领域行为失败测试**

测试必须覆盖：未来生日失败；成长数据三个值均为空失败；珍贵时刻文字和媒体均为空失败；合法里程碑成功；月龄跨年计算；时间轴倒序和日期分组。

```ts
expect(() => parseBabyInput({ name: '安安', birthDate: '2099-01-01' }, now)).toThrow();
expect(() => parseRecordDraft({ type: 'growth', occurredAt: now, details: {}, attachments: [] })).toThrow();
expect(calculateAgeLabel('2025-06-15', new Date('2026-08-01'))).toBe('1岁1个月');
expect(groupRecordsByDay(records).map(group => group.key)).toEqual(['2026-08-01', '2026-07-31']);
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/domain/__tests__`

Expected: FAIL，模块尚不存在。

- [ ] **Step 3: 定义稳定领域接口**

```ts
export type RecordType = 'moment' | 'growth' | 'activity' | 'milestone';
export type ActivityType = 'feeding' | 'sleep' | 'diaper';
export type MediaType = 'image' | 'video';

export interface Baby { id: string; name: string; birthDate: string; sex: 'female' | 'male' | null; avatarPath: string | null; createdAt: string; updatedAt: string; }
export interface Attachment { id: string; recordId: string; mediaType: MediaType; filePath: string; thumbnailPath: string | null; createdAt: string; }
export interface TimelineRecord { id: string; type: RecordType; occurredAt: string; note: string | null; details: GrowthDetails | ActivityDetails | MilestoneDetails | null; attachments: Attachment[]; createdAt: string; updatedAt: string; }
export type RecordDraftAttachment =
  | { kind: 'picked'; sourceUri: string; mediaType: MediaType }
  | { kind: 'existing'; id: string; mediaType: MediaType; filePath: string; thumbnailPath: string | null };
export interface NewAttachmentInput { id?: string; mediaType: MediaType; filePath: string; thumbnailPath: string | null; }
export interface RecordDraft { type: RecordType; occurredAt: string; note: string | null; details: GrowthDetails | ActivityDetails | MilestoneDetails | null; attachments: RecordDraftAttachment[]; }
export interface NewRecordInput extends Omit<RecordDraft, 'attachments'> { attachments: NewAttachmentInput[]; }
```

`parseRecordDraft()` 返回校验后的 `RecordDraft`；数值只做防误输边界校验：身高 `20–250 cm`、体重 `0.2–300 kg`、头围 `10–100 cm`，不输出医学结论。媒体保存编排在 Task 7 将 `RecordDraft` 转成只包含 App 私有路径的 `NewRecordInput`。

- [ ] **Step 4: 实现日期与分组函数**

`calculateAgeLabel(birthDate, now)` 使用自然年/月差，日期未到时借一个月；小于一个月显示天数。`groupRecordsByDay(records)` 先按 `occurredAt` 倒序，再使用设备本地日期生成 `YYYY-MM-DD` 分组键。

- [ ] **Step 5: 运行领域测试和类型检查**

Run: `pnpm test -- src/domain/__tests__ && pnpm typecheck`

Expected: 全部 PASS，无类型错误。

- [ ] **Step 6: 提交领域层**

```bash
git add src/domain
git commit -m "feat: define baby timeline domain rules"
```

---

### Task 3: SQLite 迁移与 repository

**Files:**
- Create: `src/data/database.ts`
- Create: `src/data/migrations.ts`
- Create: `src/data/repositories.ts`
- Create: `src/test/memoryRepositories.ts`
- Create: `src/test/fixtures.ts`
- Test: `src/data/__tests__/migrations.test.ts`
- Test: `src/data/__tests__/repository-contract.test.ts`

**Interfaces:**
- Produces: `createDatabaseManager()`、`migrateDatabase(db): Promise<void>`、`BabyRepository`、`RecordTransaction`、`RecordRepository`、`createSQLiteRepositories(db)`。
- Consumes: Task 2 的 `Baby`、`TimelineRecord`、`NewRecordInput`。

- [ ] **Step 1: 写迁移和 repository 合约失败测试**

```ts
export function recordRepositoryContract(createRepository: () => Promise<RecordRepository>) {
  test('creates, lists, updates and deletes a complete record', async () => {
    const repository = await createRepository();
    const created = await repository.create(momentInputFixture());
    expect((await repository.list()).map(x => x.id)).toEqual([created.id]);
    await repository.update(created.id, { ...momentInputFixture(), note: '修改后' });
    expect((await repository.get(created.id))?.note).toBe('修改后');
    await repository.delete(created.id);
    expect(await repository.get(created.id)).toBeNull();
  });
}
```

同一合约分别用于 `MemoryRecordRepository` 和 SQLite repository；SQLite 测试若 Jest 环境不能加载原生模块，则在 `jest-expo` 中 mock `expo-sqlite` 并把 SQL 集成验证放入 Task 9 真机清单。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/data/__tests__`

Expected: FAIL，repository 接口和实现不存在。

- [ ] **Step 3: 定义 repository 接口**

```ts
export interface BabyRepository {
  get(): Promise<Baby | null>;
  save(input: BabyInput): Promise<Baby>;
  clear(): Promise<void>;
}
export interface RecordTransaction {
  create(input: NewRecordInput): Promise<TimelineRecord>;
  update(id: string, input: NewRecordInput): Promise<TimelineRecord>;
  delete(id: string): Promise<Attachment[]>;
}
export interface RecordRepository extends RecordTransaction {
  list(filter?: { types?: RecordType[] }): Promise<TimelineRecord[]>;
  get(id: string): Promise<TimelineRecord | null>;
  withTransaction<T>(work: (tx: RecordTransaction) => Promise<T>): Promise<T>;
}
export interface DatabaseManager {
  initialize(): Promise<SQLiteDatabase>;
  withClosedDatabase<T>(work: (databasePath: string) => Promise<T>): Promise<T>;
  reopen(): Promise<SQLiteDatabase>;
}
```

- [ ] **Step 4: 建立版本 1 表结构**

`migrations.ts` 必须使用 `PRAGMA user_version` 管理版本，并创建 `baby`、`records`、`growth_details`、`activity_details`、`milestone_details`、`attachments`。启用 `PRAGMA foreign_keys = ON`，详情表的 `record_id` 唯一并级联删除；`records.occurred_at` 建降序索引。

- [ ] **Step 5: 实现事务化 SQLite repository 与内存实现**

公开的 `create()`、`update()`、`delete()` 各自调用 `withTransaction()`；事务回调收到的 `RecordTransaction` 直接写入当前事务，避免嵌套事务。`delete()` 先返回待清理附件列表，再在事务中删除记录。列表查询必须组装出完整 `TimelineRecord[]`，不得把 SQL row 暴露给 UI。

`DatabaseManager.withClosedDatabase()` 先执行 `PRAGMA wal_checkpoint(TRUNCATE)` 再关闭连接，将数据库路径交给回调，并在 `finally` 中重新打开和迁移数据库。Task 8 通过这个接口复制一致的数据库文件或原子替换恢复文件，不直接操作仍打开的 SQLite 连接。

- [ ] **Step 6: 运行合约测试与类型检查**

Run: `pnpm test -- src/data/__tests__ && pnpm typecheck`

Expected: 内存合约、迁移序列和 SQLite 映射测试均 PASS。

- [ ] **Step 7: 提交数据层**

```bash
git add src/data src/test
git commit -m "feat: add local sqlite repositories"
```

---

### Task 4: 宝宝资料建立与月龄展示

**Files:**
- Create: `app/baby/setup.tsx`
- Create: `src/features/baby/BabyForm.tsx`
- Create: `src/features/baby/BabyHeader.tsx`
- Create: `src/features/baby/useBaby.ts`
- Modify: `app/index.tsx`
- Modify: `app/(tabs)/baby.tsx`
- Test: `src/features/baby/__tests__/BabyForm.test.tsx`
- Test: `src/features/baby/__tests__/BabyHeader.test.tsx`

**Interfaces:**
- Produces: `BabyForm({ initialValue?, onSave })`、`BabyHeader({ baby, now? })`、`useBaby()`。
- Consumes: `BabyRepository`、`parseBabyInput()`、`calculateAgeLabel()`。

- [ ] **Step 1: 写资料表单失败测试**

测试空姓名、未来生日、合法保存以及 `2025-06-15` 在 `2026-08-01` 显示“1岁1个月”。

```tsx
fireEvent.changeText(screen.getByLabelText('宝宝姓名'), '安安');
fireEvent.changeText(screen.getByLabelText('出生日期'), '2025-06-15');
fireEvent.press(screen.getByText('保存'));
await waitFor(() => expect(onSave).toHaveBeenCalledWith(expect.objectContaining({ name: '安安' })));
```

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/features/baby/__tests__`

Expected: FAIL，组件尚不存在。

- [ ] **Step 3: 实现 BabyForm 和 useBaby**

表单只收集姓名、生日、可选性别与头像路径；错误显示在对应字段下。`useBaby()` 暴露 `{ baby, loading, save, reload }`，所有持久化通过 `BabyRepository`。

- [ ] **Step 4: 实现首次路由和宝宝页**

`app/index.tsx` 在初始化完成后：没有宝宝资料时 `router.replace('/baby/setup')`，否则进入 `/(tabs)/timeline`。宝宝页复用同一个 `BabyForm` 编辑资料，并使用 `BabyHeader` 显示头像、姓名和月龄。

- [ ] **Step 5: 运行组件测试和类型检查**

Run: `pnpm test -- src/features/baby/__tests__ && pnpm typecheck`

Expected: 全部 PASS。

- [ ] **Step 6: 提交宝宝资料功能**

```bash
git add app src/features/baby
git commit -m "feat: add local baby profile"
```

---

### Task 5: 统一时间轴、筛选与记录详情

**Files:**
- Create: `src/features/timeline/TimelineScreen.tsx`
- Create: `src/features/timeline/TimelineCard.tsx`
- Create: `src/features/timeline/TimelineFilters.tsx`
- Create: `src/features/timeline/useTimeline.ts`
- Create: `app/record/[id].tsx`
- Create: `src/features/records/RecordDetail.tsx`
- Modify: `app/(tabs)/timeline.tsx`
- Test: `src/features/timeline/__tests__/TimelineScreen.test.tsx`
- Test: `src/features/records/__tests__/RecordDetail.test.tsx`

**Interfaces:**
- Produces: `TimelineScreen({ repository, baby })`、`TimelineCard({ record })`、`useTimeline(repository)`。
- Consumes: `RecordRepository.list()`、`groupRecordsByDay()`、`RecordType`。

- [ ] **Step 1: 写时间轴失败测试**

使用内存 repository 建立照片时刻、成长数据和睡眠记录，断言日期倒序、卡片摘要、类型筛选和空状态。详情测试断言成长数据以 `cm/kg` 展示，缺失媒体显示“媒体文件不可用”。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/features/timeline/__tests__ src/features/records/__tests__/RecordDetail.test.tsx`

Expected: FAIL，时间轴和详情组件不存在。

- [ ] **Step 3: 实现 useTimeline 与筛选**

```ts
export interface TimelineState {
  records: TimelineRecord[];
  selectedTypes: RecordType[];
  loading: boolean;
  error: string | null;
  setSelectedTypes(types: RecordType[]): void;
  reload(): Promise<void>;
}
```

筛选为空数组表示显示全部。读取失败时保留当前已显示列表，并显示“无法读取记录，请重试”。

- [ ] **Step 4: 实现卡片和日期分组**

珍贵时刻优先展示首张图片；成长卡片展示已填写的测量值；活动卡片展示类型及数量/时长；里程碑展示标题。日期标题当天为“今天”，前一天为“昨天”，其余使用本地化年月日。

- [ ] **Step 5: 实现详情路由**

`app/record/[id].tsx` 从路由参数取 `id`，调用 repository 获取记录；不存在时显示“记录不存在”，读取失败时提供重试。详情页提供“编辑”和“删除”入口，删除行为在 Task 8 接通。

- [ ] **Step 6: 运行测试和类型检查**

Run: `pnpm test -- src/features/timeline src/features/records/__tests__/RecordDetail.test.tsx && pnpm typecheck`

Expected: 全部 PASS。

- [ ] **Step 7: 提交时间轴**

```bash
git add app src/features/timeline src/features/records/RecordDetail.tsx src/features/records/__tests__/RecordDetail.test.tsx
git commit -m "feat: render unified baby timeline"
```

---

### Task 6: 四类记录创建与编辑

**Files:**
- Create: `app/record/new.tsx`
- Create: `app/record/edit/[id].tsx`
- Create: `src/features/records/RecordTypePicker.tsx`
- Create: `src/features/records/RecordEditor.tsx`
- Create: `src/features/records/forms/MomentFields.tsx`
- Create: `src/features/records/forms/GrowthFields.tsx`
- Create: `src/features/records/forms/ActivityFields.tsx`
- Create: `src/features/records/forms/MilestoneFields.tsx`
- Modify: `app/(tabs)/add.tsx`
- Test: `src/features/records/__tests__/RecordEditor.test.tsx`

**Interfaces:**
- Produces: `RecordTypePicker({ onSelect })`、`RecordEditor({ type, initialValue?, onSubmit })`。
- Consumes: `parseRecordDraft()`；Task 7 之前用无媒体的 `NewRecordInput` 调用 `RecordRepository.create()`、`RecordRepository.update()`。

- [ ] **Step 1: 写四类表单失败测试**

分别测试：空的珍贵时刻不保存；成长数据接受单个合法测量值；活动类型必填；里程碑标题必填；发生时间默认当前时间但可编辑；编辑时原值正确回填。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/features/records/__tests__/RecordEditor.test.tsx`

Expected: FAIL，编辑器不存在。

- [ ] **Step 3: 实现类型选择与分类型字段**

类型选择器固定输出 `moment | growth | activity | milestone`。`RecordEditor` 管理共有字段 `occurredAt`、`note`、`attachments`，四个 fields 组件只管理类型专属字段，并输出符合 Task 2 的 `RecordDraft`。没有新媒体时，路由先把现有附件映射为 `NewAttachmentInput` 后调用 repository；Task 7 用统一媒体保存编排替换这段临时装配。

- [ ] **Step 4: 接通新增和编辑路由**

新增成功后使用 `router.replace('/(tabs)/timeline')`；编辑成功后返回详情页。提交中禁用保存按钮，repository 错误显示“保存失败，已有数据未受影响”，并保留表单输入。

- [ ] **Step 5: 运行测试和类型检查**

Run: `pnpm test -- src/features/records/__tests__/RecordEditor.test.tsx && pnpm typecheck`

Expected: 全部 PASS。

- [ ] **Step 6: 提交记录编辑功能**

```bash
git add app src/features/records
git commit -m "feat: create and edit timeline records"
```

---

### Task 7: 媒体导入、私有存储与失败清理

**Files:**
- Create: `src/features/media/mediaService.ts`
- Create: `src/features/media/MediaPicker.tsx`
- Create: `src/features/media/MediaPreview.tsx`
- Modify: `src/features/baby/BabyForm.tsx`
- Modify: `src/features/baby/useBaby.ts`
- Modify: `src/features/records/forms/MomentFields.tsx`
- Modify: `src/features/records/forms/MilestoneFields.tsx`
- Modify: `src/features/records/RecordEditor.tsx`
- Test: `src/features/media/__tests__/mediaService.test.ts`
- Test: `src/features/media/__tests__/MediaPicker.test.tsx`

**Interfaces:**
- Produces: `MediaService.stage()`、`commit()`、`rollback()`、`remove()`、`removeOrphans()`；`StagedMedia`。
- Consumes: expo-image-picker、expo-file-system、`Attachment`。

- [ ] **Step 1: 写媒体生命周期失败测试**

```ts
const staged = await service.stage({ uri: 'file:///picker/a.jpg', mediaType: 'image' });
expect(fs.copy).toHaveBeenCalledWith(expect.objectContaining({ to: expect.stringContaining('/staging/') }));
const committed = await service.commit(staged);
expect(committed.filePath).toContain('/media/');
await service.rollback(staged);
expect(fs.delete).toHaveBeenCalled();
```

补充测试：拒绝不支持格式；空间不足返回可展示错误；`removeOrphans(referencedPaths)` 只删除未被数据库引用的文件。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/features/media/__tests__`

Expected: FAIL，媒体服务不存在。

- [ ] **Step 3: 实现 MediaService**

```ts
export interface MediaService {
  stage(input: { uri: string; mediaType: MediaType }): Promise<StagedMedia>;
  commit(staged: StagedMedia): Promise<{ filePath: string; thumbnailPath: string | null }>;
  rollback(staged: StagedMedia): Promise<void>;
  remove(paths: string[]): Promise<void>;
  removeOrphans(referencedPaths: string[]): Promise<void>;
}
```

`StagedMedia` 固定包含 `{ stagingPath, finalPath, mediaType, thumbnailStagingPath, thumbnailFinalPath }`；数据库事务可先引用预定的 `finalPath`，只有 `commit()` 成功后才提交。文件名使用 UUID 并保留受支持扩展名；图片生成缩略图，视频第一版允许缩略图路径为 `null`。服务只使用 App document 目录下的 `staging/` 与 `media/`。

- [ ] **Step 4: 与记录保存事务协同**

保存顺序固定为：stage 所有 `kind: 'picked'` 媒体 → 调用 `RecordRepository.withTransaction()` → 在事务内写入记录及附件索引 → commit 媒体 → 事务回调成功后提交数据库。媒体 commit 失败会抛错并回滚数据库；数据库提交失败则删除本次已 commit 文件。`kind: 'existing'` 附件保留原路径和可选 id，repository 的 update 负责保留、增加或删除对应索引。把该编排封装为：

```ts
saveRecordWithMedia(input: RecordDraft, dependencies: { records: RecordRepository; media: MediaService }): Promise<TimelineRecord>
```

- [ ] **Step 5: 实现选择与预览组件**

请求相册权限被拒绝时显示“请在系统设置中允许访问照片”；用户取消选择不显示错误。珍贵时刻允许图片或视频，里程碑和宝宝头像只选择图片。更换头像成功后删除旧头像文件；失败时继续使用旧头像。`removeOrphans()` 的引用集合同时包含宝宝头像与所有记录附件。缺失本地文件时 `MediaPreview` 显示占位卡片而不是抛错。

- [ ] **Step 6: 运行媒体与记录回归测试**

Run: `pnpm test -- src/features/media src/features/records && pnpm typecheck`

Expected: 全部 PASS。

- [ ] **Step 7: 提交媒体功能**

```bash
git add src/features/media src/features/records
git commit -m "feat: persist timeline media locally"
```

---

### Task 8: 删除、清空、备份与原子恢复

**Files:**
- Create: `src/features/backup/backupManifest.ts`
- Create: `src/features/backup/backupService.ts`
- Create: `src/features/backup/BackupActions.tsx`
- Create: `src/features/records/DeleteRecordButton.tsx`
- Modify: `src/features/records/RecordDetail.tsx`
- Modify: `app/(tabs)/baby.tsx`
- Test: `src/features/backup/__tests__/backupService.test.ts`
- Test: `src/features/records/__tests__/DeleteRecordButton.test.tsx`

**Interfaces:**
- Produces: `BackupService.export()`、`inspect()`、`restore()`；`BackupManifestV1`；`DeleteRecordButton`。
- Consumes: `DatabaseManager`、MediaService、expo-file-system、expo-document-picker、expo-sharing、expo-crypto、react-native-zip-archive、repository。

- [ ] **Step 1: 写删除和备份失败测试**

测试删除必须确认；取消不调用 repository；确认后删除数据库记录并清理返回的附件。备份测试覆盖正确 manifest、缺文件、哈希不一致、不支持版本、恢复中途失败时旧数据保持不变。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/features/backup src/features/records/__tests__/DeleteRecordButton.test.tsx`

Expected: FAIL，服务和组件尚不存在。

- [ ] **Step 3: 定义版本化备份清单**

```ts
export interface BackupManifestV1 {
  format: 'baby-growth-backup';
  version: 1;
  createdAt: string;
  database: { path: 'database/app.db'; sha256: string };
  media: Array<{ path: string; sha256: string; size: number }>;
}
```

导出包扩展名使用 `.babygrowth.zip`，内部只允许相对路径；解包时拒绝 `..` 和绝对路径，防止路径穿越。

- [ ] **Step 4: 实现导出和校验**

通过 `DatabaseManager.withClosedDatabase()` 在 WAL checkpoint 并关闭连接后复制 SQLite 一致性快照，再将快照、媒体和 manifest 写入临时包；使用 expo-crypto 计算 SHA-256，使用 react-native-zip-archive 创建归档。成功后调用系统分享面板。无可用分享目标时保留临时文件并展示路径，分享结束后清理过期临时导出。

- [ ] **Step 5: 实现原子恢复**

恢复固定执行：选择文件 → 解包到临时目录 → 校验格式、版本、路径、大小和哈希 → 打开临时数据库并运行 `PRAGMA integrity_check` → 关闭当前数据库 → 将当前数据改名为 rollback 副本 → 放入恢复数据 → 重开并迁移 → 成功后删除 rollback 副本。任一步骤失败都从 rollback 副本恢复当前数据。

- [ ] **Step 6: 实现删除、清空和操作界面**

删除弹窗文案为“删除这条记录？此操作无法撤销。”；清空弹窗要求再次输入宝宝姓名后才启用确认按钮。清空同时删除 SQLite 数据与媒体，失败时展示具体阶段并再次扫描孤立媒体。

- [ ] **Step 7: 运行备份、删除和类型测试**

Run: `pnpm test -- src/features/backup src/features/records && pnpm typecheck`

Expected: 全部 PASS。

- [ ] **Step 8: 提交数据安全功能**

```bash
git add app src/features/backup src/features/records
git commit -m "feat: add verified local backup and restore"
```

---

### Task 9: App 初始化、错误边界与完整流程验证

**Files:**
- Create: `src/app/AppProvider.tsx`
- Create: `src/app/AppErrorBoundary.tsx`
- Create: `src/app/initializeApp.ts`
- Create: `src/app/__tests__/initializeApp.test.ts`
- Create: `docs/testing/device-smoke-test.md`
- Modify: `app/_layout.tsx`
- Modify: `app/index.tsx`
- Create: `README.md`

**Interfaces:**
- Produces: `initializeApp()`、`AppProvider`，向各 feature 提供 repositories、MediaService、BackupService。
- Consumes: Tasks 3、7、8 的全部基础服务。

- [ ] **Step 1: 写初始化失败测试**

测试初始化顺序为：创建目录 → 打开数据库 → 执行迁移 → 清理 staging → 清理孤立媒体 → 返回依赖；迁移失败时展示不可继续的错误页且不进入 tabs。

- [ ] **Step 2: 运行测试确认失败**

Run: `pnpm test -- src/app/__tests__/initializeApp.test.ts`

Expected: FAIL，初始化模块不存在。

- [ ] **Step 3: 实现依赖装配和错误边界**

`AppProvider` 只暴露稳定接口：

```ts
export interface AppServices {
  babies: BabyRepository;
  records: RecordRepository;
  media: MediaService;
  backup: BackupService;
  database: DatabaseManager;
}
```

根布局在初始化完成前显示启动页；失败时显示“无法打开本地数据”及“重试”按钮，不渲染业务页面。

- [ ] **Step 4: 补齐自动化验证**

Run: `pnpm test -- --coverage && pnpm typecheck && npx expo install --check && npx expo export --platform ios --output-dir dist/ios && npx expo export --platform android --output-dir dist/android`

Expected: Jest 0 failures；TypeScript 0 errors；依赖兼容；iOS 和 Android 静态 bundle 均成功生成。

- [ ] **Step 5: 编写并执行真机冒烟清单**

`docs/testing/device-smoke-test.md` 必须逐项记录 iPhone 和 Android 的结果：

1. 首次建立宝宝资料并显示正确月龄。
2. 新增四类记录并验证倒序与日期分组。
3. 编辑、筛选、删除并验证重启后状态。
4. 导入一张照片和一个视频，重启后仍可访问。
5. 拒绝相册权限、模拟缺失媒体和低存储提示。
6. 导出备份，清空数据，再完整恢复。
7. 尝试损坏备份，确认原数据保持不变。

若当前环境没有真机，将每一项标记为 `BLOCKED — device unavailable`，不得宣称真机验收完成。

- [ ] **Step 6: 更新 README**

README 写明：产品范围、完全离线、安装命令、启动 iOS/Android、测试命令、备份格式，以及“不提供医学诊断”的限制。

- [ ] **Step 7: 运行最终验证并提交**

Run: `pnpm test -- --coverage && pnpm typecheck && git status --short`

Expected: 自动化测试和类型检查通过；Git 只显示本任务计划中的预期文件。

```bash
git add app src/app README.md docs/testing/device-smoke-test.md
git commit -m "test: verify offline baby timeline flows"
```

---

## Final Acceptance

- [ ] 四类记录的新增、查看、编辑和删除均通过自动化测试。
- [ ] 时间轴排序、跨天分组、类型筛选和月龄计算通过测试。
- [ ] 媒体导入后位于 App 私有目录，重启后仍可访问。
- [ ] 保存失败不产生半条记录，删除后不遗留被删除记录的媒体。
- [ ] 备份可导出并完整恢复；损坏备份不覆盖当前数据。
- [ ] `pnpm test -- --coverage`、`pnpm typecheck`、`npx expo install --check`、iOS/Android export 全部成功。
- [ ] iPhone 与 Android 真机冒烟结果已记录；没有设备时明确记录阻塞，不作通过声明。
- [ ] 工作区没有意外文件，所有任务均按独立提交保存。
