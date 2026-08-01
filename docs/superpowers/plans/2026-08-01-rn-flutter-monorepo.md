# RN and Flutter Monorepo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Baby App into one long-lived repository containing independently buildable React Native and Flutter applications, then publish the verified result on `main`.

**Architecture:** Framework-specific code lives in `apps/react-native` and `apps/flutter`; neither application imports the other. Repository-level documentation and GitHub workflows coordinate product parity and independent validation while each application keeps its native package manager and toolchain.

**Tech Stack:** Expo 57, React Native 0.86, TypeScript 6, pnpm 10, Flutter/Dart, GitHub Actions, GitHub CLI

## Global Constraints

- Preserve the current uncommitted `tsconfig.json` content exactly and restore it at `apps/react-native/tsconfig.json` after the tracked baseline file is moved.
- Do not commit `.DS_Store`, generated dependency directories, Expo caches, Flutter caches, or unrelated working-tree changes.
- Keep `feature/rn` and `feature/baby-growth-timeline-flutter` available as migration references.
- Do not share runtime source code or package-manager state between the two applications.
- Do not push or change GitHub's default branch until both applications pass their local validation.
- Stage explicit paths for every migration commit; never use a broad staging command that can capture the preserved `tsconfig.json` modification.

---

### Task 1: Move the React Native application under `apps/react-native`

**Files:**
- Create directory: `apps/react-native/`
- Move: `app.json`, `app/`, `babel.config.js`, `ios/`, `jest.config.js`, `modules/`, `package.json`, `pnpm-lock.yaml`, `scripts/`, `src/`, `tsconfig.json`
- Move: root `README.md` to `apps/react-native/README.md`
- Move: root `.gitignore` to `apps/react-native/.gitignore`
- Move: `docs/testing/` to `apps/react-native/docs/testing/`
- Preserve: `docs/superpowers/`

**Interfaces:**
- Consumes: the tracked React Native tree at commit `c21e022` plus the user's uncommitted `tsconfig.json`
- Produces: a self-contained React Native project whose commands run from `apps/react-native`

- [ ] **Step 1: Capture baseline state and the user's TypeScript configuration**

Run:

```bash
git status --short --branch
shasum -a 256 tsconfig.json
cp tsconfig.json /tmp/baby-app-tsconfig.user.json
shasum -a 256 /tmp/baby-app-tsconfig.user.json
```

Expected: both SHA-256 values match; status shows `tsconfig.json` modified and `.DS_Store` untracked.

- [ ] **Step 2: Run the current React Native baseline checks**

Run:

```bash
pnpm test -- --runInBand
pnpm typecheck
```

Expected: Jest and TypeScript exit successfully. If a check already fails, record the exact failure before moving files and require the corresponding post-move check to have no new failure.

- [ ] **Step 3: Restore only the tracked TypeScript baseline before the Git-aware move**

Run:

```bash
git restore --source=HEAD --worktree tsconfig.json
mkdir -p apps/react-native/docs
```

Expected: `/tmp/baby-app-tsconfig.user.json` still has the SHA recorded in Step 1 and root `tsconfig.json` is clean.

- [ ] **Step 4: Move all tracked React Native files with history**

Run:

```bash
git mv app.json app babel.config.js ios jest.config.js modules package.json pnpm-lock.yaml scripts src tsconfig.json apps/react-native/
git mv README.md apps/react-native/README.md
git mv .gitignore apps/react-native/.gitignore
git mv docs/testing apps/react-native/docs/testing
```

Expected: `git status --short` reports renames into `apps/react-native` and leaves `docs/superpowers` at the repository root.

- [ ] **Step 5: Verify the structural move before committing**

Run:

```bash
git diff --cached --check
git status --short
test -f apps/react-native/package.json
test -f apps/react-native/docs/testing/device-smoke-test.md
test -f docs/superpowers/specs/2026-08-01-rn-flutter-monorepo-design.md
```

Expected: all checks exit successfully; no user-modified TypeScript content is staged.

- [ ] **Step 6: Commit the React Native relocation**

Run:

```bash
git commit -m "refactor: move React Native app into monorepo"
```

Expected: the commit contains moves only.

- [ ] **Step 7: Restore the user's TypeScript configuration at its new path**

Run:

```bash
cp /tmp/baby-app-tsconfig.user.json apps/react-native/tsconfig.json
shasum -a 256 apps/react-native/tsconfig.json
shasum -a 256 /tmp/baby-app-tsconfig.user.json
git status --short
```

Expected: both SHA-256 values match and `apps/react-native/tsconfig.json` is modified but unstaged.

---

### Task 2: Import the Flutter application under `apps/flutter`

