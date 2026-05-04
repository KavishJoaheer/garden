"""Tests for calendar and task generation endpoints."""

import pytest


class TestCalendarGeneration:
    """Test /api/v1/calendar/generate endpoint."""

    def test_generate_calendar_basic(self, authenticated_client):
        """Should generate calendar events from plant data."""
        response = authenticated_client.post(
            "/api/v1/calendar/generate",
            json={
                "plants": [
                    {
                        "plant_id": "basil",
                        "plant_name": "Basil",
                        "bed_name": "Bed A",
                        "sowing_months": [3, 4, 5],
                        "harvest_months": [6, 7, 8],
                        "days_to_germination": 7,
                        "days_to_harvest": 60,
                    }
                ],
                "start_date": "2026-03-01",
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "events" in data
        assert "total_events" in data
        assert data["total_events"] >= 0
        assert "date_range_start" in data
        assert "date_range_end" in data

    def test_generate_calendar_empty_plants(self, authenticated_client):
        """Empty plant list should return empty calendar."""
        response = authenticated_client.post(
            "/api/v1/calendar/generate",
            json={"plants": []},
        )
        assert response.status_code == 200
        assert response.json()["total_events"] == 0

    def test_generate_calendar_multiple_plants(self, authenticated_client):
        """Multiple plants should produce multiple events."""
        response = authenticated_client.post(
            "/api/v1/calendar/generate",
            json={
                "plants": [
                    {
                        "plant_id": "basil",
                        "plant_name": "Basil",
                        "sowing_months": [3, 4],
                        "harvest_months": [6, 7],
                        "days_to_germination": 7,
                        "days_to_harvest": 60,
                    },
                    {
                        "plant_id": "tomato",
                        "plant_name": "Tomato",
                        "sowing_months": [9, 10],
                        "harvest_months": [1, 2],
                        "days_to_germination": 10,
                        "days_to_harvest": 90,
                    },
                ],
                "start_date": "2026-03-01",
            },
        )
        assert response.status_code == 200
        assert response.json()["total_events"] > 0


class TestTaskGeneration:
    """Test /api/v1/calendar/tasks endpoint."""

    def test_generate_tasks_from_events(self, authenticated_client):
        """Should convert events to human-readable tasks."""
        response = authenticated_client.post(
            "/api/v1/calendar/tasks",
            json={
                "events": [
                    {
                        "plant_id": "basil",
                        "plant_name": "Basil",
                        "event_type": "sow",
                        "start_date": "2026-04-01",
                        "bed_name": "Bed A",
                        "description": "Sow basil seeds",
                        "priority": "high",
                    }
                ],
                "current_date": "2026-03-28",
            },
        )
        assert response.status_code == 200

        data = response.json()
        assert "tasks" in data
        assert "urgent_tasks" in data
        assert "upcoming_tasks" in data
