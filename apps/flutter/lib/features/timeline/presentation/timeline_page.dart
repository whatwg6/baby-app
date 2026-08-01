import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/date/timeline_grouping.dart';
import '../../../domain/models/baby.dart';
import '../application/timeline_controller.dart';
import '../../baby/presentation/baby_header.dart';
import 'timeline_filters.dart';
import 'timeline_section.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.hasBaby,
    this.controller,
    this.baby,
    this.now,
  });

  final bool hasBaby;
  final TimelineController? controller;
  final Baby? baby;
  final DateTime Function()? now;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  @override
  void initState() {
    super.initState();
    widget.controller?.load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return _EmptyTimeline(hasBaby: widget.hasBaby);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _TimelineContent(
        controller: controller,
        hasBaby: widget.hasBaby,
        baby: widget.baby,
        now: widget.now ?? DateTime.now,
      ),
    );
  }
}

class _TimelineContent extends StatelessWidget {
  const _TimelineContent({
    required this.controller,
    required this.hasBaby,
    required this.baby,
    required this.now,
  });

  final TimelineController controller;
  final bool hasBaby;
  final Baby? baby;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final groups = groupRecordsByLocalDay(state.records);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: controller.reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (baby != null) ...[
              BabyHeader(baby: baby!, now: now),
              const SizedBox(height: 16),
            ],
            TimelineFilters(
              selectedTypes: state.selectedTypes,
              onToggle: controller.toggleType,
              onClear: controller.clearFilters,
            ),
            if (state.errorMessage != null) ...[
              const SizedBox(height: 12),
              _ReadError(onRetry: controller.reload),
            ],
            if (state.isLoading && state.records.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: _EmptyTimeline(hasBaby: hasBaby),
              )
            else
              for (final group in groups)
                TimelineSection(
                  group: group,
                  label: timelineDayLabel(group.key, now()),
                  onRecordTap: (id) => context.push('/records/$id'),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReadError extends StatelessWidget {
  const _ReadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(child: Text('无法读取记录，请重试')),
      TextButton(onPressed: onRetry, child: const Text('重试')),
    ],
  );
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.hasBaby});

  final bool hasBaby;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome_outlined, size: 48),
            const SizedBox(height: 16),
            const Text('还没有成长记录'),
            const SizedBox(height: 8),
            Text(
              hasBaby ? '从第一个瞬间开始记录吧。' : '先添加宝宝资料，再记录第一个瞬间。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.go('/add'),
              child: const Text('记录第一个瞬间'),
            ),
          ],
        ),
      ),
    ),
  );
}

String timelineDayLabel(String dayKey, DateTime now) {
  final day = DateTime.parse(dayKey);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (day == today) return '今天';
  if (day == yesterday) return '昨天';
  return '${day.year}年${day.month}月${day.day}日';
}
