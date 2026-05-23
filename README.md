# NHCE Lost & Found System 🎒💻

A premium, modern web application designed for New Horizon College of Engineering (NHCE) to help students report and recover lost items on campus. Built with a sleek glassmorphic UI, Smart Matching technology, and automated email notifications.

## Features ✨
- **Smart Matching Algorithm:** Automatically cross-references lost and found reports to identify potential matches using NLP keyword intersection.
- **Automated Notifications:** Sends real-time alerts to users when a potential match is found or an item is claimed.
- **Glassmorphic UI:** A premium, modern interface with a dark-blue aesthetic, subtle shadows, and interactive micro-animations.
- **Admin Dashboard:** Secure moderation panel for managing item statuses and user reports.
- **Image Uploads:** Secure image handling and resizing via Pillow for visual proof of items.

## Tech Stack 🛠️
- **Backend:** Flask, Python 3.11, SQLite, SQLAlchemy
- **Frontend:** HTML5, Vanilla CSS3 (Glassmorphism), JavaScript
- **Email Services:** Flask-Mailman (SMTP via Gmail)
- **Deployment:** Render (Gunicorn)

## Local Setup 🚀

1. **Clone the repository:**
   ```bash
   git clone https://github.com/Chandugv/NHCE-LOST_AND_FOUND.git
   cd NHCE-LOST_AND_FOUND
   ```

2. **Set up a virtual environment:**
   ```bash
   python3 -m venv venv
   source venv/bin/activate
   ```

3. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

4. **Environment Variables:**
   Rename `.env.example` to `.env` and fill in your details (like Gmail App Passwords).

5. **Run the Database & Server:**
   ```bash
   python init_db.py
   python app.py
   ```
   *The app will run at `http://127.0.0.1:5000/`*

## Deployment 🌍
This project is configured for easy deployment on **Render.com**. It includes a `Procfile`, a `runtime.txt`, and uses `gunicorn` for a production-grade server!
