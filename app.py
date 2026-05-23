import os
from flask import (
    Flask,
    render_template,
    request,
    redirect,
    url_for,
    flash,
    session,
)
from flask_mailman import Mail, EmailMessage
from werkzeug.utils import secure_filename
from PIL import Image
from models import db, User, Item, Claim, Notification, PreRegisteredItem
from config import Config
import uuid
try:
    import qrcode
except Exception:
    qrcode = None
    print("[WARN] qrcode module not available; QR features disabled")
from io import BytesIO
import base64

app = Flask(__name__)
app.config.from_object(Config)
# Ensure a writable instance path on serverless platforms
try:
    if os.environ.get('VERCEL'):
        app.instance_path = os.environ.get('INSTANCE_PATH', '/tmp/instance')
    # try to create instance path if possible
    os.makedirs(app.instance_path, exist_ok=True)
except Exception:
    # Ignore failures creating instance path on read-only filesystems
    pass

# Ensure upload folder is writable or fallback to /tmp/uploads
try:
    upload_folder = app.config.get('UPLOAD_FOLDER')
    if not os.access(upload_folder, os.W_OK):
        app.config['UPLOAD_FOLDER'] = os.environ.get('UPLOAD_FOLDER', '/tmp/uploads')
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
except Exception:
    # Best-effort — serverless may be read-only except /tmp
    pass

# Initialize Extensions
db.init_app(app)

# If running on a serverless platform with a fresh /tmp sqlite DB, ensure tables exist
try:
    if os.environ.get('VERCEL'):
        with app.app_context():
            db.create_all()
except Exception:
    # Best-effort: avoid crashing import if DB creation fails
    pass
mail = Mail(app)


def find_potential_matches(item):
    """
    Search for items of the opposite type in the same category that might match the new report.
    """
    opposite_type = "found" if item.item_type == "lost" else "lost"
    potential_matches = Item.query.filter(
        Item.id != item.id,
        Item.item_type == opposite_type,
        Item.category == item.category,
        Item.status == "open",
    ).all()

    matches = []
    # Simplified keyword matching (same-words intersection)
    item_keywords = set(item.title.lower().split())

    for potential in potential_matches:
        pot_keywords = set(potential.title.lower().split())
        if item_keywords.intersection(pot_keywords):
            matches.append(potential)

    return matches


@app.context_processor
def inject_user_data():
    if "user_id" in session:
        user = User.query.get(session["user_id"])
        if user:
            return {
                "user_notifications": Notification.query.filter_by(
                    user_id=user.id
                )
                .order_by(Notification.created_at.desc())
                .limit(10)
                .all()
            }
    return {"user_notifications": []}


def allowed_file(filename):
    return (
        "." in filename
        and filename.rsplit(".", 1)[1].lower()
        in app.config["ALLOWED_EXTENSIONS"]
    )


def save_photo(file):
    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        # Ensure unique filename
        filename = f"{os.urandom(8).hex()}_{filename}"
        filepath = os.path.join(app.config["UPLOAD_FOLDER"], filename)

        # Open with Pillow, resize and save
        img = Image.open(file)
        img.thumbnail((800, 800))  # Resize for standard view
        img.save(filepath)
        return filename
    return None


# Routes


@app.route("/")
def index():
    query = request.args.get("q", "")
    category = request.args.get("category", "")
    location = request.args.get("location", "")
    item_type = request.args.get("type", "")  # lost/found

    items_query = Item.query.filter_by(status="open")

    if query:
        items_query = items_query.filter(
            (Item.title.ilike(f"%{query}%"))
            | (Item.description.ilike(f"%{query}%"))
        )
    if category:
        items_query = items_query.filter_by(category=category)
    if location:
        items_query = items_query.filter_by(location=location)
    if item_type:
        items_query = items_query.filter_by(item_type=item_type)

    items = items_query.order_by(Item.created_at.desc()).all()
    top_users = (
        User.query.filter(User.karma_points > 0)
        .order_by(User.karma_points.desc())
        .limit(5)
        .all()
    )
    return render_template(
        "index.html",
        items=items,
        top_users=top_users,
        query=query,
        category=category,
        location=location,
        item_type=item_type,
    )


