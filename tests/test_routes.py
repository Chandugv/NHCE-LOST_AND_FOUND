"""
Tests for core Flask routes and application health.

Covers:
  - Health check endpoint
  - Homepage (index) renders correctly
  - 404 handling for unknown routes
  - Login / logout flow
  - Registration with duplicate detection
  - Item listing and detail pages
  - Redirect behaviour when unauthenticated
"""

import pytest
from tests.conftest import make_user, make_item


# ── Health & Basic Pages ──────────────────────────────────────────────────────

class TestHealthCheck:
    """The /health endpoint should always return 200 + JSON {status: ok}."""

    def test_health_returns_200(self, client, app):
        with app.app_context():
            resp = client.get("/health")
            assert resp.status_code == 200

    def test_health_returns_ok_json(self, client, app):
        with app.app_context():
            data = client.get("/health").get_json()
            assert data == {"status": "ok"}


class TestIndexPage:
    """The homepage should load and show the item feed."""

    def test_index_status_200(self, client, app):
        with app.app_context():
            resp = client.get("/")
            assert resp.status_code == 200

    def test_index_contains_lost_and_found_text(self, client, app):
        with app.app_context():
            resp = client.get("/")
            assert b"Lost" in resp.data or b"Found" in resp.data

    def test_index_search_query_param(self, client, app):
        """Passing ?q= should not crash the page."""
        with app.app_context():
            resp = client.get("/?q=wallet&category=Accessories")
            assert resp.status_code == 200


class TestUnknownRoute:
    """Requests to nonexistent routes should return 404."""

    def test_404_for_unknown_path(self, client, app):
        with app.app_context():
            resp = client.get("/this-does-not-exist")
            assert resp.status_code == 404


# ── Authentication ────────────────────────────────────────────────────────────

class TestRegistration:
    """User registration page and form submission."""

    def test_register_page_loads(self, client, app):
        with app.app_context():
            resp = client.get("/register")
            assert resp.status_code == 200

    def test_successful_registration_redirects(self, client, app):
        with app.app_context():
            resp = client.post("/register", data={
                "username": "newstudent",
                "email": "new@nhce.edu",
                "password": "StrongPass1!",
            }, follow_redirects=False)
            # Should redirect to /login after success
            assert resp.status_code in (301, 302)
            assert "/login" in resp.headers.get("Location", "")

    def test_duplicate_username_flashes_error(self, client, app):
        with app.app_context():
            make_user(username="dupuser", email="dup@nhce.edu")
            resp = client.post("/register", data={
                "username": "dupuser",
                "email": "other@nhce.edu",
                "password": "AnyPass123",
            }, follow_redirects=True)
            assert resp.status_code == 200
            # Flask flashes "Username or Email already exists."
            assert b"already exists" in resp.data or b"exists" in resp.data


class TestLogin:
    """Login and logout flows."""

    def test_login_page_loads(self, client, app):
        with app.app_context():
            resp = client.get("/login")
            assert resp.status_code == 200

    def test_valid_login_redirects(self, client, app):
        with app.app_context():
            make_user(username="loginuser", email="login@nhce.edu",
                      password="Right@Pass1")
            resp = client.post("/login", data={
                "username": "loginuser",
                "password": "Right@Pass1",
            }, follow_redirects=False)
            assert resp.status_code in (301, 302)

    def test_invalid_password_stays_on_login(self, client, app):
        with app.app_context():
            make_user(username="loginuser2", email="login2@nhce.edu",
                      password="Right@Pass1")
            resp = client.post("/login", data={
                "username": "loginuser2",
                "password": "WrongPassword",
            }, follow_redirects=True)
            assert resp.status_code == 200
            assert b"Invalid" in resp.data or b"password" in resp.data.lower()

    def test_logout_redirects_to_index(self, client, app):
        with app.app_context():
            make_user(username="logoutuser", email="logout@nhce.edu",
                      password="Pass@1234")
            # First login
            client.post("/login", data={
                "username": "logoutuser",
                "password": "Pass@1234",
            })
            resp = client.get("/logout", follow_redirects=False)
            assert resp.status_code in (301, 302)
            assert "/" in resp.headers.get("Location", "")


# ── Unauthenticated Redirects ─────────────────────────────────────────────────

class TestAuthGuards:
    """Protected routes must redirect anonymous users to /login."""

    @pytest.mark.parametrize("path", [
        "/post",
        "/profile",
        "/generate_qr",
        "/admin",
        "/karma_shop",
    ])
    def test_protected_route_redirects_to_login(self, client, app, path):
        with app.app_context():
            resp = client.get(path, follow_redirects=False)
            assert resp.status_code in (301, 302)
            location = resp.headers.get("Location", "")
            assert "login" in location


# ── Item Listing & Detail ─────────────────────────────────────────────────────

class TestItems:
    """Item creation and retrieval."""

    def test_item_detail_404_for_missing_item(self, client, app):
        with app.app_context():
            resp = client.get("/item/99999")
            assert resp.status_code == 404

    def test_item_detail_200_for_existing_item(self, client, app):
        with app.app_context():
            user = make_user(username="itemowner", email="itemowner@nhce.edu")
            item = make_item(user_id=user.id, title="Blue Umbrella")
            resp = client.get(f"/item/{item.id}")
            assert resp.status_code == 200
            assert b"Blue Umbrella" in resp.data

    def test_index_shows_open_items(self, client, app):
        with app.app_context():
            user = make_user(username="poster", email="poster@nhce.edu")
            make_item(user_id=user.id, title="Unique Lost Calculator",
                      status="open")
            resp = client.get("/")
            assert b"Unique Lost Calculator" in resp.data

    def test_index_hides_resolved_items(self, client, app):
        with app.app_context():
            user = make_user(username="poster2", email="poster2@nhce.edu")
            make_item(user_id=user.id, title="Secretly Resolved Item",
                      status="resolved")
            resp = client.get("/")
            # Resolved items should NOT appear on the public feed
            assert b"Secretly Resolved Item" not in resp.data

    def test_post_item_requires_login(self, client, app):
        with app.app_context():
            resp = client.post("/post", data={
                "title": "My Watch",
                "description": "Silver watch lost near canteen",
                "category": "Accessories",
                "location": "Canteen",
                "item_type": "lost",
            }, follow_redirects=False)
            assert resp.status_code in (301, 302)
            assert "login" in resp.headers.get("Location", "")
