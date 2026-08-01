import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../application/baby_controller.dart';
import 'baby_form.dart';

class BabySetupPage extends StatelessWidget {
  const BabySetupPage({super.key, required this.controller});

  final BabyController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.state.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('添加宝宝资料')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BabyForm(
                onSave: controller.save,
                onSaved: () async {
                  if (context.mounted) {
                    context.go('/timeline');
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
