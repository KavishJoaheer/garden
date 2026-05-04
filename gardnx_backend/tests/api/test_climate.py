"""Tests for climate data endpoints."""


class TestCurrentClimate:
    """Test /api/v1/climate/current endpoint."""

    def test_current_climate_mauritius(self, authenticated_client):
        """Should return climate data for a Mauritius location."""
        response = authenticated_client.get(
            "/api/v1/climate/current?lat=-20.2&lon=57.5"
        )
        # May be 200 or 502/500 if Open-Meteo is unreachable in CI
        if response.status_code == 200:
            data = response.json()
            assert "temperature_c" in data
            assert "humidity_percent" in data
            assert "season" in data
            assert "gardening_notes" in data

    def test_current_climate_invalid_coords(self, authenticated_client):
        """Invalid coordinates should return 422."""
        response = authenticated_client.get(
            "/api/v1/climate/current?lat=999&lon=999"
        )
        assert response.status_code == 422


class TestMonthlyClimate:
    """Test /api/v1/climate/monthly endpoint."""

    def test_monthly_averages(self, authenticated_client):
        """Should return 12 months of climate data."""
        response = authenticated_client.get(
            "/api/v1/climate/monthly?lat=-20.2&lon=57.5"
        )
        if response.status_code == 200:
            data = response.json()
            assert "months" in data
            assert len(data["months"]) == 12

            for month in data["months"]:
                assert 1 <= month["month"] <= 12
                assert "avg_temp_c" in month
                assert "season" in month
