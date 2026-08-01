import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/router.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(ProviderScope(child: BabyTimelineApp(router: createRouter())));
}
