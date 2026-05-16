"""Shared dependencies for API endpoints.

This module provides the `get_current_user` dependency used by all
authenticated endpoints. It verifies Firebase ID tokens and supports
an anonymous development mode when ALLOW_ANON=true + DEBUG=true.
"""

import logging

from fastapi import Header

from app.config import settings
from app.errors import AuthorizationError, ModelNotLoadedError

logger = logging.getLogger("gardnx")


def _anon_or_raise(reason: str) -> str:
    """Return 'anonymous' when ALLOW_ANON is set; otherwise raise 401.

    Centralising this keeps every auth failure path behind the same gate.
    """
    if settings.allow_anon:
        logger.debug("allow_anon=true — returning anonymous (%s)", reason)
        return "anonymous"
    raise AuthorizationError(detail=f"Unauthorized: {reason}")


async def get_current_user(authorization: str | None = Header(None)) -> str:
    """Verify Firebase ID token and return user_id.

    When ``ALLOW_ANON=true`` (dev/local), any unauthenticated request is
    tagged ``anonymous``. In production (default) we raise 401.

    NOTE: We never decode JWTs manually. Either Firebase verifies them
    or we return anonymous in dev mode. No unsafe base64 decoding.
    """
    if not authorization or not authorization.startswith("Bearer "):
        return _anon_or_raise("missing bearer token")

    token = authorization.split("Bearer ", 1)[1].strip()
    if not token:
        return _anon_or_raise("empty bearer token")

    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth

        # If Firebase wasn't initialized, we can't verify tokens
        if not firebase_admin._apps:
            if not settings.allow_anon:
                raise AuthorizationError(
                    detail="Firebase not initialized — cannot verify token"
                )
            logger.warning(
                "Firebase not initialized; accepting request as anonymous (dev mode)"
            )
            return "anonymous"

        decoded_token = firebase_auth.verify_id_token(token, clock_skew_seconds=60)
        return decoded_token["uid"]

    except ImportError:
        return _anon_or_raise("firebase_admin not installed")
    except AuthorizationError:
        raise
    except Exception as e:
        logger.warning("Token verification failed: %s", e)
        return _anon_or_raise(f"token verification failed: {e}")


def get_analyzer():
    """Return the global GardenAnalyzer instance from app state."""
    from app.main import app

    analyzer = getattr(app.state, "analyzer", None)
    if analyzer is None:
        raise ModelNotLoadedError()
    return analyzer