@app.route("/post", methods=["GET", "POST"])
def post_item():
    if "user_id" not in session:
        flash("Please login or register to post an item.", "warning")
        return redirect(url_for("login"))

    user = User.query.get(session["user_id"])

    if request.method == "POST":
        title = request.form["title"]
        description = request.form["description"]
        category = request.form["category"]
        location = request.form["location"]
        item_type = request.form["item_type"]
        # Default to account email if not specified
        poster_email = request.form.get("poster_email") or user.email

        photo = request.files.get("photo")
        photo_filename = save_photo(photo)

        new_item = Item(
            title=title,
            description=description,
            category=category,
            location=location,
            item_type=item_type,
            poster_email=poster_email,
            photo_filename=photo_filename,
            user_id=user.id,
        )
        db.session.add(new_item)
        db.session.commit()

        # Phase 2: Search for matches and notify
        matches = find_potential_matches(new_item)
        for match in matches:
            # Notify the current user about a match
            notif_current = Notification(
                user_id=user.id,
                message=f"Smart Match Found: Someone reported a {match.title} that fits your post!",
                link=url_for("item_detail", item_id=match.id),
            )
            # Notify the match owner
            notif_match_owner = Notification(
                user_id=match.user_id,
                message=f"Smart Match Found: Someone just posted a {new_item.title} that matches yours!",
                link=url_for("item_detail", item_id=new_item.id),
            )
            db.session.add(notif_current)
            db.session.add(notif_match_owner)

        if matches:
            db.session.commit()
            flash(
                f"Your {item_type} item has been posted! We found {len(matches)} potential matches for you.",
                "success",
            )
        else:
            flash(
                f"Your {item_type} item has been posted successfully!",
                "success",
            )

        return redirect(url_for("index"))

    return render_template(
        "post_item.html",
        user=user,
        prefill_title=request.args.get("title", ""),
        prefill_desc=request.args.get("description", ""),
        prefill_type=request.args.get("type", ""),
    )


@app.route("/item/<int:item_id>")
def item_detail(item_id):
    item = Item.query.get_or_404(item_id)
    return render_template("item_detail.html", item=item)


@app.route("/claim/<int:item_id>", methods=["POST"])
def claim_item(item_id):
    item = Item.query.get_or_404(item_id)
    claimer_name = request.form["claimer_name"]
    claimer_email = request.form["claimer_email"]
    description_proof = request.form["description_proof"]

    new_claim = Claim(
        item_id=item_id,
        claimer_name=claimer_name,
        claimer_email=claimer_email,
        description_proof=description_proof,
    )
    db.session.add(new_claim)
    db.session.commit()

    # Only attempt email if credentials are configured
    mail_user = app.config.get("MAIL_USERNAME", "")
    mail_pass = app.config.get("MAIL_PASSWORD", "")

    if mail_user and mail_pass:
        msg = EmailMessage(
            subject=f"New Claim for your item: {item.title}",
            body=(
                f"Hello,\n\n"
                f"Someone has submitted a claim for your item: '{item.title}'.\n\n"
                f"Claimer Name  : {claimer_name}\n"
                f"Claimer Email : {claimer_email}\n"
                f"Proof Provided: {description_proof}\n\n"
                f"Please log in to the portal to review the claim.\n\n"
                f"— Lost & Found System"
            ),
            from_email=app.config["MAIL_DEFAULT_SENDER"],
            to=[item.poster_email],
        )
        try:
            msg.send()
            flash(
                "Claim submitted! The poster has been notified by email.",
                "success",
            )
        except Exception as e:
            print(f"[Email Error] {e}")
            flash(
                "Claim submitted successfully! (Email notification could not be sent — check SMTP settings.)",
                "warning",
            )
    else:
        # No email credentials — still save the claim, just skip email
        flash(
            "Claim submitted successfully! (Email notifications are not configured yet.)",
            "success",
        )

    return redirect(url_for("item_detail", item_id=item_id))


# Admin View (Phase 5 Placeholder)


