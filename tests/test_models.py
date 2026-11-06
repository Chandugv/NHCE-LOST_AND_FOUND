"""
Tests for the Smart Matching algorithm and business logic.

Covers:
  - find_potential_matches — keyword intersection
  - User.set_password / check_password
  - Karma point award logic
  - allowed_file helper
"""

import pytest
from tests.conftest import make_user, make_item


# ── Smart Matching ────────────────────────────────────────────────────────────

class TestSmartMatching:
    """
    find_potential_matches should return items of the opposite type
    in the same category that share at least one keyword with the query item.
    """

    def test_no_match_when_database_empty(self, app):
        with app.app_context():
            from app import find_potential_matches
            user = make_user(username="matcher", email="matcher@nhce.edu")
            item = make_item(user_id=user.id, title="Red Wallet",
                             category="Accessories", item_type="lost")
            matches = find_potential_matches(item)
            assert matches == []

    def test_match_found_on_keyword_intersection(self, app):
        """A 'found' item with a matching keyword should be returned."""
        with app.app_context():
            from app import find_potential_matches
            user = make_user(username="u1", email="u1@nhce.edu")
            # Lost item: "Red Wallet"
            lost_item = make_item(user_id=user.id, title="Red Wallet",
                                  category="Accessories", item_type="lost")
            # Found item: "Wallet Black" — shares keyword "Wallet"
            make_item(user_id=user.id, title="Wallet Black",
                      category="Accessories", item_type="found")

            matches = find_potential_matches(lost_item)
            assert len(matches) == 1
            assert matches[0].title == "Wallet Black"

    def test_no_match_on_different_category(self, app):
        """Items in different categories should NOT match even if keywords overlap."""
        with app.app_context():
            from app import find_potential_matches
            user = make_user(username="u2", email="u2@nhce.edu")
            lost_item = make_item(user_id=user.id, title="Apple Earbuds",
                                  category="Electronics", item_type="lost")
            # Same keyword "Apple" but different category
            make_item(user_id=user.id, title="Apple Notebook",
                      category="Stationery", item_type="found")

            matches = find_potential_matches(lost_item)
            assert matches == []

    def test_no_self_match(self, app):
        """An item should never be matched against itself."""
        with app.app_context():
            from app import find_potential_matches
            user = make_user(username="u3", email="u3@nhce.edu")
            # Only one item in DB — same type, same title
            item = make_item(user_id=user.id, title="Calculator",
                             category="Electronics", item_type="lost")
            # Add an opposite-type item with NO keyword overlap
            make_item(user_id=user.id, title="Completely Different",
                      category="Electronics", item_type="found")
            matches = find_potential_matches(item)
            # "Calculator" ∩ "Completely Different" = ∅ → no match
            assert matches == []

    def test_resolved_items_excluded_from_matches(self, app):
        """Already-resolved found items should not appear as matches."""
        with app.app_context():
            from app import find_potential_matches
            user = make_user(username="u4", email="u4@nhce.edu")
            lost_item = make_item(user_id=user.id, title="Blue Pen",
                                  category="Stationery", item_type="lost")
            make_item(user_id=user.id, title="Pen Pouch Blue",
                      category="Stationery", item_type="found",
                      status="resolved")
            matches = find_potential_matches(lost_item)
            assert matches == []


# ── User Model ────────────────────────────────────────────────────────────────

class TestUserModel:
    """Password hashing and verification."""

    def test_password_is_hashed_at_rest(self, app):
        with app.app_context():
            user = make_user(username="hashtest", email="hash@nhce.edu",
                             password="PlainText123")
            assert user.password_hash != "PlainText123"
            assert len(user.password_hash) > 20

    def test_correct_password_passes(self, app):
        with app.app_context():
            user = make_user(username="pwtest", email="pw@nhce.edu",
                             password="Correct@Pass")
            assert user.check_password("Correct@Pass") is True

    def test_wrong_password_fails(self, app):
        with app.app_context():
            user = make_user(username="wrongpw", email="wrongpw@nhce.edu",
                             password="Correct@Pass")
            assert user.check_password("WrongPassword") is False

    def test_karma_starts_at_zero(self, app):
        with app.app_context():
            user = make_user(username="karma0", email="karma0@nhce.edu")
            assert user.karma_points == 0


# ── Allowed File Extension Helper ─────────────────────────────────────────────

class TestAllowedFile:
    """allowed_file should accept images and reject other extensions."""

    def test_jpg_is_allowed(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("photo.jpg") is True

    def test_jpeg_is_allowed(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("image.jpeg") is True

    def test_png_is_allowed(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("screenshot.PNG") is True

    def test_gif_is_allowed(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("anim.gif") is True

    def test_exe_is_rejected(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("virus.exe") is False

    def test_pdf_is_rejected(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("resume.pdf") is False

    def test_no_extension_is_rejected(self, app):
        with app.app_context():
            from app import allowed_file
            assert allowed_file("noextension") is False


# ── Item Model ────────────────────────────────────────────────────────────────

class TestItemModel:
    """Basic item model properties."""

    def test_item_repr(self, app):
        with app.app_context():
            user = make_user(username="reprtest", email="repr@nhce.edu")
            item = make_item(user_id=user.id, title="Blue Cap",
                             item_type="found")
            assert "found" in repr(item)
            assert "Blue Cap" in repr(item)

    def test_item_default_status_is_open(self, app):
        with app.app_context():
            user = make_user(username="statustest", email="status@nhce.edu")
            item = make_item(user_id=user.id, title="Umbrella")
            assert item.status == "open"
