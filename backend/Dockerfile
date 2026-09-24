# Optimized for Raspberry Pi 5 (arm64 / aarch64) - Debian bookworm
FROM python:3.11-slim-bookworm

# Labels for maintenance
LABEL maintainer="Private AI Bridge"
LABEL architecture="arm64"
LABEL description="FastAPI + dsk for Huawei Watch GT6 bridge"

# Env: Python optimized
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive

# Install system deps: only essentials for curl-cffi + wasmtime
# --no-install-recommends = smaller image, less attack surface
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    build-essential \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

WORKDIR /app

# Copy requirements first (Docker layer caching)
COPY requirements.txt .

# Install Python deps
# 1. Upgrade pip
# 2. Install requirements
# 3. Install dsk directly from git (latest) - because no PyPI package
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt && \
    pip install "git+https://github.com/xtekky/deepseek4free.git" && \
    # Verify wasmtime works on arm64
    python -c "import wasmtime; print('wasmtime OK')" && \
    python -c "import curl_cffi; print('curl-cffi OK')"

# Copy app code
COPY app.py .
# Optional: copy .env if exists (but better via docker-compose env_file)
# COPY .env .env

# Create non-root user for security (Pi best practice)
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Healthcheck: lightweight, every 30s, no curl needed (use python)
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3)" || exit 1

# Run with uvicorn - optimized for Pi5:
# --workers 1 (Pi5 RAM), --loop uvloop if available, --http httptools
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--log-level", "info"]
