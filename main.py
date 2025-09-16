import logging
import log
import sys
import signal
import os
from datetime import datetime, timezone
from flask import Flask, request, render_template, abort, redirect, url_for
from markupsafe import Markup
import mistune
import uuid
import database
import orchestrator

# otel
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import ConsoleSpanExporter, BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor


def signal_handler(signal, frame):
    logging.warning('SIGTERM received, exiting...')
    sys.exit(0)


signal.signal(signal.SIGTERM, signal_handler)
app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')

# Setup OpenTelemetry
tracer_provider = TracerProvider()
tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(tracer_provider)
FlaskInstrumentor().instrument_app(app)
BotocoreInstrumentor().instrument()


@app.before_request
def before_request():
    """log http request (except for health checks)"""
    if request.path != "/health":
        logging.info(f"HTTP {request.method} {request.url}")


@app.after_request
def after_request(response):
    """log http response (except for health checks)"""
    if request.path != "/health":
        logging.info(
            f"HTTP {request.method} {request.url} {response.status_code}")
    return response


# initialize database client
db = database.Database()

# Check if authentication is enabled
auth_enabled = os.environ.get('ENABLE_AUTHENTICATION', 'false').lower() == 'true'


@app.template_filter('markdown')
def render_markdown(text):
    """Render Markdown text to HTML"""
    renderer = mistune.create_markdown(
        escape=False,
        plugins=['strikethrough', 'footnotes', 'table']
    )

    # Render the markdown as-is - let mistune handle proper formatting
    return Markup(renderer(text))


@app.route("/health")
def health_check():
    return "healthy"


def get_current_user_id():
    """get the currently logged in user from Cognito headers or fallback for non-authenticated mode"""
    import base64
    import json
    
    if auth_enabled:
        # ALB forwards Cognito user info in headers
        email = request.headers.get('x-amzn-oidc-data')
        if email:
            # Decode the JWT payload (middle part)
            try:
                payload = email.split('.')[1]
                # Add padding if needed
                payload += '=' * (4 - len(payload) % 4)
                decoded = base64.b64decode(payload)
                user_data = json.loads(decoded)
                email_address = user_data.get('email', 'unknown-user')
                # Encode email with base64 to comply with actorId pattern [a-zA-Z0-9][a-zA-Z0-9-_/]*
                return base64.b64encode(email_address.encode()).decode().rstrip('=')
            except Exception as e:
                logging.warning(f"Failed to decode user data: {e}")
        
        # Fallback for development/testing - also encode to maintain consistency
        fallback_user = request.headers.get('x-amzn-oidc-identity', 'user-1')
        return base64.b64encode(fallback_user.encode()).decode().rstrip('=')
    else:
        # Non-authenticated mode - use a default user
        default_user = 'anonymous-user'
        return base64.b64encode(default_user.encode()).decode().rstrip('=')


def get_current_user_email():
    """get the currently logged in user's email for display"""
    import base64
    import json
    
    if auth_enabled:
        # ALB forwards Cognito user info in headers
        email = request.headers.get('x-amzn-oidc-data')
        if email:
            # Decode the JWT payload (middle part)
            try:
                payload = email.split('.')[1]
                # Add padding if needed
                payload += '=' * (4 - len(payload) % 4)
                decoded = base64.b64decode(payload)
                user_data = json.loads(decoded)
                return user_data.get('email', 'Unknown User')
            except Exception as e:
                logging.warning(f"Failed to decode user data: {e}")
        
        # Fallback for development/testing
        return request.headers.get('x-amzn-oidc-identity', 'Test User')
    else:
        # Non-authenticated mode
        return 'Anonymous User'


def get_chat_history(user_id):
    """
    fetches the user's latest chat history
    """
    logging.info(f"fetching chat history for user {user_id}")

    # fetch last 10 questions from db
    return db.list_by_user(user_id, 10)


@app.route("/")
def index():
    """home page"""
    user_email = get_current_user_email() if auth_enabled else None
    return render_template("index.html", conversation={}, user_email=user_email, auth_enabled=auth_enabled)


@app.route("/logout")
def logout():
    """logout route - expires ALB auth cookies and redirects to Cognito logout"""
    if not auth_enabled:
        return redirect(url_for('index'))
    
    # Get Cognito logout URL
    cognito_logout_url = os.environ.get('COGNITO_LOGOUT_URL')
    if not cognito_logout_url:
        return redirect('/')
    
    # Create response that redirects to Cognito logout
    response = redirect(cognito_logout_url)
    
    # Expire ALB authentication session cookies
    # ALB can create up to 4 cookie shards (AWSELBAuthSessionCookie-0 to AWSELBAuthSessionCookie-3)
    for i in range(4):
        cookie_name = f"AWSELBAuthSessionCookie-{i}"
        response.set_cookie(
            cookie_name,
            value='',
            expires=0,  # Expire immediately
            path='/',
            secure=True,
            httponly=True
        )
    
    return response