**Files:**
- Create: `apps/flutter/.gitignore`
- Create: `apps/flutter/.metadata`
- Create: `apps/flutter/analysis_options.yaml`
- Create: `apps/flutter/android/**`
- Create: `apps/flutter/docs/**`
- Create: `apps/flutter/ios/**`
- Create: `apps/flutter/lib/**`
- Create: `apps/flutter/pubspec.lock`
- Create: `apps/flutter/pubspec.yaml`
- Create: `apps/flutter/test/**`

**Interfaces:**
- Consumes: the complete tracked tree from `feature/baby-growth-timeline-flutter`
- Produces: a self-contained Flutter project whose commands run from `apps/flutter`

- [ ] **Step 1: Export the Flutter branch without Git metadata**

Run:

```bash
git archive --format=tar --output=/tmp/baby-app-flutter.tar feature/baby-growth-timeline-flutter
mkdir -p apps/flutter
tar -xf /tmp/baby-app-flutter.tar -C apps/flutter
```

Expected: `apps/flutter/pubspec.yaml`, `apps/flutter/lib`, and `apps/flutter/test` exist; no `.git` entry exists below `apps/flutter`.

- [ ] **Step 2: Compare the imported tree with the source branch**

Run:

```bash
git ls-tree -r --name-only feature/baby-growth-timeline-flutter
find apps/flutter -type f | sort
```

Expected: every tracked Flutter branch path appears below `apps/flutter`; generated worktree files do not appear.

- [ ] **Step 3: Stage only the Flutter application and validate the index**

Run:

```bash
git add apps/flutter
git diff --cached --check
git diff --cached --name-only
git status --short
```

Expected: cached paths begin with `apps/flutter/`; `apps/react-native/tsconfig.json` remains modified and unstaged.

- [ ] **Step 4: Commit the Flutter import**

Run:

```bash
git commit -m "feat: add Flutter app to monorepo"
```

Expected: the commit contains only `apps/flutter` paths.

---

### Task 3: Add repository documentation, ignore rules, and independent CI

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `docs/product-parity.md`
- Create: `docs/superpowers/plans/2026-08-01-rn-flutter-monorepo.md`
- Create: `.github/workflows/react-native.yml`
- Create: `.github/workflows/flutter.yml`
- Modify: `apps/react-native/README.md`
- Modify: `apps/flutter/README.md` if the Flutter branch provides one; otherwise create it

**Interfaces:**
- Consumes: the two self-contained application directories from Tasks 1 and 2
- Produces: discoverable developer entry points and CI checks named `react-native` and `flutter`

- [ ] **Step 1: Write the root repository README**

Create `README.md` with:

```markdown
# Baby App

Baby App is a local-first baby growth journal maintained in two production implementations.

| Implementation | Location | Toolchain |
| --- | --- | --- |
| React Native | [`apps/react-native`](apps/react-native) | Expo, React Native, TypeScript, pnpm |
| Flutter | [`apps/flutter`](apps/flutter) | Flutter, Dart |

Both versions are long-lived and independently buildable. Product behavior should remain aligned; intentional differences are recorded in [`docs/product-parity.md`](docs/product-parity.md).

## Development

Follow each application's README for installation, test, and platform build commands:

- [React Native development](apps/react-native/README.md)
- [Flutter development](apps/flutter/README.md)

Framework-specific dependencies and generated files stay inside the corresponding application directory.
```

- [ ] **Step 2: Write root ignore rules**

Create `.gitignore` with:

```gitignore
.DS_Store
.superpowers/
.worktrees/
node_modules/
.pnpm-store/
```

Expected: the existing untracked root `.DS_Store` disappears from `git status` without being deleted or committed.

- [ ] **Step 3: Add explicit application documentation and parity tracking**

Keep the existing React Native product and safety documentation, but add this immediately below its title:

````markdown
> This is the React Native/Expo implementation. Run all commands below from `apps/react-native`.

```bash
cd apps/react-native
```
````

Create `apps/flutter/README.md` with:

````markdown
# Baby Growth Timeline — Flutter

This is the Flutter implementation of Baby App. It is maintained alongside the React Native version and stores application data locally on the device.

## Setup

Run all commands from the Flutter application directory:

```bash
cd apps/flutter
flutter pub get --enforce-lockfile
```

## Validate

```bash
flutter analyze
flutter test
```

## Run

```bash
flutter run
```

Product parity and intentional differences are tracked in [`../../docs/product-parity.md`](../../docs/product-parity.md).
````

Create `docs/product-parity.md` with:

