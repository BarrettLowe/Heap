from __future__ import annotations

import calendar
import re
from dataclasses import dataclass
from datetime import date, timedelta
from enum import StrEnum


_DECIMAL_CHUNK_WIDTH: int = 100
_CANONICAL_POSITIVE_INTEGER: re.Pattern[str] = re.compile(r"[1-9][0-9]*")


class RepeatDateOverflowError(ValueError):
    """Report when a repeat rule produces a date outside Python's range."""


class RepeatUnit(StrEnum):
    """Calendar units supported by completion-based repeat rules."""

    DAYS = "days"
    MONTHS = "months"


@dataclass(frozen=True)
class RepeatRule:
    """Describe a positive whole-number repeat interval."""

    unit: RepeatUnit
    interval: int

    def __post_init__(self) -> None:
        """Reject unsupported units and intervals that are not strict integers."""
        if not isinstance(self.unit, RepeatUnit):
            try:
                object.__setattr__(self, "unit", RepeatUnit(self.unit))
            except (TypeError, ValueError) as error:
                raise ValueError("Repeat unit must be days or months") from error
        if type(self.interval) is not int or self.interval <= 0:
            raise ValueError("Repeat interval must be a positive integer")

    @staticmethod
    def parse_interval(value: str) -> int:
        """Parse canonical digits in 100-digit chunks below Python's conversion limit."""
        if (
            not isinstance(value, str)
            or _CANONICAL_POSITIVE_INTEGER.fullmatch(value) is None
        ):
            raise ValueError(
                "Repeat interval must be a canonical positive integer string"
            )
        interval = 0
        for start in range(0, len(value), _DECIMAL_CHUNK_WIDTH):
            chunk = value[start : start + _DECIMAL_CHUNK_WIDTH]
            interval = interval * (10 ** len(chunk)) + int(chunk)
        return interval

    def interval_as_decimal(self) -> str:
        """Format using 100-digit chunks below Python's whole-integer digit limit."""
        chunks: list[int] = []
        remaining = self.interval
        base = 10 ** _DECIMAL_CHUNK_WIDTH
        while remaining:
            remaining, chunk = divmod(remaining, base)
            chunks.append(chunk)
        return str(chunks[-1]) + "".join(
            f"{chunk:0{_DECIMAL_CHUNK_WIDTH}d}" for chunk in reversed(chunks[:-1])
        )

    def next_due_date(self, completed_on: date) -> date:
        """Calculate the next calendar date from the actual completion date."""
        try:
            if self.unit is RepeatUnit.DAYS:
                return completed_on + timedelta(days=self.interval)
            month_index = (
                completed_on.year * 12 + completed_on.month - 1 + self.interval
            )
            year, month_index = divmod(month_index, 12)
            month = month_index + 1
            day = min(
                completed_on.day, calendar.monthrange(year, month)[1]
            )
            return date(year, month, day)
        except (OverflowError, ValueError) as error:
            raise RepeatDateOverflowError(
                "Repeat result is outside the supported date range"
            ) from error
