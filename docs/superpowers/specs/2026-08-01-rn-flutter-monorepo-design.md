# RN and Flutter Monorepo Design

## Goal

Maintain the React Native and Flutter implementations as equal, long-lived versions of the same Baby App product. Both implementations live in one GitHub repository, can be built and tested independently, and share product-level documentation without sharing framework-specific source code.

## Current State

- The React Native implementation is on `feature/rn` and is currently the repository's GitHub default branch.
- The Flutter implementation is on `feature/baby-growth-timeline-flutter` in a linked worktree.
- Long-lived branches currently distinguish implementations. This makes cross-version changes, documentation, CI, and releases harder to see and coordinate.
- The working tree contains unrelated local changes (`tsconfig.json` and `.DS_Store`); the migration must preserve and avoid committing them unless they are intentionally handled as part of a later migration step.

## Chosen Approach

Use one repository and one integration branch with two self-contained applications:

```text
baby-app/
├── apps/
│   ├── react-native/
│   └── flutter/
├── docs/
├── .github/workflows/
├── .gitignore
└── README.md
```

The alternatives considered were long-lived framework branches and two separate repositories. Long-lived branches hide divergence until merges and make shared changes awkward. Separate repositories provide stronger isolation but split product documentation, issue tracking, and coordinated delivery. Neither fits the goal as well as a monorepo.

## Application Boundaries

`apps/react-native` contains the complete React Native/Expo application, including JavaScript dependencies, native projects, source, tests, and framework configuration. Its commands run from that directory and do not depend on Flutter tooling.

`apps/flutter` contains the complete Flutter application, including Dart dependencies, native projects, source, tests, and framework configuration. Its commands run from that directory and do not depend on Node tooling.

No application imports source code from the other. Product behavior may be documented jointly, but implementation code remains framework-specific.

## Shared Repository Files

- The root `README.md` explains the two maintained implementations and links to setup, development, test, and build commands for each.
- Root `docs/` contains product requirements, parity notes, architecture decisions, and cross-version testing guidance.
- Root `.gitignore` covers repository-wide operating-system and editor artifacts; application-specific ignores remain inside each application where useful.
- GitHub workflows live at the root because GitHub only discovers workflows under `.github/workflows`.

Root-level dependency orchestration is intentionally omitted initially. Each application remains usable with its native toolchain. Small root convenience commands can be added later only if repeated maintenance justifies them.

## Source and History Migration

1. Start from the React Native integration state on `feature/rn`.
2. Move React Native project files into `apps/react-native` with Git-aware moves so history remains traceable.
3. Import the complete Flutter application tree from `feature/baby-growth-timeline-flutter` into `apps/flutter` without copying that branch's repository-level Git metadata or unrelated shared documentation.
4. Resolve root-file overlaps explicitly. The root README and ignore rules are authored for the monorepo; framework-specific versions move with their applications.
5. Preserve unrelated user modifications and do not include them in migration commits accidentally.

The old feature branches remain available until the monorepo has been verified and pushed. They can then be retained temporarily as migration references and deleted in a separate, explicit cleanup.

## Branch and GitHub Strategy

The completed monorepo is integrated into `main`. `main` becomes the GitHub default branch after it has been pushed and verified. Future work uses short-lived feature branches based on `main`; branch names describe product work, not framework choice.

A product change affecting both implementations should normally update both application directories in one pull request, making parity visible during review. Framework-specific fixes may touch only one directory.

## Continuous Integration

CI has independent jobs for React Native and Flutter:

- React Native job: install locked dependencies, run tests, and run the available type/lint checks from `apps/react-native`.
- Flutter job: restore locked dependencies, run analysis, and run tests from `apps/flutter`.
- Path filters may skip an unaffected application, but changes to shared documentation or workflow configuration should not incorrectly report application validation that did not run.

One application's failure does not prevent the other job from producing its result. Merging requires all applicable jobs to pass.

## Documentation and Parity

The root documentation identifies both applications as supported. A lightweight parity document records intentional differences, platform limitations, and the status of product features when implementations do not land simultaneously. It is descriptive rather than a generated source of truth.

## Error and Rollback Handling

- Perform migration in focused commits so structural moves and Flutter import can be inspected separately.
- Do not delete the original implementation branches during migration.
- If either application cannot be restored, built, or tested from its new directory, keep `main` unchanged and fix the migration branch before integration.
- Never solve a toolchain conflict by making one application depend on the other's package manager.

## Verification

The migration is complete when:

1. Both application directories contain their expected tracked files.
2. React Native dependency installation, tests, and type/lint checks pass from `apps/react-native`.
3. Flutter dependency restoration, analysis, and tests pass from `apps/flutter`.
4. Root documentation accurately describes setup and commands for both versions.
5. CI configuration validates the two applications independently.
6. No unrelated local changes were lost or accidentally committed.
7. `main` is pushed and set as the GitHub default branch only after the local migration is verified.

## Out of Scope

- Sharing runtime source code between Dart and TypeScript.
- Forcing identical UI implementation details where framework conventions differ.
- Combining Node and Flutter dependencies into one package manager.
- Deleting historical branches as part of the initial migration.
- Creating a shared backend or generated cross-language model layer.
