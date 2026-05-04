"""Shared test fixtures for the GardNx backend test suite.

Provides:
- test_client: A FastAPI TestClient with Firebase mocked out
- authenticated_client: A test client with a pre-authenticated user
- sample data fixtures for plants, beds, etc.
"""

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.main import app


# ── Auth override ─────────────────────────────────────────────────────────

TEST_USER_ID = "test-user-001"


async def _mock_current_user() -> str:
    """Return a fixed test user ID for all authenticated endpoints."""
    return TEST_USER_ID


# ── TestClient fixtures ──────────────────────────────────────────────────


@pytest.fixture
def test_client():
    """Unauthenticated test client with Firebase mocked."""
    # Override the user dependency so we don't need real Firebase tokens
    app.dependency_overrides[get_current_user] = _mock_current_user

    with TestClient(app, raise_server_exceptions=False) as client:
        yield client

    app.dependency_overrides.clear()


@pytest.fixture
def authenticated_client(test_client):
    """Test client pre-configured with auth header (same as test_client since
    we override the dependency, but semantically clearer in test names)."""
    test_client.headers["Authorization"] = "Bearer test-token-123"
    return test_client


# ── Sample data fixtures ─────────────────────────────────────────────────


@pytest.fixture
def sample_bed():
    """A standard garden bed for layout tests."""
    return {
        "width_cm": 200,
        "height_cm": 300,
        "sun_exposure": "full_sun",
        "soil_type": "loamy",
    }


@pytest.fixture
def sample_plants():
    """A few plant IDs known to exist in the Mauritius catalog."""
    return [
        {"plant_id": "basil", "quantity": 3, "priority": 1},
        {"plant_id": "tomato", "quantity": 2, "priority": 2},
    ]


@pytest.fixture
def sample_layout_request(sample_bed, sample_plants):
    """A complete layout generation request."""
    return {
        "bed": sample_bed,
        "plants": sample_plants,
        "use_companion_rules": True,
    }
