# syntax=docker/dockerfile:1
#
# Token refresher image. Non-root, minimal, works with a read-only root
# filesystem (all writes go to the mounted emptyDir at /tmp).
#
# For production, pin the base image by digest:
#   FROM python:3.12-slim@sha256:<digest>
FROM python:3.12-slim

# Create a non-root user matching the pod securityContext runAsUser (10001).
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 --home-dir /app --no-create-home app

WORKDIR /app

# Install dependencies first for better layer caching.
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --require-hashes=false -r /app/requirements.txt

COPY refresh_token.py /app/refresh_token.py

# Drop privileges.
USER 10001

# Do not buffer stdout/stderr so logs stream promptly.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

ENTRYPOINT ["python", "/app/refresh_token.py"]
