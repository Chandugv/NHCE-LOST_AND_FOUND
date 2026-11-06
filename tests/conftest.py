"""
Pytest configuration and shared fixtures for NHCE Lost & Found tests.
Uses an in-memory SQLite database — no external services required.
"""

import os
import pytest

# Point to in-memory SQLite before importing the app so Config picks it up
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")
os.environ.setdefault("SECRET_KEY", "test-secret-key-not-for-prod")
os.environ.setdefault("FLASK_ENV", "testing")


@pytest.fixture(scope="session")
def app():
    """Create the Flask application configured for testing."""
    from app import app as flask_app

    flask_app.config.update(
        TESTING=True,
        SQLALCHEMY_DATABASE_URI="sqlite:///:memory:",
        WTF_CSRF_ENABLED=False,
        MAIL_SUPPRESS_SEND=True,          # Never actually send emails in tests
        UPLOAD_FOLDER="/tmp/test_uploads",
    )
    yield flask_app


@pytest.fixture(scope="session")
def _db(app):
    """Create all tables once per test session, drop them at the end."""
    from models import db

    with app.app_context():
        db.create_all()
        yield db
        db.drop_all()


@pytest.fixture(autouse=True)
def db_session(_db, app):
    """
    Wrap every test in a transaction that is rolled back afterward,
    so each test starts with a clean database.
    """
    from models import db as _db_obj

    with app.app_context():
        connection = _db_obj.engine.connect()
        transaction = connection.begin()
        # Bind the session to this connection so rollback works
        _db_obj.session.configure(bind=connection)
        yield
        _db_obj.session.remove()
        transaction.rollback()
        connection.close()


@pytest.fixture
def client(app):
    """Return a test client for the Flask application."""
    return app.test_client()


@pytest.fixture
def runner(app):
    """Return a CLI test runner."""
    return app.test_cli_runner()


# ── Helper factories ──────────────────────────────────────────────────────────

def make_user(username="testuser", email="test@nhce.edu", password="Test@1234",
              is_admin=False):
    """Create and persist a User object inside the current app context."""
    from models import db, User

    user = User(
        username=username,
        email=email,
        is_admin=is_admin,
    )
    user.set_password(password)
    db.session.add(user)
    db.session.commit()
    return user


def make_item(user_id, title="Red Wallet", description="Leather wallet",
              category="Accessories", location="Block A", item_type="lost",
              status="open"):
    """Create and persist an Item object inside the current app context."""
    from models import db, Item

    item = Item(
        title=title,
        description=description,
        category=category,
        location=location,
        item_type=item_type,
        poster_email="test@nhce.edu",
        user_id=user_id,
        status=status,
    )
    db.session.add(item)
    db.session.commit()
    return item
