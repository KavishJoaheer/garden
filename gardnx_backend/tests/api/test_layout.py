"""Tests for layout generation and validation endpoints."""

import pytest


class TestLayoutGeneration:
    """Test /api/v1/layout/generate endpoint."""

    def test_generate_basic_layout(self, authenticated_client, sample_layout_request):
        """Should generate a valid layout with placements."""
        response = authenticated_client.post(
            "/api/v1/layout/generate",
            json=sample_layout_request,
        )
        assert response.status_code == 200

        data = response.json()
        assert "placements" in data
        assert "grid" in data
        assert "statistics" in data
        assert "warnings" in data
        assert "bed" in data

    def test_generate_layout_statistics(self, authenticated_client, sample_layout_request):
        """Layout statistics should have valid values."""
        response = authenticated_client.post(
            "/api/v1/layout/generate",
            json=sample_layout_request,
        )
        stats = response.json()["statistics"]

        assert stats["total_cells"] > 0
        assert stats["occupied_cells"] >= 0
        assert 0 <= stats["utilization_percent"] <= 100
        assert stats["grid_rows"] > 0
        assert stats["grid_cols"] > 0
        assert stats["cell_size_cm"] > 0

    def test_generate_empty_plant_list(self, authenticated_client, sample_bed):
        """Empty plant list should return empty layout without error."""
        response = authenticated_client.post(
            "/api/v1/layout/generate",
            json={
                "bed": sample_bed,
                "plants": [],
                "use_companion_rules": True,
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert len(data["placements"]) == 0

    def test_generate_invalid_bed_dimensions(self, authenticated_client):
        """Zero or negative bed dimensions should return 422."""
        response = authenticated_client.post(
            "/api/v1/layout/generate",
            json={
                "bed": {
                    "width_cm": 0,
                    "height_cm": -10,
                },
                "plants": [],
            },
        )
        assert response.status_code == 422


class TestSpacingCalculation:
    """Test /api/v1/layout/spacing endpoint."""

    def test_spacing_calculation(self, authenticated_client):
        """Should calculate max plants correctly."""
        response = authenticated_client.post(
            "/api/v1/layout/spacing",
            json={
                "bed_width_cm": 200,
                "bed_height_cm": 300,
                "between_plants_cm": 30,
                "between_rows_cm": 40,
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert data["max_plants"] > 0
        assert data["rows"] > 0
        assert data["cols"] > 0
        assert 0 <= data["bed_utilization_percent"] <= 100


class TestBedRecommendation:
    """Test /api/v1/layout/recommend endpoint."""

    def test_recommend_for_bed(self, authenticated_client):
        """Should return plant suggestions for a bed."""
        response = authenticated_client.post(
            "/api/v1/layout/recommend",
            json={
                "width_cm": 200,
                "height_cm": 300,
                "sun_exposure": "full_sun",
                "soil_type": "loamy",
                "season": "summer",
                "region": "north",
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "recommendations" in data
        assert "engine_used" in data
        assert len(data["recommendations"]) > 0

    def test_recommend_suggestions_have_required_fields(self, authenticated_client):
        """Each suggestion should have all required fields."""
        response = authenticated_client.post(
            "/api/v1/layout/recommend",
            json={
                "width_cm": 150,
                "height_cm": 150,
                "sun_exposure": "partial_shade",
                "season": "winter",
                "region": "south",
            },
        )
        suggestions = response.json()["recommendations"]

        for s in suggestions[:3]:  # Check first 3
            assert "plant_id" in s
            assert "plant_name" in s
            assert "suitability_score" in s
            assert "reasons" in s
            assert "max_count" in s
