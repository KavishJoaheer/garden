"""Shared dependencies for API endpoints."""

import logging
from typing import Optional

from fastapi import Header, HTTPException

from app.config import settings

logger = logging.getLogger("gardnx")


def _anon_or_401(reason: str) -> str:
    """Return 'anonymous' when ALLOW_ANON is set; otherwise raise 401.

    Centralising this keeps every auth failure path behind the same gate.
    """
    if settings.allow_anon:
        logger.debug("allow_anon=true — returning anonymous (%s)", reason)
        return "anonymous"
    raise HTTPException(status_code=401, detail=f"Unauthorized: {reason}")


async def get_current_user(authorization: Optional[str] = Header(None)) -> str:
    """Verify Firebase ID token and return user_id.

    When `ALLOW_ANON=true` (dev/local), any unauthenticated or unverifiable
    request is tagged `anonymous`. In production (default) we raise 401.
    """
    if not authorization or not authorization.startswith("Bearer "):
        return _anon_or_401("missing bearer token")

    token = authorization.split("Bearer ")[1]
    try:
        import firebase_admin
        from firebase_admin import auth as firebase_auth

        # If Firebase wasn't initialized (no credentials file), skip verification
        if not firebase_admin._apps:
            if not settings.allow_anon:
                raise HTTPException(
                    status_code=503,
                    detail="Firebase not initialised — cannot verify token",
                )
            logger.warning("Firebase not initialised; decoding token unsafely for dev")
            import base64
            import json
            payload_b64 = token.split(".")[1]
            payload_b64 += "=" * (4 - len(payload_b64) % 4)
            payload = json.loads(base64.urlsafe_b64decode(payload_b64))
            return payload.get("user_id") or payload.get("sub") or "anonymous"

        decoded_token = firebase_auth.verify_id_token(token)
        return decoded_token["uid"]
    except ImportError:
        return _anon_or_401("firebase_admin not installed")
    except HTTPException:
        raise
    except Exception as e:
        logger.warning("Token verification failed: %s", e)
        return _anon_or_401(f"token verification failed: {e}")


def get_analyzer():
    """Return the global GardenAnalyzer instance from app state."""
    from app.main import app_state

    analyzer = app_state.get("model")
    if analyzer is None:
        raise HTTPException(status_code=503, detail="Model not loaded yet")
    return analyzer
