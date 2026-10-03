FROM python:3.12-slim

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    HEAP_DATABASE_PATH=/data/heap.sqlite \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.9.22 /uv /uvx /bin/
COPY pyproject.toml uv.lock ./
COPY src ./src

RUN uv sync --locked --no-dev \
    && groupadd --system heap \
    && useradd --system --gid heap --home-dir /nonexistent heap \
    && mkdir /data \
    && chown heap:heap /data

USER heap:heap

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8000/healthz', timeout=2)"

CMD ["/app/.venv/bin/uvicorn", "heap.interface.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
