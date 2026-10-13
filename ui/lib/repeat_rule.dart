class RepeatRule {
  RepeatRule({required this.unit, required this.interval}) {
    if ((unit != 'days' && unit != 'months') ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(interval)) {
      throw ArgumentError(
        'Repeat rule must have a unit and canonical interval.',
      );
    }
  }

  final String unit;
  final String interval;

  factory RepeatRule.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().length != 2 ||
        !value.keys.toSet().containsAll({'unit', 'interval'})) {
      throw const FormatException('Invalid repeat rule.');
    }
    final unit = value['unit'];
    final interval = value['interval'];
    if ((unit != 'days' && unit != 'months') ||
        interval is! String ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(interval)) {
      throw const FormatException('Invalid repeat rule.');
    }
    return RepeatRule(unit: unit as String, interval: interval);
  }

  Map<String, Object?> toJson() => {'unit': unit, 'interval': interval};

  @override
  bool operator ==(Object other) =>
      other is RepeatRule && other.unit == unit && other.interval == interval;

  @override
  int get hashCode => Object.hash(unit, interval);
}
