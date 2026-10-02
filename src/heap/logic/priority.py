from enum import IntEnum


class Priority(IntEnum):
    """Manual importance levels; P1 is highest, not a numeric ranking weight."""

    P1 = 1
    P2 = 2
    P3 = 3
    P4 = 4
    P5 = 5

    @property
    def label(self) -> str:
        """Return the descriptive label for this importance level."""
        return {
            Priority.P1: "Critical",
            Priority.P2: "Important",
            Priority.P3: "Normal",
            Priority.P4: "Someday",
            Priority.P5: "Maybe",
        }[self]
