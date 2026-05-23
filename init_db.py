import os
from app import app, db
from models import User

def init_db():
    with app.app_context():
        # Create tables
        db.create_all()
        
        # Check if Admin exists, otherwise create one
        admin = User.query.filter_by(username='admin').first()
        if not admin:
            admin = User(username='admin', email='admin@nhce.edu')
            admin.set_password('admin123')
            db.session.add(admin)
            db.session.commit()
            print("Admin user created with username 'admin' and password 'admin123'.")
        else:
            print("Database and admin user already exist.")

if __name__ == "__main__":
    init_db()
