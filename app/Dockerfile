# syntax=docker/dockerfile:1

# ---- builder: install dependencies into a venv -----------------------------
FROM python:3.12-slim AS builder

WORKDIR /app
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

COPY requirements.txt .
RUN python -m venv /venv \
    && /venv/bin/pip install -r requirements.txt

# ---- runtime: minimal image with a non-root user ---------------------------
FROM python:3.12-slim AS runtime

# Build metadata, surfaced by the app at /api/info.
ARG APP_VERSION=0.0.0-dev
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA} \
    PATH="/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

# Run as an unprivileged user.
RUN useradd --create-home --uid 10001 appuser
WORKDIR /app

COPY --from=builder /venv /venv
COPY --chown=appuser:appuser main.py ./main.py

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status==200 else 1)"

# Serve the FastAPI app. `main:app` because main.py is copied to the workdir.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