@app.route("/new", methods=["POST"])
def new():
    """POST /new starts a new conversation"""
    return render_template("chat.html", conversation={})


@app.route("/conversations")
def conversations():
    """GET /conversations returns just the conversation history"""
    user_id = get_current_user_id()
    user_email = get_current_user_email() if auth_enabled else None
    return render_template("conversations.html", chat_history=get_chat_history(user_id), user_email=user_email, auth_enabled=auth_enabled)


@app.route("/ask", methods=["POST"])
def ask():
    """POST /ask adds a new Q&A to the conversation"""

    # get conversation id and question from form
    if "conversation_id" not in request.values:
        m = "missing required form data: conversation_id"
        logging.error(m)
        abort(400, m)
    id = request.values["conversation_id"]
    logging.info(f"conversation id: {id}")

    if "question" not in request.values:
        m = "missing required form data: question"
        logging.error(m)
        abort(400, m)
    question = request.values["question"]
    question = question.rstrip()
    logging.info(f"question: {question}")
    logging.info(f"id: {id}")

    user_id = get_current_user_id()

    is_new_conversation = (id == "")
    if is_new_conversation:
        id = str(uuid.uuid4())

    conversation = {
        "conversationId": id,
        "userId": user_id,
        "questions": [],
    }

    _, conversation, sources = ask_internal(conversation, question)

    # Only render the chat content, not the entire body
    response = render_template("chat.html",
                               conversation=conversation,
                               sources=sources)

    # If this is a new conversation, also update the conversation history
    if is_new_conversation:

        utc_datetime = datetime.now(timezone.utc)
        local_datetime = utc_datetime.astimezone()

        # Manual 12-hour format conversion
        hour = local_datetime.hour
        am_pm = "AM" if hour < 12 else "PM"
        hour_12 = hour if hour == 0 or hour == 12 else hour % 12
        if hour_12 == 0:
            hour_12 = 12

        current_datetime = f"{local_datetime.month}/{local_datetime.day}/{local_datetime.year} {hour_12}:{local_datetime.minute:02d} {am_pm}"

        new_history_item = {
            "conversationId": id,
            "initial_question": question,
            "created": current_datetime,
        }
        conversation_item = render_template(
            "conversation_item.html", item=new_history_item)

        # Use out-of-band swap to prepend to conversation list
        response += f'<div hx-swap-oob="afterbegin:#conversation-list">{conversation_item}</div>'

    return response


def ask_internal(conversation, question):
    """
    core ask implementation shared by app and api.
    """

    # RAG orchestration to get answer
    answer, sources = orchestrator.orchestrate(conversation, question)

    conversation_id = conversation["conversationId"]
    user_id = conversation["userId"]

    # fetch latest conversation
    conversation = db.get(conversation_id, user_id)
    sources = []

    return answer, conversation, sources


if __name__ == '__main__':
    port = 8080
    print(f"listening on http://localhost:{port}")
    app.run(host="0.0.0.0", port=port)


@app.route("/conversation/<id>", methods=["GET"])
def get_conversation(id):
    """GET /conversation/<id> fetches a conversation by id"""

    user_id = get_current_user_id()
    conversation = db.get(id, user_id)
    return render_template("chat.html", conversation=conversation)


@app.route("/api/ask", methods=["POST"])
def ask_api_new():
    """returns an answer to a question in a new conversation"""

    # get request json from body
    body = request.get_json()
    log.debug(body)
    if "question" not in body:
        m = "missing field: question"
        logging.error(m)
        abort(400, m)
    question = body["question"]

    user_id = get_current_user_id()
    
    conversation = {
        "conversationId": str(uuid.uuid4()),
        "userId": user_id,
        "questions": [],
    }

    answer, conversation, sources = ask_internal(conversation, question)

    return {
        "conversationId": conversation["conversationId"],
        "answer": answer,
        "sources": sources,
    }


@app.route("/api/ask/<id>", methods=["POST"])
def ask_api(id):
    """returns an answer to a question in a conversation"""

    # get request json from body
    body = request.get_json()
    log.debug(body)
    if "question" not in body:
        m = "missing field: question"
        logging.error(m)
        abort(400, m)
    question = body["question"]

    user_id = get_current_user_id()

    if id == "":
        m = "conversation id is required"
        logging.error(m)
        abort(400, m)
    else:
        conversation = db.get(id, user_id)
        logging.info("fetched conversation")
        log.debug(conversation)

    answer, _, sources = ask_internal(conversation, question)

    return {
        "conversationId": id,
        "answer": answer,
        "sources": sources,
    }


@app.route("/api/conversations/users/<user_id>")
def conversations_get_by_user(user_id):
    """fetch top 10 conversations for a user"""
    return db.list_by_user(user_id, 10)
