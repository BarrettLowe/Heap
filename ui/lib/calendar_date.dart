class CalendarDate implements Comparable<CalendarDate> {
  CalendarDate(int year, int month, int day)
    : year = year,
      month = month,
      day = day {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      throw const FormatException('Invalid calendar date.');
    }
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw const FormatException('Invalid calendar date.');
    }
  }

  final int year;
  final int month;
  final int day;

  factory CalendarDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('Invalid canonical calendar date.');
    }
    return CalendarDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }

  factory CalendarDate.fromLocalDate(DateTime value) =>
      CalendarDate(value.year, value.month, value.day);

  DateTime toLocalDate() => DateTime(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  int compareTo(CalendarDate other) {
    final yearOrder = year.compareTo(other.year);
    if (yearOrder != 0) return yearOrder;
    final monthOrder = month.compareTo(other.month);
    return monthOrder != 0 ? monthOrder : day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}
