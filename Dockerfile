# Imagem do pipeline: Python + dependências + ODBC Driver 18, para que ninguém precise
# instalar Python, uv ou o driver da Microsoft na própria máquina. Só o Docker.
# O código do projeto NÃO é copiado: o docker-compose monta a pasta do projeto em /app,
# então alterações em pipelines/ e sql/ valem sem rebuild.
FROM python:3.14-slim-bookworm

ARG DEBIAN_FRONTEND=noninteractive

# ODBC Driver 18 for SQL Server (repositório oficial da Microsoft para Debian 12).
# ACCEPT_EULA=Y aceita a licença do driver, como no passo manual do README.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gnupg ca-certificates \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
       | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl -fsSL https://packages.microsoft.com/config/debian/12/prod.list \
       -o /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends msodbcsql18 unixodbc \
    && apt-get purge -y gnupg && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:0.11.16 /uv /usr/local/bin/uv

# O ambiente virtual fica fora de /app para não colidir com o .venv da máquina do usuário
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/opt/venv/bin:$PATH

WORKDIR /app
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-install-project --no-dev

CMD ["python", "pipelines/run_all.py", "--sem-docker"]
