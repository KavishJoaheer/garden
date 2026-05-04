"""Tests for plant catalog and recommendation endpoints."""

import pytest


class TestPlantCatalog:
    """Test /api/v1/plants/catalog endpoint."""

    def test_catalog_returns_plants(self, authenticated_client):
        """Catalog should return a non-empty list of plants."""
        response = authenticated_client.get("/api/v1/plants/catalog")
        assert response.status_code == 200

        plants = response.json()
        assert isinstance(plants, list)
        assert len(plants) > 0

    def test_catalog_plant_has_required_fields(self, authenticated_client):
        """Each plant should have all required fields."""
        response = authenticated_client.get("/api/v1/plants/catalog")
        plant = response.json()[0]

        required_fields = ["id", "name", "type", "conditions", "spacing", "timing"]
        for field in required_fields:
            assert field in plant, f"Missing field: {field}"

    def test_catalog_filter_by_type(self, authenticated_client):
        """Filtering by type should return only matching plants."""
        response = authenticated_client.get("/api/v1/plants/catalog?type=herb")
        assert response.status_code == 200

        plants = response.json()
        for plant in plants:
            assert plant["type"] == "herb"

    def test_catalog_filter_by_sun(self, authenticated_client):
        """Filtering by sun requirement should return matching plants."""
        response = authenticated_client.get(
            "/api/v1/plants/catalog?sun=full_sun"
        )
        assert response.status_code == 200

        plants = response.json()
        for plant in plants:
            assert plant["conditions"]["sunlight"] == "full_sun"

    def test_catalog_search(self, authenticated_client):
        """Search should filter by plant name."""
        response = authenticated_client.get(
            "/api/v1/plants/catalog?search=basil"
        )
        assert response.status_code == 200

        plants = response.json()
        assert len(plants) >= 1
        assert any("basil" in p["name"].lower() for p in plants)


class TestPlantDetail:
    """Test /api/v1/plants/{plant_id} endpoint."""

    def test_get_existing_plant(self, authenticated_client):
        """Getting a valid plant should return 200 with full data."""
        # First get a valid plant ID from the catalog
        catalog = authenticated_client.get("/api/v1/plants/catalog").json()
        plant_id = catalog[0]["id"]

        response = authenticated_client.get(f"/api/v1/plants/{plant_id}")
        assert response.status_code == 200
        assert response.json()["id"] == plant_id

    def test_get_nonexistent_plant_returns_404(self, authenticated_client):
        """Getting a non-existent plant should return 404."""
        response = authenticated_client.get("/api/v1/plants/nonexistent_xyz")
        assert response.status_code == 404


class TestPlantRecommendations:
    """Test /api/v1/plants/recommend endpoint."""

    def test_recommend_returns_results(self, authenticated_client):
        """Recommendations should return scored results."""
        response = authenticated_client.post(
            "/api/v1/plants/recommend",
            json={
                "bed_sunlight": "full_sun",
                "bed_soil_type": "loamy",
                "month": 3,
                "region": "north",
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "recommendations" in data
        assert "engine_used" in data
        assert len(data["recommendations"]) > 0

    def test_recommend_scores_are_valid(self, authenticated_client):
        """All recommendation scores should be between 0 and 1."""
        response = authenticated_client.post(
            "/api/v1/plants/recommend",
            json={
                "bed_sunlight": "partial_shade",
                "month": 6,
                "region": "south",
            },
        )
        data = response.json()

        for rec in data["recommendations"]:
            assert 0.0 <= rec["score"] <= 1.0
            assert len(rec["reasons"]) > 0

    def test_recommend_with_preferences(self, authenticated_client):
        """Recommendations should accept user preferences."""
        response = authenticated_client.post(
            "/api/v1/plants/recommend",
            json={
                "bed_sunlight": "full_sun",
                "month": 1,
                "region": "north",
                "preferences": ["vegetables", "fast_growing"],
                "experience_level": "beginner",
            },
        )
        assert response.status_code == 200

    def test_recommend_invalid_month_returns_422(self, authenticated_client):
        """Month outside 1-12 should return 422 validation error."""
        response = authenticated_client.post(
            "/api/v1/plants/recommend",
            json={
                "bed_sunlight": "full_sun",
                "month": 13,
                "region": "north",
            },
        )
        assert response.status_code == 422


class TestEngineStatus:
    """Test /api/v1/plants/engine-status endpoint."""

    def test_engine_status_returns_all_engines(self, authenticated_client):
        """Should return status for gemini, ollama, and rules."""
        response = authenticated_client.get("/api/v1/plants/engine-status")
        assert response.status_code == 200

        data = response.json()
        assert "gemini" in data
        assert "ollama" in data
        assert "rules" in data
        # Rules engine is always available
        assert data["rules"]["available"] is True
