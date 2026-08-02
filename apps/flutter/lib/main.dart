import 'package:baby_growth_timeline/app/app.dart';
import 'package:baby_growth_timeline/app/bootstrap.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final debugLogger = LocalDebugLogger();
  installLocalFlutterErrorLogging(debugLogger);
  runApp(
    BabyTimelineBootstrap(
      bootstrap: () =>
          bootstrapApp(LocalBootstrapEnvironment(debugLogger: debugLogger)),
    ),
  );
}
