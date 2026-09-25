# syntax=docker/dockerfile:1
#
# Token refresher image. Non-root, minimal, works with a read-only root
# filesystem (all writes go to the mounted emptyDir at /tmp).
#
# For production, pin the base image by digest:
#   FROM python:3.14-slim@sha256:<digest>
FROM python:3.14-slim

# uv — fast, reproducible Python installer (https://docs.astral.sh/uv/).
# Build-time-only tool, pinned by tag (Dependabot tracks it); pin by digest for
# production builds.
COPY --from=ghcr.io/astral-sh/uv:0.12.19 /uv /uvx /bin/

# Create a non-root user matching the pod securityContext runAsUser (10001).
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 --home-dir /app --no-create-home app

WORKDIR /app

ENV UV_NO_CACHE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install dependencies first for better layer caching.
COPY requirements.txt /app/requirements.txt
RUN uv pip install --system --no-cache -r /app/requirements.txt

COPY refresh_token.py /app/refresh_token.py

# Drop privileges.
USER 10001

ENTRYPOINT ["python", "/app/refresh_token.py"]