@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        username = request.form["username"]
        email = request.form["email"]
        password = request.form["password"]
        phone = request.form.get("phone")
        department = request.form.get("department")

        if User.query.filter(
            (User.username == username) | (User.email == email)
        ).first():
            flash("Username or Email already exists.", "danger")
            return redirect(url_for("register"))

        new_user = User(
            username=username, email=email, phone=phone, department=department
        )
        new_user.set_password(password)
        db.session.add(new_user)
        db.session.commit()

        flash("Account created! Please log in.", "success")
        return redirect(url_for("login"))
    return render_template("register.html")


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form["username"]
        password = request.form["password"]
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            session["user_id"] = user.id
            session["is_admin"] = user.is_admin
            if user.is_admin:
                return redirect(url_for("admin_dashboard"))
            return redirect(url_for("profile"))
        flash("Invalid username or password", "danger")
    return render_template("login.html")


@app.route("/profile")
def profile():
    if "user_id" not in session:
        return redirect(url_for("login"))
    user = User.query.get(session["user_id"])
    items = Item.query.filter_by(user_id=user.id).all()
    return render_template("profile.html", user=user, items=items)


@app.route("/notifications/read", methods=["POST"])
def mark_notifications_read():
    if "user_id" in session:
        Notification.query.filter_by(
            user_id=session["user_id"], is_read=False
        ).update({"is_read": True})
        db.session.commit()
    return redirect(request.referrer or url_for("profile"))


@app.route("/generate_qr", methods=["GET", "POST"])
def generate_qr():
    if "user_id" not in session:
        return redirect(url_for("login"))

    if request.method == "POST":
        title = request.form["title"]
        description = request.form.get("description", "")
        user_id = session["user_id"]
        qr_id = str(uuid.uuid4())

        pre_item = PreRegisteredItem(
            qr_id=qr_id, title=title, description=description, user_id=user_id
        )
        db.session.add(pre_item)
        db.session.commit()

        # Generate QR code image (only if qrcode module is available)
        if qrcode is None:
            flash("QR generation is not available on the server (missing dependency).", "warning")
            qr_base64 = None
            qr_url = url_for("scan_qr", qr_id=qr_id, _external=True)
        else:
            qr = qrcode.QRCode(version=1, box_size=10, border=5)
            qr_url = url_for("scan_qr", qr_id=qr_id, _external=True)
            qr.add_data(qr_url)
            qr.make(fit=True)
            img = qr.make_image(fill="black", back_color="white")

            buffer = BytesIO()
            img.save(buffer)
            qr_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")

        return render_template(
            "qr_code.html", qr_base64=qr_base64, title=title, qr_url=qr_url
        )

    return render_template("generate_qr.html")


@app.route("/scan/<string:qr_id>", methods=["GET"])
def scan_qr(qr_id):
    pre_item = PreRegisteredItem.query.filter_by(qr_id=qr_id).first_or_404()
    owner = User.query.get(pre_item.user_id)
    return render_template("scan_qr.html", pre_item=pre_item, owner=owner)


@app.route("/health")
def health_check():
    return {"status": "ok"}, 200


@app.route("/admin")
def admin_dashboard():
    if "user_id" not in session or not session.get("is_admin"):
        flash("Unauthorized access. Admin login required.", "danger")
        return redirect(url_for("login"))

    items = Item.query.order_by(Item.created_at.desc()).all()

    # Phase 3: Analytics calculations
    total_lost = Item.query.filter_by(item_type="lost").count()
    total_found = Item.query.filter_by(item_type="found").count()
    total_resolved = Item.query.filter_by(status="resolved").count()

    # Category distribution for pie chart
    categories_raw = (
        db.session.query(Item.category, db.func.count(Item.id))
        .group_by(Item.category)
        .all()
    )
    categories_data = {
        "labels": [c[0] for c in categories_raw],
        "counts": [c[1] for c in categories_raw],
    }

    return render_template(
        "admin.html",
        items=items,
        stats={
            "lost": total_lost,
            "found": total_found,
            "resolved": total_resolved,
        },
        categories_data=categories_data,
    )


