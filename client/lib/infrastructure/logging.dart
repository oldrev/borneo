import 'package:logger/logger.dart';

Logger createLogger() {
  return Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      excludeBox: const {Level.info: true},
      noBoxingByDefault: true,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
  );
}