FROM ubuntu:24.04

# How to install uv
COPY --from=ghcr.io/astral-sh/uv:0.13.7 /uv /uvx /bin/

WORKDIR /workspace

# Handling the enviroment
COPY pyproject.toml uv.lock .python-version ./
ENV UV_PROJECT_ENVIRONMENT=/opt/venv

RUN uv sync --locked
