"""A small FastAPI service used to demonstrate the CI/CD + GitOps pipeline.

Endpoints:
    GET /            -> service metadata
    GET /healthz     -> liveness/readiness probe
    GET /api/info    -> runtime info (hostname, version, git sha)
"""

from __future__ import annotations

import os
import socket

from fastapi import FastAPI

# APP_VERSION and GIT_SHA are injected at build/deploy time (see Dockerfile and
# the Kubernetes manifests). They let you confirm which image a pod is running.
APP_VERSION = os.getenv("APP_VERSION", "0.0.0-dev")
GIT_SHA = os.getenv("GIT_SHA", "unknown")

app = FastAPI(
    title="gitops-cicd-demo",
    version=APP_VERSION,
    description="Sample service deployed by a GitHub Actions -> GHCR -> Argo CD pipeline.",
)


@app.get("/")
def root() -> dict:
    """Return basic service metadata."""
    return {
        "service": "gitops-cicd-demo",
        "version": APP_VERSION,
        "message": "Deployed via GitHub Actions + Argo CD GitOps.",
    }


@app.get("/healthz")
def healthz() -> dict:
    """Health check used by Kubernetes liveness/readiness probes."""
    return {"status": "ok"}


@app.get("/api/info")
def info() -> dict:
    """Return runtime details useful for verifying a rollout."""
    return {
        "hostname": socket.gethostname(),
        "version": APP_VERSION,
        "git_sha": GIT_SHA,
    }