@app.route(
    "/admin/update_status/<int:item_id>/<string:status>", methods=["POST"]
)
def update_status(item_id, status):
    if "user_id" not in session:
        return redirect(url_for("login"))
    item = Item.query.get_or_404(item_id)

    # Phase 1 Gamification: Award 10 Karma Points if a 'found' item is
    # successfully returned
    if (
        status == "resolved"
        and item.status != "resolved"
        and item.item_type == "found"
    ):
        owner = User.query.get(item.user_id)
        if owner:
            owner.karma_points += 10
            flash("10 Karma Points awarded for returning an item!", "success")

    item.status = status
    db.session.commit()
    flash(f"Item status updated to {status}.", "success")
    return redirect(request.referrer or url_for("index"))


@app.route("/admin/delete/<int:item_id>", methods=["POST"])
def delete_item(item_id):
    if "user_id" not in session:
        return redirect(url_for("login"))
    item = Item.query.get_or_404(item_id)
    # Remove photo file if exists
    if item.photo_filename:
        try:
            os.remove(
                os.path.join(app.config["UPLOAD_FOLDER"], item.photo_filename)
            )
        except Exception:
            pass
    db.session.delete(item)
    db.session.commit()
    flash("Item deleted successfully.", "success")
    return redirect(url_for("admin_dashboard"))


@app.route("/admin/test_email", methods=["POST"])
def test_email():
    if "user_id" not in session:
        return redirect(url_for("login"))

    mail_user = app.config.get("MAIL_USERNAME", "")
    mail_pass = app.config.get("MAIL_PASSWORD", "")

    if not mail_user or not mail_pass:
        flash(
            "Email is NOT configured (MAIL_USERNAME/PASSWORD missing in .env).",
            "danger",
        )
        return redirect(url_for("admin_dashboard"))

    msg = EmailMessage(
        subject="Lost & Found SMTP Test",
        body="This is a test email from your Lost & Found System. If you received this, your configuration is correct!",
        from_email=app.config["MAIL_DEFAULT_SENDER"],
        to=[mail_user],
    )

    try:
        msg.send()
        flash(f"Test email sent successfully to {mail_user}!", "success")
    except Exception as e:
        flash(f"SMTP Error: {str(e)}", "danger")
        print(f"[SMTP Test Error] {e}")

    return redirect(url_for("admin_dashboard"))


@app.route("/item/<int:item_id>/claims", methods=["GET"])
def review_claims(item_id):
    if "user_id" not in session:
        return redirect(url_for("login"))
    item = Item.query.get_or_404(item_id)
    user = User.query.get(session["user_id"])
    
    # Restrict to owner of the item or admin
    if item.user_id != user.id and not user.is_admin:
        flash("You are not authorized to view these claims.", "danger")
        return redirect(url_for("profile"))
        
    return render_template("review_claims.html", item=item)


