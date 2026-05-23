import os
from dotenv import load_dotenv

load_dotenv()

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'lost-and-found-dev-key'
    # When running on serverless platforms (like Vercel) the filesystem is read-only
    # except for /tmp — use a tmp sqlite DB there if no DATABASE_URL provided.
    if os.environ.get('VERCEL'):
        default_db = 'sqlite:////tmp/lost_and_found.db'
    else:
        default_db = os.environ.get('DATABASE_URL') or 'sqlite:///lost_and_found.db'
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or default_db
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    # ─── Mail Configuration ──────────────────────────────────────────────────
    # For Gmail: use an App Password (not your real password)
    # Steps: Google Account → Security → 2-Step Verification → App Passwords
    # Then paste the 16-char app password below or in .env as MAIL_PASSWORD
    MAIL_SERVER = os.environ.get('MAIL_SERVER') or 'smtp.gmail.com'
    MAIL_PORT = int(os.environ.get('MAIL_PORT') or 587)
    MAIL_USE_TLS = True
    MAIL_USE_SSL = False
    MAIL_USERNAME = os.environ.get('MAIL_USERNAME') or ''
    MAIL_PASSWORD = os.environ.get('MAIL_PASSWORD') or ''
    MAIL_DEFAULT_SENDER = os.environ.get('MAIL_DEFAULT_SENDER') or os.environ.get('MAIL_USERNAME') or ''

    # ─── Uploads ─────────────────────────────────────────────────────────────
    # Upload folder: prefer env override; on Vercel use /tmp/uploads
    if os.environ.get('VERCEL'):
        UPLOAD_FOLDER = os.environ.get('UPLOAD_FOLDER') or '/tmp/uploads'
    else:
        UPLOAD_FOLDER = os.path.join(os.path.abspath(os.path.dirname(__file__)), 'static/uploads')
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
