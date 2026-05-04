"""Tests for health check endpoints."""


class TestHealthCheck:
    """Test the /health, /health/ready, and /health/live endpoints."""

    def test_health_returns_200(self, test_client):
        """Basic health check should always return 200."""
        response = test_client.get("/health")
        assert response.status_code == 200

        data = response.json()
        assert data["status"] == "ok"
        assert "version" in data
        assert "model_loaded" in data
        assert "mock_mode" in data

    def test_liveness_returns_200(self, test_client):
        """/health/live should always return 200 (Kubernetes liveness probe)."""
        response = test_client.get("/health/live")
        assert response.status_code == 200
        assert response.json()["status"] == "alive"

    def test_readiness_check(self, test_client):
        """/health/ready should return 200 or 503 depending on service state."""
        response = test_client.get("/health/ready")
        # In test environment without Firebase, may be 503
        assert response.status_code in (200, 503)
        data = response.json()
        assert "status" in data

    def test_health_includes_request_id(self, test_client):
        """All responses should include X-Request-ID header."""
        response = test_client.get("/health")
        assert "X-Request-ID" in response.headers

    def test_health_includes_security_headers(self, test_client):
        """All responses should include security headers."""
        response = test_client.get("/health")
        assert response.headers.get("X-Content-Type-Options") == "nosniff"
        assert response.headers.get("X-Frame-Options") == "DENY"