@app.route("/claim/<int:claim_id>/approve", methods=["POST"])
def approve_claim(claim_id):
    if "user_id" not in session:
        return redirect(url_for("login"))
    
    claim = Claim.query.get_or_404(claim_id)
    item = Item.query.get(claim.item_id)
    user = User.query.get(session["user_id"])
    
    # Restrict to owner or admin
    if item.user_id != user.id and not user.is_admin:
        flash("Unauthorized action.", "danger")
        return redirect(url_for("profile"))
        
    # Process approval
    claim.status = "approved"
    item.status = "resolved"
    
    # Reject other claims
    for other_claim in item.claims:
        if other_claim.id != claim.id:
            other_claim.status = "rejected"
            # Notify rejected claimers
            claimer_u = User.query.filter_by(email=other_claim.claimer_email).first()
            notif_rej = Notification(
                user_id=claimer_u.id if claimer_u else item.user_id,
                message=f"Your claim for '{item.title}' has been rejected as it was claimed by another user.",
                link=url_for("item_detail", item_id=item.id)
            )
            db.session.add(notif_rej)
            
    # Award karma points to the item finder if it was a found item
    if item.item_type == "found":
        finder = User.query.get(item.user_id)
        if finder:
            finder.karma_points += 10
            flash("10 Karma Points awarded for returning an item!", "success")
            
    db.session.commit()
    
    # Create notification for approved claimer
    claimer_user = User.query.filter_by(email=claim.claimer_email).first()
    if claimer_user:
        notif = Notification(
            user_id=claimer_user.id,
            message=f"Congratulations! Your claim for '{item.title}' has been APPROVED by the owner.",
            link=url_for("profile")
        )
        db.session.add(notif)
        db.session.commit()
        
    # Send email notification to approved claimer
    mail_user = app.config.get("MAIL_USERNAME", "")
    mail_pass = app.config.get("MAIL_PASSWORD", "")
    if mail_user and mail_pass:
        msg = EmailMessage(
            subject=f"Claim Approved: {item.title}",
            body=(
                f"Hello {claim.claimer_name},\n\n"
                f"Your claim for the item '{item.title}' has been APPROVED!\n\n"
                f"You can now coordinate with the poster ({item.poster_email}) to arrange return details.\n\n"
                f"— NHCE Lost & Found System"
            ),
            from_email=app.config["MAIL_DEFAULT_SENDER"],
            to=[claim.claimer_email],
        )
        try:
            msg.send()
        except Exception as e:
            print(f"[Email Error] {e}")

    flash("Claim approved successfully and applicant notified!", "success")
    return redirect(url_for("review_claims", item_id=item.id))


@app.route("/claim/<int:claim_id>/reject", methods=["POST"])
def reject_claim(claim_id):
    if "user_id" not in session:
        return redirect(url_for("login"))
        
    claim = Claim.query.get_or_404(claim_id)
    item = Item.query.get(claim.item_id)
    user = User.query.get(session["user_id"])
    
    if item.user_id != user.id and not user.is_admin:
        flash("Unauthorized action.", "danger")
        return redirect(url_for("profile"))
        
    claim.status = "rejected"
    db.session.commit()
    
    claimer_user = User.query.filter_by(email=claim.claimer_email).first()
    if claimer_user:
        notif = Notification(
            user_id=claimer_user.id,
            message=f"Your claim for '{item.title}' has been rejected by the owner.",
            link=url_for("item_detail", item_id=item.id)
        )
        db.session.add(notif)
        db.session.commit()
        
    flash("Claim has been rejected.", "warning")
    return redirect(url_for("review_claims", item_id=item.id))


@app.route("/karma_shop", methods=["GET"])
def karma_shop():
    if "user_id" not in session:
        return redirect(url_for("login"))
    user = User.query.get(session["user_id"])
    
    # Leaderboard calculation
    top_users = User.query.order_by(User.karma_points.desc()).limit(10).all()
    
    rewards = [
        {"id": "coffee", "title": "Udupi Canteen Filter Coffee Coupon", "cost": 30, "icon": "fa-coffee", "desc": "Get a piping hot traditional filter coffee free at Udupi canteen."},
        {"id": "stationery", "title": "NHCE College Stationery Pack", "cost": 50, "icon": "fa-pen-fancy", "desc": "A custom college notebook, premium ballpoint pen, and pencil set."},
        {"id": "hoodie", "title": "NHCE College Hoodie Discount", "cost": 100, "icon": "fa-tshirt", "desc": "Get a premium navy blue NHCE hoodie at 50% discount at the college co-op store."}
    ]
    
    return render_template("karma_shop.html", user=user, top_users=top_users, rewards=rewards)


