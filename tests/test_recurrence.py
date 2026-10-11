from datetime import date

import pytest

from heap.logic.recurrence import RepeatRule, RepeatUnit


@pytest.mark.parametrize(
    ("unit", "interval", "completed_on", "expected"),
    [
        (RepeatUnit.DAYS, 14, date(2026, 10, 5), date(2026, 10, 19)),
        (RepeatUnit.MONTHS, 1, date(2025, 1, 31), date(2025, 2, 28)),
        (RepeatUnit.MONTHS, 1, date(2024, 1, 31), date(2024, 2, 29)),
        (RepeatUnit.MONTHS, 1, date(2025, 2, 28), date(2025, 3, 28)),
        (RepeatUnit.MONTHS, 12, date(2025, 12, 31), date(2026, 12, 31)),
    ],
)
def test_repeat_rule_calculates_from_completion_calendar_date(
    unit: RepeatUnit, interval: int, completed_on: date, expected: date
) -> None:
    """Calculate day and clamped-month intervals from the completion date."""
    rule = RepeatRule(unit=unit, interval=interval)
    assert rule.next_due_date(completed_on) == expected


@pytest.mark.parametrize("interval", [0, -1, True, 1.5, "2"])
def test_repeat_rule_rejects_non_positive_or_non_integer_intervals(interval: object) -> None:
    """Reject non-positive and non-strict integer intervals in the domain."""
    with pytest.raises(ValueError):
        RepeatRule(unit=RepeatUnit.DAYS, interval=interval)


def test_repeat_rule_decimal_round_trip_exceeds_python_digit_conversion_limit() -> None:
    """Parse and format huge intervals without a whole-number digit cutoff."""
    decimal = "9876543210" * 500
    rule = RepeatRule(
        unit=RepeatUnit.DAYS,
        interval=RepeatRule.parse_interval(decimal),
    )
    assert rule.interval_as_decimal() == decimal


def test_repeat_rule_rejects_unrepresentable_calendar_result() -> None:
    """Report a date-range error when addition exceeds Python's calendar range."""
    with pytest.raises(ValueError, match="Repeat"):
        RepeatRule(unit=RepeatUnit.DAYS, interval=10**100).next_due_date(
            date.max
        )
