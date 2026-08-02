import 'dart:async';

import 'package:baby_growth_timeline/domain/models/baby.dart';
import 'package:baby_growth_timeline/features/baby/presentation/baby_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpForm(
    WidgetTester tester, {
    Baby? initialValue,
    required Future<void> Function(BabyDraft draft) onSave,
    DateTime? now,
    Future<DateTime?> Function(BuildContext, DateTime, DateTime)?
    selectBirthDate,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BabyForm(
            initialValue: initialValue,
            onSave: onSave,
            now: () => now ?? DateTime(2026, 7, 15),
            selectBirthDate: selectBirthDate,
          ),
        ),
      ),
    );
  }

  testWidgets('saves a valid profile draft', (tester) async {
    BabyDraft? saved;
    await pumpForm(tester, onSave: (draft) async => saved = draft);

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(saved, const BabyDraft(name: '安安', birthDate: '2025-06-15'));
  });

  testWidgets('selects an optional sex when creating a profile', (
    tester,
  ) async {
    BabyDraft? saved;
    await pumpForm(tester, onSave: (draft) async => saved = draft);

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.byKey(const Key('baby-sex')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('女').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      saved,
      const BabyDraft(name: '安安', birthDate: '2025-06-15', sex: '女'),
    );
  });

  testWidgets('shows an error below the name when it is empty', (tester) async {
    await pumpForm(tester, onSave: (_) async {});

    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请输入宝宝姓名。'), findsOneWidget);
  });

  testWidgets('shows an error below a future birthday', (tester) async {
    await pumpForm(tester, onSave: (_) async {});

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2026-07-16');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('生日不能晚于今天。'), findsOneWidget);
  });

  testWidgets('prefills the fields when editing a baby', (tester) async {
    final baby = Baby(
      id: 'baby-1',
      name: '乐乐',
      birthDate: '2025-06-15',
      createdAt: DateTime.utc(2025, 6, 15),
      updatedAt: DateTime.utc(2025, 6, 15),
    );
    await pumpForm(tester, initialValue: baby, onSave: (_) async {});

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('baby-name')))
          .controller!
          .text,
      '乐乐',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('birth-date')))
          .controller!
          .text,
      '2025-06-15',
    );
  });

  testWidgets('prefills and modifies sex when editing a baby', (tester) async {
    BabyDraft? saved;
    final baby = Baby(
      id: 'baby-1',
      name: '乐乐',
      birthDate: '2025-06-15',
      sex: '女',
      createdAt: DateTime.utc(2025, 6, 15),
      updatedAt: DateTime.utc(2025, 6, 15),
    );
    await pumpForm(
      tester,
      initialValue: baby,
      onSave: (draft) async => saved = draft,
    );

    expect(
      tester
          .widget<DropdownButton<String>>(
            find.descendant(
              of: find.byKey(const Key('baby-sex')),
              matching: find.byType(DropdownButton<String>),
            ),
          )
          .value,
      '女',
    );
    await tester.tap(find.byKey(const Key('baby-sex')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('男').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(saved?.sex, '男');
  });

  testWidgets('clears an existing optional sex', (tester) async {
    BabyDraft? saved;
    final baby = Baby(
      id: 'baby-1',
      name: '乐乐',
      birthDate: '2025-06-15',
      sex: '女',
      createdAt: DateTime.utc(2025, 6, 15),
      updatedAt: DateTime.utc(2025, 6, 15),
    );
    await pumpForm(
      tester,
      initialValue: baby,
      onSave: (draft) async => saved = draft,
    );

    await tester.tap(find.byKey(const Key('baby-sex')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不填写').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(saved, isNotNull);
    expect(saved!.sex, isNull);
  });

  testWidgets('retains entered values when saving fails', (tester) async {
    await pumpForm(
      tester,
      onSave: (_) => Future<void>.error(StateError('save failed')),
    );

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('baby-name')))
          .controller!
          .text,
      '安安',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('birth-date')))
          .controller!
          .text,
      '2025-06-15',
    );
    expect(find.text('保存失败，请稍后重试。'), findsOneWidget);
  });

  testWidgets('disables save while a profile save is in progress', (
    tester,
  ) async {
    final saveCompleter = Completer<void>();
    await pumpForm(tester, onSave: (_) => saveCompleter.future);

    await tester.enterText(find.byKey(const Key('baby-name')), '安安');
    await tester.enterText(find.byKey(const Key('birth-date')), '2025-06-15');
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    saveCompleter.complete();
    await tester.pump();
  });

  testWidgets('uses the injected birthday selector', (tester) async {
    DateTime? initialDate;
    await pumpForm(
      tester,
      onSave: (_) async {},
      selectBirthDate: (context, initial, last) async {
        initialDate = initial;
        return DateTime(2025, 6, 15);
      },
    );

    await tester.tap(find.byTooltip('选择生日'));
    await tester.pump();

    expect(initialDate, DateTime(2026, 7, 15));
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('birth-date')))
          .controller!
          .text,
      '2025-06-15',
    );
  });
}
