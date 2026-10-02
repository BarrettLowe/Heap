from enum import Enum


class Duration(Enum):
    """Fixed duration estimates; unknown means the task still needs clarification."""

    UNKNOWN = None
    FIVE_MINUTES = 5
    FIFTEEN_MINUTES = 15
    THIRTY_MINUTES = 30
    ONE_HOUR = 60
    TWO_HOURS = 120
    FOUR_HOURS = 240

    @property
    def minutes(self) -> int | None:
        """Return the estimate in minutes, or None when it is unknown."""
        return self.value