```markdown
# Product parity

Both implementations are production versions of Baby App. Update this table whenever a product change affects only one implementation or lands at different times.

| Capability | React Native | Flutter | Notes |
| --- | --- | --- | --- |
| Baby profile | Supported | Supported | Local profile and age display |
| Unified growth timeline | Supported | Supported | Moments, growth, daily activity, and milestones |
| Create and edit records | Supported | Supported | Includes record detail flows |
| Delete records | Supported | Verify | Confirm Flutter behavior during device smoke testing |
| Private media storage | Supported | Supported | Photos and videos remain in application-private storage |
| Backup and restore | Supported | Verify | RN has documented hardened ZIP backup and recovery semantics; Flutter parity requires explicit verification |

`Verify` means the implementation may contain related code but has not been confirmed against the shared product contract. It does not mean unsupported.
```

- [ ] **Step 4: Add the React Native workflow**

Create `.github/workflows/react-native.yml`:

```yaml
name: React Native

on:
  pull_request:
    paths:
      - "apps/react-native/**"
      - ".github/workflows/react-native.yml"
  push:
    branches: [main]
    paths:
      - "apps/react-native/**"
      - ".github/workflows/react-native.yml"

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/react-native
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10.33.4
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm
          cache-dependency-path: apps/react-native/pnpm-lock.yaml
      - run: pnpm install --frozen-lockfile
      - run: pnpm test -- --runInBand
      - run: pnpm typecheck
```

- [ ] **Step 5: Add the Flutter workflow**

Create `.github/workflows/flutter.yml`:

```yaml
name: Flutter

on:
  pull_request:
    paths:
      - "apps/flutter/**"
      - ".github/workflows/flutter.yml"
  push:
    branches: [main]
    paths:
      - "apps/flutter/**"
      - ".github/workflows/flutter.yml"

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: apps/flutter
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get --enforce-lockfile
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 6: Stage explicit repository files and commit**

Run:

```bash
git add README.md .gitignore docs/product-parity.md docs/superpowers/plans/2026-08-01-rn-flutter-monorepo.md .github/workflows/react-native.yml .github/workflows/flutter.yml apps/react-native/README.md apps/flutter/README.md
git diff --cached --check
git diff --cached --name-only
git commit -m "chore: add monorepo documentation and CI"
```

Expected: the preserved `apps/react-native/tsconfig.json` modification is not in the commit.

---

### Task 4: Verify both applications and publish `main`

**Files:**
- Verify: `apps/react-native/**`
- Verify: `apps/flutter/**`
- Verify: `.github/workflows/*.yml`
- Preserve unstaged: `apps/react-native/tsconfig.json`

**Interfaces:**
- Consumes: the completed monorepo working tree
- Produces: a verified `main` branch on GitHub and an unchanged user TypeScript configuration

- [ ] **Step 1: Install and verify React Native from its new directory**

Run:

```bash
cd apps/react-native
pnpm install --frozen-lockfile
pnpm test -- --runInBand
pnpm typecheck
npx expo install --check
```

Expected: all commands exit successfully with the preserved TypeScript configuration present.

- [ ] **Step 2: Install and verify Flutter from its new directory**

Run:

```bash
cd apps/flutter
flutter pub get --enforce-lockfile
flutter analyze
flutter test
```

Expected: dependency restore, analysis, and all tests exit successfully.

- [ ] **Step 3: Verify repository boundaries and preserved user state**

Run from the repository root:

```bash
shasum -a 256 apps/react-native/tsconfig.json
shasum -a 256 /tmp/baby-app-tsconfig.user.json
git status --short --branch
git diff --check
git diff -- apps/react-native/tsconfig.json
find apps -name .git -o -name .DS_Store
```

Expected: the two hashes match; the only intentional tracked working-tree modification is `apps/react-native/tsconfig.json`; no nested Git repository exists; `.DS_Store` is ignored.

- [ ] **Step 4: Confirm `main` can advance without rewriting history**

Run:

```bash
git merge-base --is-ancestor main HEAD
git log --oneline main..HEAD
```

Expected: the ancestry check exits successfully and the log contains the RN work, design, and monorepo migration commits.

- [ ] **Step 5: Publish and select `main`**

Run:

```bash
git push origin HEAD:main
git branch -f main HEAD
gh repo edit whatwg6/baby-app --default-branch main
```

Expected: GitHub contains `main` at the verified commit and reports `main` as the default branch. No historical feature branch is deleted.

- [ ] **Step 6: Perform final remote verification**

Run:

```bash
gh repo view whatwg6/baby-app --json defaultBranchRef,url,visibility
git ls-remote --heads origin main feature/rn
git status --short --branch
```

Expected: the default branch is `main`, both remote branches remain visible, the repository is private, and the user's TypeScript modification remains local and unstaged.
