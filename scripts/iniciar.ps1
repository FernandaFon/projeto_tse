<#
  Prepara o ambiente e roda o pipeline completo do projeto TSE no Windows.
  Normalmente é chamado pelo iniciar.bat (duplo clique). Argumentos são repassados ao pipeline:
    iniciar.bat                    tudo: SQL Server -> extração -> carga -> T-SQL
    iniciar.bat --pular-extracao   reaproveita data\silver
    iniciar.bat --sem-tsql         para depois da carga em stg
    iniciar.bat --forcar           baixa e refaz tudo

  Único pré-requisito: Docker Desktop (o script oferece instalar com o winget).
  Python, uv e o ODBC Driver 18 rodam dentro de um container (veja o Dockerfile).
  Compatível com o Windows PowerShell 5.1 que já vem no Windows.
#>

# Sem bloco param(): assim argumentos como --pular-extracao chegam intactos em $args
$repassar = @($args)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
[Console]::OutputEncoding = [Text.Encoding]::UTF8  # acentos na saída do Docker e do Python

function Etapa($m)  { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)     { Write-Host "[OK] $m" -ForegroundColor Green }
function Aviso($m)  { Write-Host "[AVISO] $m" -ForegroundColor Yellow }
function Falhar($m) { Write-Host "`n[ERRO] $m" -ForegroundColor Red; exit 1 }
function Confirmar($m) {
    $r = Read-Host "$m [S/n]"
    return ($r -eq '' -or $r -match '^[sSyY]')
}
# Via cmd para que a saída de erro do docker não vire exceção no PowerShell 5.1
function Docker-Responde { cmd /c "docker info >nul 2>&1"; return ($LASTEXITCODE -eq 0) }

# ---------------------------------------------------------------- 1. Docker instalado
Etapa "1/5 Conferindo o Docker"
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Aviso "Docker Desktop não encontrado."

    # O Docker Desktop usa o WSL 2
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        cmd /c "wsl --status >nul 2>&1"
        if ($LASTEXITCODE -ne 0) {
            if (-not (Confirmar "O Docker Desktop precisa do WSL 2, que não está instalado. Instalar agora (pede administrador)?")) {
                Falhar "Instale o WSL 2 (comando: wsl --install) e rode o iniciar.bat de novo."
            }
            Start-Process wsl -ArgumentList '--install', '--no-distribution' -Verb RunAs -Wait
            Aviso "WSL instalado. REINICIE o computador e rode o iniciar.bat de novo."
            exit 0
        }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Falhar "Instale o Docker Desktop (https://docs.docker.com/desktop/setup/install/windows-install/) e rode o iniciar.bat de novo."
    }
    if (-not (Confirmar "Instalar o Docker Desktop agora com o winget?")) {
        Falhar "Instale o Docker Desktop (https://docs.docker.com/desktop/setup/install/windows-install/) e rode o iniciar.bat de novo."
    }
    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Falhar "A instalação do Docker Desktop falhou (código $LASTEXITCODE)." }
    Aviso "Docker Desktop instalado. Se o instalador pedir, reinicie o computador. Depois rode o iniciar.bat de novo."
    exit 0  # esta janela ainda não enxerga o comando docker no PATH
}
Ok ((docker --version) -join ' ')

# ---------------------------------------------------------------- 2. Docker em execução
Etapa "2/5 Conferindo se o Docker está em execução"
if (-not (Docker-Responde)) {
    $exe = Join-Path $Env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $exe) {
        Aviso "Abrindo o Docker Desktop (na primeira vez, aceite os termos na janela dele)..."
        Start-Process $exe
    } else {
        Aviso "Abra o Docker Desktop manualmente."
    }
    $limite = (Get-Date).AddMinutes(4)
    while (-not (Docker-Responde)) {
        if ((Get-Date) -gt $limite) {
            Falhar "O Docker não respondeu em 4 minutos. Abra o Docker Desktop, espere o status 'Engine running' e rode de novo."
        }
        Start-Sleep -Seconds 5
    }
}
Ok "Docker em execução"

cmd /c "docker compose version >nul 2>&1"
if ($LASTEXITCODE -ne 0) { Falhar "Falta o Docker Compose v2 (comando 'docker compose'). Atualize o Docker Desktop." }

# ---------------------------------------------------------------- 3. Arquivo .env
Etapa "3/5 Configuração (.env)"
if (Test-Path .env) {
    Ok ".env já existe (mantido)"
} else {
    # senha forte aleatória: maiúscula, minúscula, número e símbolo (regra do SQL Server)
    $bytes = New-Object byte[] 12
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $senha = 'Tse_' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '') + '!'
    if (Test-Path .env.example) {
        $linhas = Get-Content .env.example -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^MSSQL_SA_PASSWORD=') { "MSSQL_SA_PASSWORD=$senha" } else { $_ }
        }
    } else {
        $linhas = @("MSSQL_SA_PASSWORD=$senha")
    }
    # UTF-8 sem BOM: com BOM, o Docker e o python-dotenv leriam errado a primeira variável
    $destino = Join-Path (Get-Location) '.env'
    [IO.File]::WriteAllText($destino, (($linhas -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
    Ok ".env criado com uma senha aleatória (veja o arquivo .env)"
}
New-Item -ItemType Directory -Force data | Out-Null

# ---------------------------------------------------------------- 4. SQL Server
Etapa "4/5 Subindo o SQL Server (a primeira vez baixa a imagem, ~1,5 GB)"
docker compose up -d --wait sqlserver
if ($LASTEXITCODE -ne 0) { Falhar "O SQL Server não subiu. Veja o log com: docker compose logs sqlserver" }
Ok "SQL Server pronto"

# ---------------------------------------------------------------- 5. Pipeline
Etapa "5/5 Rodando o pipeline (a primeira execução leva de 30 a 60 min)"
docker compose run --rm --build pipeline python pipelines/run_all.py --sem-docker @repassar
if ($LASTEXITCODE -ne 0) { Falhar "O pipeline falhou (veja a mensagem acima). Rode de novo: o que já foi feito é reaproveitado." }

$porta = (Select-String -Path .env -Pattern '^MSSQL_PORT=(.+)$' | Select-Object -First 1)
$porta = if ($porta) { $porta.Matches[0].Groups[1].Value } else { '1433' }
Write-Host "`nTudo pronto!" -ForegroundColor Green
Write-Host "Banco: servidor localhost,$porta  banco tse_warehouse  usuário sa (senha no arquivo .env)"
Write-Host "Power BI Desktop: Obter dados > SQL Server > localhost,$porta"
Write-Host "Para parar o SQL Server: docker compose stop   |   apagar o banco: docker compose down -v"
