/// Returns a Chinese age label calculated from natural calendar months.
String calculateAgeLabel(DateTime birthDate, DateTime now) {
  final birth = birthDate.toLocal();
  final current = now.toLocal();
  final birthDay = DateTime(birth.year, birth.month, birth.day);
  final currentDay = DateTime(current.year, current.month, current.day);

  var totalMonths =
      (currentDay.year - birthDay.year) * 12 +
      currentDay.month -
      birthDay.month;
  if (currentDay.day < birthDay.day) {
    totalMonths -= 1;
  }

  if (totalMonths < 1) {
    final days = currentDay.difference(birthDay).inDays;
    return '${days < 0 ? 0 : days}天';
  }

  final years = totalMonths ~/ 12;
  final months = totalMonths % 12;
  if (years == 0) {
    return '$months个月';
  }
  return '$years岁$months个月';
}
