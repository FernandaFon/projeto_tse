#!/usr/bin/env bash
# Prepara o ambiente e roda o pipeline completo do projeto TSE (Linux e macOS).
#
#   ./iniciar.sh                    # tudo: SQL Server -> extração -> carga -> T-SQL
#   ./iniciar.sh --pular-extracao   # reaproveita data/silver
#   ./iniciar.sh --sem-tsql         # para depois da carga em stg
#   ./iniciar.sh --forcar           # baixa e refaz tudo
#
# Único pré-requisito: Docker. Se ele faltar, o script oferece instalar.
# Python, uv e o ODBC Driver 18 rodam dentro de um container (veja o Dockerfile).
set -euo pipefail

cd "$(dirname "$0")"

if [ -t 1 ]; then AZUL=$'\e[1;36m'; VERDE=$'\e[1;32m'; AMARELO=$'\e[1;33m'; VERMELHO=$'\e[1;31m'; FIM=$'\e[0m'
else AZUL=; VERDE=; AMARELO=; VERMELHO=; FIM=; fi
etapa() { printf '\n%s==> %s%s\n' "$AZUL" "$1" "$FIM"; }
ok()    { printf '%s[OK]%s %s\n' "$VERDE" "$FIM" "$1"; }
aviso() { printf '%s[AVISO]%s %s\n' "$AMARELO" "$FIM" "$1"; }
erro()  { printf '\n%s[ERRO]%s %s\n' "$VERMELHO" "$FIM" "$1" >&2; exit 1; }

confirmar() {  # pergunta S/n; sem terminal interativo, responde "não"
    [ -t 0 ] || return 1
    read -r -p "$1 [S/n] " resp
    case "${resp:-s}" in [sSyY]*) return 0 ;; *) return 1 ;; esac
}

case "${1:-}" in
    -h|--help|--ajuda) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

# ---------------------------------------------------------------- 1. Docker instalado
instalar_docker() {
    if [ "$(uname -s)" = "Darwin" ]; then
        erro "Instale o Docker Desktop para Mac (https://docs.docker.com/desktop/setup/install/mac-install/
       ou 'brew install --cask docker'), abra-o uma vez e rode este script de novo."
    fi
    local cmd
    if command -v pacman >/dev/null; then
        cmd="sudo pacman -S --needed --noconfirm docker docker-compose docker-buildx"
    elif command -v apt-get >/dev/null || command -v dnf >/dev/null || command -v yum >/dev/null; then
        cmd="curl -fsSL https://get.docker.com | sudo sh"   # script oficial da Docker
    else
        erro "Distribuição não reconhecida. Instale o Docker seguindo https://docs.docker.com/engine/install/
       e rode este script de novo."
    fi
    aviso "Docker não encontrado."
    confirmar "Instalar o Docker agora com: $cmd ?" \
        || erro "Instale o Docker (https://docs.docker.com/engine/install/) e rode este script de novo."
    bash -c "$cmd"
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    aviso "Seu usuário entrou no grupo 'docker'. Até fazer logout/login, este script usa sudo."
}

etapa "1/5 Conferindo o Docker"
command -v docker >/dev/null || instalar_docker
ok "$(docker --version)"

# ---------------------------------------------------------------- 2. Docker em execução
DOCKER=(docker)
docker_responde() { "${DOCKER[@]}" info >/dev/null 2>&1; }

etapa "2/5 Conferindo se o Docker está em execução"
if ! docker_responde; then
    saida_info="$(docker info 2>&1 || true)"  # com pipefail, um pipe com "docker info" falharia sempre
    if grep -qi "permission denied" <<<"$saida_info"; then
        aviso "Sem permissão no Docker (usuário fora do grupo 'docker'). Usando sudo nesta execução."
        DOCKER=(sudo env "HOST_UID=$(id -u)" "HOST_GID=$(id -g)" docker)
    elif [ "$(uname -s)" = "Darwin" ]; then
        aviso "Abrindo o Docker Desktop..."
        open -a Docker || true
    elif command -v systemctl >/dev/null; then
        aviso "Iniciando o serviço do Docker (pode pedir sua senha)..."
        sudo systemctl start docker
    fi
    for _ in $(seq 1 60); do docker_responde && break; sleep 3; done
    docker_responde || erro "O Docker não respondeu. Inicie-o manualmente e rode este script de novo."
fi
ok "Docker em execução"

"${DOCKER[@]}" compose version >/dev/null 2>&1 \
    || erro "Falta o Docker Compose v2 (comando 'docker compose'). Veja https://docs.docker.com/compose/install/"

# ---------------------------------------------------------------- 3. Arquivo .env
etapa "3/5 Configuração (.env)"
if [ -f .env ]; then
    ok ".env já existe (mantido)"
else
    # senha forte aleatória: maiúscula, minúscula, número e símbolo (regra do SQL Server)
    senha="Tse_$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')!"
    if [ -f .env.example ]; then
        sed "s/^MSSQL_SA_PASSWORD=.*/MSSQL_SA_PASSWORD=$senha/" .env.example > .env
    else
        printf 'MSSQL_SA_PASSWORD=%s\n' "$senha" > .env
    fi
    ok ".env criado com uma senha aleatória (veja o arquivo .env)"
fi

# grava data/ com o seu usuário, e não como root
HOST_UID="$(id -u)"; HOST_GID="$(id -g)"; export HOST_UID HOST_GID
mkdir -p data

# ---------------------------------------------------------------- 4. SQL Server
etapa "4/5 Subindo o SQL Server (a primeira vez baixa a imagem, ~1,5 GB)"
"${DOCKER[@]}" compose up -d --wait sqlserver
ok "SQL Server pronto"

# ---------------------------------------------------------------- 5. Pipeline
etapa "5/5 Rodando o pipeline (a primeira execução leva de 30 a 60 min)"
"${DOCKER[@]}" compose run --rm --build pipeline python pipelines/run_all.py --sem-docker "$@"

porta="$(grep -E '^MSSQL_PORT=' .env | cut -d= -f2 || true)"
printf '\n%sTudo pronto!%s\n' "$VERDE" "$FIM"
cat <<EOF
Banco: servidor 127.0.0.1, porta ${porta:-1433}, banco tse_warehouse, usuário sa
       (a senha está no arquivo .env; no DBeaver, marque trustServerCertificate=true)
Para parar o SQL Server: docker compose stop   |   apagar o banco: docker compose down -v
EOF
