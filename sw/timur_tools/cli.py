"""What the command-line entry points in sw/ share.

Every script has a ``main(argv) -> int`` that parses its arguments, does its
work and lets TimurError propagate; ``run`` turns such an error into one line
on stderr and exit status 1. Results go to stdout, diagnostics to stderr
through the ``timur`` logger.
"""

from __future__ import annotations

import argparse
import logging
import sys
from collections.abc import Callable, Sequence

from .errors import TimurError
from .paths import ENV_ROOT, Project

LOG = logging.getLogger("timur")

Main = Callable[[Sequence[str] | None], int]

EXIT_FAILURE = 1


def run(main: Main, prog: str, argv: Sequence[str] | None = None) -> int:
    """Call main; report a TimurError or a file error as '<prog>: <message>'."""
    try:
        return main(argv)
    except (TimurError, OSError) as error:
        print("%s: %s" % (prog, error), file=sys.stderr)
        return EXIT_FAILURE


def configure_logging(verbose: bool = False) -> None:
    """Diagnostics to stderr: INFO and above, or DEBUG (commands run) if verbose."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(message)s",
        stream=sys.stderr,
    )
    LOG.setLevel(logging.DEBUG if verbose else logging.INFO)


def add_common_arguments(parser: argparse.ArgumentParser, root: bool = True) -> None:
    """--verbose, and --root for the scripts that read and write a project tree."""
    if root:
        parser.add_argument(
            "--root",
            metavar="DIR",
            help="project directory (default: $%s, or the project this script is in)" % ENV_ROOT,
        )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="also print the commands that are run"
    )


def project_from(args: argparse.Namespace) -> Project:
    """The project selected by --root; also sets up logging."""
    configure_logging(args.verbose)
    return Project.at(args.root)


def positive_int(text: str) -> int:
    """argparse type: an integer greater than zero."""
    try:
        value = int(text, 0)
    except ValueError:
        raise argparse.ArgumentTypeError("%r is not a number" % text) from None
    if value <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero, not %d" % value)
    return value