@app.route("/karma_shop/redeem/<string:item_id>", methods=["POST"])
def redeem_reward(item_id):
    if "user_id" not in session:
        return redirect(url_for("login"))
    user = User.query.get(session["user_id"])
    
    rewards_map = {
        "coffee": {"title": "Udupi Canteen Filter Coffee Coupon", "cost": 30},
        "stationery": {"title": "NHCE College Stationery Pack", "cost": 50},
        "hoodie": {"title": "NHCE College Hoodie Discount", "cost": 100}
    }
    
    if item_id not in rewards_map:
        return {"status": "error", "message": "Invalid reward selected."}, 400
        
    reward = rewards_map[item_id]
    if user.karma_points < reward["cost"]:
        return {"status": "error", "message": "Insufficient Karma Points to redeem this reward."}, 400
        
    user.karma_points -= reward["cost"]
    
    # Generate dynamic ticket and base64 QR code for presentation in modal
    ticket_code = f"NHCE-{os.urandom(4).hex().upper()}-{item_id.upper()}"
    
    if qrcode is None:
        qr_base64 = None
    else:
        qr = qrcode.QRCode(version=1, box_size=10, border=3)
        qr.add_data(f"Voucher code: {ticket_code}\nUser: {user.username}\nReward: {reward['title']}")
        qr.make(fit=True)
        img = qr.make_image(fill="black", back_color="white")

        buffer = BytesIO()
        img.save(buffer)
        qr_base64 = base64.b64encode(buffer.getvalue()).decode("utf-8")
    
    # Save a notification detailing the redemption
    notif = Notification(
        user_id=user.id,
        message=f"Successfully redeemed '{reward['title']}' for {reward['cost']} points. Code: {ticket_code}",
        link=url_for("profile")
    )
    db.session.add(notif)
    db.session.commit()
    
    return {
        "status": "success",
        "ticket_code": ticket_code,
        "title": reward["title"],
        "cost": reward["cost"],
        "qr_base64": qr_base64,
        "remaining_points": user.karma_points
    }


@app.route("/scan/<string:qr_id>/message", methods=["POST"])
def scan_qr_message(qr_id):
    pre_item = PreRegisteredItem.query.filter_by(qr_id=qr_id).first_or_404()
    owner = User.query.get(pre_item.user_id)
    
    finder_email = request.form["finder_email"]
    finder_message = request.form["finder_message"]
    
    # Create notification for owner
    notif = Notification(
        user_id=owner.id,
        message=f"Scanned item secure message: '{finder_message}' (Sender: {finder_email})",
        link=url_for("profile")
    )
    db.session.add(notif)
    db.session.commit()
    
    # Send email notification securely to owner
    mail_user = app.config.get("MAIL_USERNAME", "")
    mail_pass = app.config.get("MAIL_PASSWORD", "")
    if mail_user and mail_pass:
        msg = EmailMessage(
            subject=f"Secure Msg: Scanned asset '{pre_item.title}'",
            body=(
                f"Hello {owner.username},\n\n"
                f"Someone scanned the QR code of your pre-registered item: '{pre_item.title}'.\n\n"
                f"They left the following secure message for you:\n"
                f"\"{finder_message}\"\n\n"
                f"Finder's Contact Email: {finder_email}\n\n"
                f"Please contact them directly or pick up your item.\n\n"
                f"— NHCE Lost & Found System"
            ),
            from_email=app.config["MAIL_DEFAULT_SENDER"],
            to=[owner.email],
        )
        try:
            msg.send()
            flash("Secure message sent to the owner! They have been notified via email and system dashboard.", "success")
        except Exception as e:
            print(f"[Email Error] {e}")
            flash("Message submitted successfully! (Email fail - SMTP server error.)", "warning")
    else:
        flash("Message submitted successfully! The owner has been notified on their dashboard.", "success")
        
    return redirect(url_for("scan_qr", qr_id=qr_id))


@app.route("/logout")
def logout():
    session.pop("user_id", None)
    return redirect(url_for("index"))


if __name__ == "__main__":
    # Local development auto-setup
    with app.app_context():
        db.create_all()
        if not User.query.filter_by(username="admin").first():
            admin = User(
                username="admin",
                email="admin@newhorizonindia.edu",
                is_admin=True,
            )
            admin.set_password("admin123")
            db.session.add(admin)
            db.session.commit()
            print("[INFO] Admin user created: admin / admin123")

    # Use PORT from environment for deployment, default to 5000 for local
    port = int(os.environ.get("PORT", 5000))
    app.run(
        host="0.0.0.0",
        port=port,
        debug=os.environ.get("FLASK_DEBUG", "True") == "True",
    )
