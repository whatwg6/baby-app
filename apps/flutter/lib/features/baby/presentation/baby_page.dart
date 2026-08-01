import 'package:flutter/material.dart';

import '../../backup/presentation/backup_actions.dart';
import '../application/baby_controller.dart';
import 'baby_form.dart';
import 'baby_header.dart';

class BabyPage extends StatefulWidget {
  const BabyPage({super.key, this.controller, this.onClearAllData});

  final BabyController? controller;
  final Future<void> Function()? onClearAllData;

  @override
  State<BabyPage> createState() => _BabyPageState();
}

class _BabyPageState extends State<BabyPage> {
  var _editing = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Center(child: Text('宝宝资料')),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildProfile(context, controller),
    );
  }

  Widget _buildProfile(BuildContext context, BabyController controller) {
    final baby = controller.baby;
    if (controller.state.isLoading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    if (baby == null) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Center(child: Text('请先添加宝宝资料')),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          children: [
            BabyHeader(baby: baby),
            const SizedBox(height: 24),
            if (_editing)
              BabyForm(
                initialValue: baby,
                onSave: controller.save,
                onSaved: () async {
                  if (mounted) {
                    setState(() => _editing = false);
                  }
                },
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _editing = true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('编辑资料'),
                  ),
                  if (widget.onClearAllData != null) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _confirmClear(context, baby.name),
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: const Text('清空所有数据'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, String babyName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ClearDataDialog(babyName: babyName),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onClearAllData!();
    } catch (error) {
      if (mounted && context.mounted) {
        final message = error is ClearAllDataCleanupException
            ? error.toString()
            : '清空失败，请稍后重试';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

class _ClearDataDialog extends StatefulWidget {
  const _ClearDataDialog({required this.babyName});

  final String babyName;

  @override
  State<_ClearDataDialog> createState() => _ClearDataDialogState();
}

class _ClearDataDialogState extends State<_ClearDataDialog> {
  final _nameController = TextEditingController();
  var _matches = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('清空所有数据'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('将删除宝宝资料、全部记录和媒体，此操作无法撤销'),
        const SizedBox(height: 16),
        Text('请输入宝宝姓名“${widget.babyName}”以确认'),
        const SizedBox(height: 8),
        TextField(
          key: const Key('clear-baby-name'),
          controller: _nameController,
          onChanged: (value) =>
              setState(() => _matches = value == widget.babyName),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _matches ? () => Navigator.pop(context, true) : null,
        child: const Text('确认清空'),
      ),
    ],
  );
}
