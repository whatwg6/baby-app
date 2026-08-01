import 'package:baby_growth_timeline/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BabyTimelineApp extends StatelessWidget {
  const BabyTimelineApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '宝宝成长记',
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
