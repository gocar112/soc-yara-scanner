# Security Suite - container image.
#
# docker-compose.yml referenced `build: .` for a Dockerfile that was never in
# the repository, so `docker compose up` could not work. This is that file.
#
# Runs as a non-root user. The suite's remediation rails delete and quarantine
# files, and a container that can do that as root can do it to anything it has
# mounted.
FROM python:3.12-slim AS base

# yara-python publishes manylinux wheels, so no compiler is needed at runtime.
# build-essential is present only while pip resolves, then dropped with the
# builder layer.
FROM base AS builder
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
COPY requirements.txt /tmp/requirements.txt
RUN python -m pip install --no-cache-dir --prefix=/install \
    --requirement /tmp/requirements.txt

FROM base AS runtime
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
COPY --from=builder /install /usr/local

RUN useradd --create-home --uid 10001 suite
WORKDIR /app
COPY --chown=suite:suite . /app

# Writable state. Named volumes mount over these in docker-compose.yml.
RUN mkdir -p /app/data /app/uploads /app/quarantine /app/nvds \
 && chown -R suite:suite /app/data /app/uploads /app/quarantine /app/nvds
USER suite

EXPOSE 8787

# Binding 0.0.0.0 here is safe *only* because compose publishes the port to the
# host's loopback interface, and because the server still refuses any request
# whose Host header is not a localhost name. Inside a container 127.0.0.1 would
# be unreachable from the host entirely.
HEALTHCHECK --interval=30s --timeout=4s --start-period=40s --retries=3 \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8787/api/state',timeout=3)" || exit 1

CMD ["python", "run.py", "--headless", "--no-browser", "--host", "0.0.0.0"]
