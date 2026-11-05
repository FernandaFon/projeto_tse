<#
  Prepara um Windows (ex.: o do WinBoat) para o Claude Code trabalhar no dashboard Power BI
  de forma autônoma: recarregar o relatório, tirar print das páginas e consultar o modelo em DAX.

  Rode no PowerShell do Windows, direto da pasta compartilhada:
    powershell -ExecutionPolicy Bypass -File \\host.lan\Data\Projects\projeto_tse\scripts\preparar-windows.ps1

  Instala (pelo winget, só o que faltar): Git for Windows, Node.js LTS e uv.
  Depois: pbir-cli, uma unidade de rede para a pasta compartilhada, o MCP de modelagem
  do Power BI (Microsoft) e os plugins pbip/reports do Claude Code, só para este projeto.
  Compatível com o Windows PowerShell 5.1 que já vem no Windows. Pode ser rodado de novo.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Etapa($m)  { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m)     { Write-Host "[OK] $m" -ForegroundColor Green }
function Aviso($m)  { Write-Host "[AVISO] $m" -ForegroundColor Yellow }
function Falhar($m) { Write-Host "`n[ERRO] $m" -ForegroundColor Red; exit 1 }
function Atualizar-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
# Via cmd: evita que o PowerShell 5.1 mexa em argumentos como "--" ou trate a saída de erro como exceção.
# Out-Host mostra a saída sem devolvê-la: a função retorna só o código de saída.
function Rodar($linha) { cmd /c $linha | Out-Host; return $LASTEXITCODE }

$Projeto = Split-Path -Parent $PSScriptRoot
$Compartilhado = '\\host.lan\Data'

# ---------------------------------------------------------------- 1. PATH
Etapa "1/6 PATH do usuário (Claude Code e ferramentas do uv)"
$bin = Join-Path $HOME '.local\bin'
$pathUsuario = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $pathUsuario) { $pathUsuario = '' }
if (($pathUsuario -split ';') -notcontains $bin) {
    [Environment]::SetEnvironmentVariable('Path', ($pathUsuario.TrimEnd(';') + ';' + $bin).TrimStart(';'), 'User')
    Ok "$bin adicionado ao PATH"
} else {
    Ok "$bin já está no PATH"
}
Atualizar-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Falhar "Claude Code não encontrado. Instale com: irm https://claude.ai/install.ps1 | iex"
}

# ---------------------------------------------------------------- 2. Programas
Etapa "2/6 Git, Node.js e uv"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Falhar "winget não encontrado. Instale o 'App Installer' pela Microsoft Store e rode de novo."
}
$pacotes = @(
    @{ cmd = 'git';  id = 'Git.Git';           nome = 'Git for Windows' },
    @{ cmd = 'node'; id = 'OpenJS.NodeJS.LTS'; nome = 'Node.js LTS (para o MCP da Microsoft)' },
    @{ cmd = 'uv';   id = 'astral-sh.uv';      nome = 'uv (para o pbir-cli)' }
)
foreach ($p in $pacotes) {
    if (Get-Command $p.cmd -ErrorAction SilentlyContinue) { Ok "$($p.nome) já instalado"; continue }
    Write-Host "Instalando $($p.nome)..."
    winget install -e --id $p.id --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Falhar "Falha ao instalar $($p.nome) (código $LASTEXITCODE)." }
    Atualizar-Path
    Ok "$($p.nome) instalado"
}

# ---------------------------------------------------------------- 3. pbir-cli
Etapa "3/6 pbir-cli (recarrega o relatório e tira print das páginas)"
if (Get-Command pbir -ErrorAction SilentlyContinue) {
    if ((Rodar "uv tool upgrade pbir-cli") -ne 0) { Aviso "Não consegui atualizar o pbir-cli; mantendo a versão instalada." }
} elseif ((Rodar "uv tool install pbir-cli") -ne 0) {
    Falhar "Falha ao instalar o pbir-cli."
}
Atualizar-Path
Ok ((cmd /c "pbir --version 2>&1") -join ' ')

# ---------------------------------------------------------------- 4. Unidade de rede
Etapa "4/6 Unidade de rede para a pasta compartilhada"
$ProjetoLocal = $Projeto
if ($Projeto.StartsWith($Compartilhado, [StringComparison]::OrdinalIgnoreCase)) {
    # Git, Node e o Claude Code trabalham melhor com letra de unidade do que com caminho \\servidor
    $unidade = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $_.DisplayRoot -and $_.DisplayRoot.TrimEnd('\') -ieq $Compartilhado } |
        Select-Object -First 1
    if ($unidade) {
        $letra = $unidade.Name
        Ok "$Compartilhado já está mapeado em ${letra}:"
    } else {
        $letra = @('Z', 'Y', 'X', 'W', 'V') | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
        if (-not $letra) { Falhar "Nenhuma letra livre entre Z e V para mapear $Compartilhado." }
        if ((Rodar "net use ${letra}: $Compartilhado /persistent:yes") -ne 0) { Falhar "Não consegui mapear $Compartilhado." }
        Ok "$Compartilhado mapeado em ${letra}:"
    }
    $ProjetoLocal = "${letra}:" + $Projeto.Substring($Compartilhado.Length)
}
Ok "Projeto em $ProjetoLocal"

# A pasta pertence ao usuário do Linux: sem isto o Git recusa o repositório ("dubious ownership")
$seguro = $ProjetoLocal.Replace('\', '/')
$existentes = @(cmd /c "git config --global --get-all safe.directory 2>nul")
if ($existentes -notcontains $seguro) {
    Rodar "git config --global --add safe.directory `"$seguro`"" | Out-Null
    Ok "Git: $seguro marcado como seguro"
}

# ---------------------------------------------------------------- 5. MCP
Etapa "5/6 MCP de modelagem do Power BI (Microsoft)"
Push-Location $ProjetoLocal
try {
    if ((Rodar "claude mcp get powerbi-modeling >nul 2>&1") -eq 0) {
        Ok "powerbi-modeling já configurado"
    } else {
        # No Windows, servidores MCP via npx precisam do "cmd /c"
        $r = Rodar "claude mcp add powerbi-modeling -s local -- cmd /c npx -y @microsoft/powerbi-modeling-mcp@latest --start"
        if ($r -ne 0) { Falhar "Não consegui registrar o MCP powerbi-modeling." }
        Ok "powerbi-modeling registrado (o EULA da Microsoft é pedido no primeiro uso)"
    }

    # ------------------------------------------------------------ 6. Plugins
    Etapa "6/6 Plugins do Claude Code para Power BI (pbip e reports)"
    $mk = 'power-bi-agentic-development'
    if ((Rodar "claude plugin marketplace add data-goblin/power-bi-agentic-development --scope local") -ne 0) {
        Aviso "Marketplace não adicionado (talvez já exista); seguindo."
    }
    foreach ($plugin in @('pbip', 'reports')) {
        if ((Rodar "claude plugin install $plugin@$mk --scope local") -ne 0) {
            Aviso "Plugin $plugin não instalado (talvez já esteja); seguindo."
        } else {
            Ok "Plugin $plugin instalado"
        }
    }
} finally {
    Pop-Location
}

Write-Host "`nTudo pronto!" -ForegroundColor Green
Write-Host "1. Abra no Power BI Desktop: $ProjetoLocal\powerbi\DashboardTSE.pbip e clique em Atualizar."
Write-Host "2. Abra um PowerShell NOVO e rode:  cd $ProjetoLocal ; claude"
Write-Host "3. Na primeira vez, aceite o EULA do MCP da Microsoft e aprove os comandos 'pbir' quando o Claude pedir."
