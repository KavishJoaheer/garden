"""Structured logging configuration for the GardNx backend.

- DEBUG=true  → human-readable colored output for development
- DEBUG=false → JSON-formatted log lines for production (parseable by ELK, Datadog, etc.)
"""

import logging
import logging.config
import sys
from typing import Any


def setup_logging(*, debug: bool = True, log_level: str | None = None) -> None:
    """Configure the root and 'gardnx' loggers.

    Parameters
    ----------
    debug : bool
        When True, uses a human-readable formatter on stderr.
        When False, uses a structured JSON formatter.
    log_level : str | None
        Override log level (e.g. "DEBUG", "INFO", "WARNING").
        Defaults to DEBUG when debug=True, INFO otherwise.
    """
    level = log_level or ("DEBUG" if debug else "INFO")

    if debug:
        fmt = "%(asctime)s │ %(levelname)-7s │ %(name)s │ %(message)s"
        datefmt = "%H:%M:%S"
    else:
        # Structured key=value format that's easy to parse without extra deps
        fmt = (
            '{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s",'
            '"message":"%(message)s"}'
        )
        datefmt = "%Y-%m-%dT%H:%M:%S%z"

    config: dict[str, Any] = {
        "version": 1,
        "disable_existing_loggers": False,
        "formatters": {
            "default": {
                "format": fmt,
                "datefmt": datefmt,
            },
        },
        "handlers": {
            "console": {
                "class": "logging.StreamHandler",
                "stream": "ext://sys.stderr",
                "formatter": "default",
            },
        },
        "loggers": {
            "gardnx": {
                "level": level,
                "handlers": ["console"],
                "propagate": False,
            },
            "uvicorn": {
                "level": level,
                "handlers": ["console"],
                "propagate": False,
            },
            "uvicorn.access": {
                "level": "WARNING",
                "handlers": ["console"],
                "propagate": False,
            },
        },
        "root": {
            "level": "WARNING",
            "handlers": ["console"],
        },
    }

    logging.config.dictConfig(config)
