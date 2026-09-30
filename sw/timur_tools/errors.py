"""Errors the Timur tools report to the user."""


class TimurError(Exception):
    """A failure with a message for the user.

    Library code raises it (or a subclass); only the command-line entry points
    turn it into one line on stderr and exit status 1 (see cli.run).
    """


class GenerationError(TimurError):
    """A generator found that its inputs, the model and the expectations disagree."""
