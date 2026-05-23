from datetime import datetime
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    phone = db.Column(db.String(20), nullable=True)
    department = db.Column(db.String(100), nullable=True)
    is_admin = db.Column(db.Boolean, default=False)
    karma_points = db.Column(db.Integer, default=0)
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
    
    items = db.relationship('Item', backref='owner', lazy=True)
    notifications = db.relationship('Notification', backref='notified_user', lazy=True)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class Notification(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    message = db.Column(db.String(255), nullable=False)
    link = db.Column(db.String(255), nullable=True) # Link to the matched item
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

class Item(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text, nullable=False)
    category = db.Column(db.String(50), nullable=False, index=True)
    location = db.Column(db.String(100), nullable=False)
    item_type = db.Column(db.String(10), nullable=False, index=True) # "lost" or "found"
    photo_filename = db.Column(db.String(100), nullable=True)
    poster_email = db.Column(db.String(120), nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True) # Linked to owner
    status = db.Column(db.String(20), default='open', index=True) # "open", "pending", "resolved"
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    claims = db.relationship('Claim', backref='item', lazy=True, cascade="all, delete-orphan")

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def __repr__(self):
        return f'<Item {self.item_type}: {self.title}>'

class Claim(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    item_id = db.Column(db.Integer, db.ForeignKey('item.id'), nullable=False)
    claimer_name = db.Column(db.String(100), nullable=False)
    claimer_email = db.Column(db.String(120), nullable=False)
    description_proof = db.Column(db.Text, nullable=False)
    status = db.Column(db.String(20), default='pending') # "pending", "approved", "rejected"
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def __repr__(self):
        return f'<Claim for Item {self.item_id} by {self.claimer_email}>'

class PreRegisteredItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    qr_id = db.Column(db.String(36), unique=True, nullable=False, index=True)
    title = db.Column(db.String(100), nullable=False)
    description = db.Column(db.Text, nullable=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
