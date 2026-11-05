# Dados Abertos de Votação do TSE (2022): equipe DevLivery

Pipeline local e automatizado que baixa os dados de votação do TSE, filtra as quatro capitais do Sudeste
(São Paulo, Rio de Janeiro, Belo Horizonte e Vitória), carrega tudo no SQL Server (Docker) e prepara a limpeza em T-SQL.

Projeto da Faculdade Impacta (Innovation Lab: Applied BI, Relational Database Programming e Business Intelligence), semestre 2026.2.
Fonte dos dados: [Portal de Dados Abertos do TSE](https://dadosabertos.tse.jus.br/), licença Creative Commons Atribuição. **Cite o TSE como fonte em qualquer produto derivado.**

---

## Como o pipeline funciona

```
TSE (cdn.tse.jus.br)
   │  01_extract_tse.py
   ▼
data/bronze/   ZIPs originais + manifesto.jsonl (URL, SHA-256, data)
   │  filtro por blocos nas 4 capitais
   ▼
data/silver/   Parquet (tudo como texto), particionado por uf=/ano=
   │  02_load_staging.py
   ▼
SQL Server (Docker)  schema [stg]  (tabelas stg.stg_<dataset>)
   │  03_run_tsql.py  (scripts em sql/*.sql)
   ▼
Tabelas limpas / star schema  ──►  DBeaver, Metabase ou Power BI
```

Escopo desta versão: **somente 2022**, rodando 100% na máquina local.

---

## Início rápido (recomendado)

O único programa necessário é o **Docker**. Python, `uv` e o ODBC Driver 18 rodam dentro de um container,
e o script de início instala ou configura o que faltar.

**1. Baixe o projeto:** `git clone https://github.com/FernandaFon/projeto_tse.git` ou, sem Git,
**Code → Download ZIP** no GitHub e extraia a pasta.

**2. Rode o script de início:**

| Windows | Linux / macOS |
|---|---|
| Dê **duplo clique** em `iniciar.bat` | No terminal, dentro da pasta: `./iniciar.sh` |

O script faz, em ordem:

1. confere o Docker e, se faltar, oferece instalar (Windows: WSL 2 e Docker Desktop pelo `winget`;
   Linux: script oficial da Docker ou `pacman`; macOS: indica o Docker Desktop);
2. inicia o Docker se ele estiver parado;
3. cria o `.env` com uma senha forte aleatória, se ele ainda não existir;
4. sobe o SQL Server e espera ele ficar pronto;
5. roda o pipeline inteiro no container: extração, carga e T-SQL.

A primeira execução leva de 30 a 60 minutos (cerca de 3 GB de downloads do TSE e 20 milhões de linhas carregadas).
As seguintes reaproveitam downloads, Parquet e tabelas já carregadas. Reserve uns 10 GB livres em disco.

Opções (as mesmas nos dois sistemas):

```bash
./iniciar.sh --pular-extracao   # iniciar.bat --pular-extracao : reaproveita data/silver
./iniciar.sh --sem-tsql         # iniciar.bat --sem-tsql       : para depois da carga em stg
./iniciar.sh --forcar           # iniciar.bat --forcar         : baixa e refaz tudo
```

Depois de pronto, conecte no banco em `localhost`, porta `1433`, banco `tse_warehouse`, usuário `sa` e a senha do `.env`
(veja [Conectando pelo DBeaver](#conectando-pelo-dbeaver)). Para parar o SQL Server: `docker compose stop`.

---

## Modo desenvolvedor (Python na sua máquina)

Para alterar e depurar os scripts Python fora do container, instale também o `uv` e o ODBC Driver 18.
Os scripts SQL e Python são lidos direto da pasta do projeto nos dois modos, então para mudanças só em `sql/` o
`iniciar` já basta.

| Ferramenta | Para quê | Observação |
|---|---|---|
| [Docker](https://docs.docker.com/get-started/get-docker/) com Compose v2 | SQL Server | comando `docker compose` (com espaço) |
| [uv](https://docs.astral.sh/uv/) | Python e dependências | o `uv` instala a versão certa do Python sozinho |
| **ODBC Driver 18 for SQL Server** | o `pyodbc` conversar com o banco | **não é instalado pelo `uv`**, é um programa do sistema |
| [DBeaver](https://dbeaver.io/download/) (opcional) | explorar o banco | |

### Instalação no Windows

1. **Docker Desktop** (com WSL 2 habilitado) e deixe-o **aberto** antes de rodar o pipeline.
2. **uv**, no PowerShell:
   ```powershell
   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
   ```
3. **ODBC Driver 18 for SQL Server**: baixe o instalador (`.msi`) na página
   [Download ODBC Driver for SQL Server](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server)
   da Microsoft e instale com as opções padrão.
4. Reabra o terminal para o `uv` entrar no PATH.

### Instalação no Linux

1. **Docker**: siga o guia oficial da sua distribuição e adicione seu usuário ao grupo `docker` para não precisar de `sudo`:
   ```bash
   sudo usermod -aG docker $USER   # depois faça logout/login
   sudo systemctl enable --now docker
   ```
2. **uv**:
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```
3. **ODBC Driver 18 + unixODBC**:
   - **Ubuntu/Debian**: adicione o repositório da Microsoft (passo a passo em
     [Install the Microsoft ODBC driver for SQL Server (Linux)](https://learn.microsoft.com/sql/connect/odbc/linux-mac/installing-the-microsoft-odbc-driver-for-sql-server))
     e depois:
     ```bash
     sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18 unixodbc-dev
     ```
   - **Arch Linux**: instale `unixodbc` pelo `pacman` e o driver da Microsoft pelo AUR
     (pacote `msodbcsql`, por exemplo com `yay -S msodbcsql unixodbc`).
   - **Outras distribuições**: veja o link da Microsoft acima.
4. **Confira** que o driver foi registrado (deve aparecer `ODBC Driver 18 for SQL Server`):
   ```bash
   odbcinst -q -d
   ```

### Rodando

Crie o `.env` (ou rode o `iniciar` uma vez, que cria sozinho):

| Linux / macOS | Windows (PowerShell) |
|---|---|
| `cp .env.example .env` | `Copy-Item .env.example .env` |

Abra o `.env` e troque `MSSQL_SA_PASSWORD`. Regra do SQL Server: mínimo de 8 caracteres, com pelo menos 3 entre
maiúscula, minúscula, número e símbolo. Evite o caractere `$`.

```bash
uv sync                                   # instala as dependências
uv run pipelines/run_all.py               # sobe o Docker, extrai, carrega e roda o T-SQL
```

Ou rode etapa por etapa:

```bash
docker compose up -d --wait sqlserver     # sobe o SQL Server e espera ficar pronto
uv run pipelines/01_extract_tse.py        # baixa e filtra as 4 capitais
uv run pipelines/02_load_staging.py       # carrega em stg.* (cria o banco e espera ele responder)
uv run pipelines/03_run_tsql.py           # executa sql/*.sql em ordem
```

As etapas podem ser repetidas à vontade: downloads e Parquet já existentes são reaproveitados e a carga pula tabelas já completas.

### Opções úteis

```bash
uv run pipelines/01_extract_tse.py --bases 5 6 7   # só algumas bases (números da tabela abaixo)
uv run pipelines/01_extract_tse.py --forcar        # baixa e refaz tudo
uv run pipelines/run_all.py --pular-extracao       # reaproveita data/silver
uv run pipelines/run_all.py --sem-tsql             # para depois da carga em stg
uv run pipelines/03_run_tsql.py --listar           # mostra a ordem dos scripts SQL
```

---

## Bases utilizadas (2022)

URLs começam com `https://cdn.tse.jus.br/estatistica/sead/odsele/`.

| Nº | Base | Arquivo(s) |
|---|---|---|
| 1 a 4 | Votação por seção (Governador, Senador, Dep. Federal e Estadual) | `votacao_secao/votacao_secao_2022_{ES,MG,RJ,SP}.zip` |
| 5 | Votação em partido por município/zona | `votacao_partido_munzona/votacao_partido_munzona_2022.zip` |
| 6 | Votação nominal por município/zona | `votacao_candidato_munzona/votacao_candidato_munzona_2022.zip` |
| 7 | Detalhe da apuração por município/zona | `detalhe_votacao_munzona/detalhe_votacao_munzona_2022.zip` |
| 8 | Detalhe da apuração por seção | `detalhe_votacao_secao/detalhe_votacao_secao_2022.zip` |
| 9 | Presidente por seção (arquivo nacional) | `votacao_secao/votacao_secao_2022_BR.zip` |
| 10 | Perfil do eleitorado por seção | `perfil_eleitor_secao/perfil_eleitor_secao_2022_{ES,MG,RJ,SP}.zip` |
| 11 | Perfil do comparecimento e abstenção | `perfil_comparecimento_abstencao/perfil_comparecimento_abstencao_2022.zip` |
| 12 | Eleitorado por local de votação | `eleitorado_locais_votacao/eleitorado_local_votacao_2022.zip` |

O cargo de **Presidente** só existe no arquivo `_BR` (base 9); os arquivos por UF não o contêm, então não há dupla contagem.

Códigos TSE dos municípios usados no filtro: São Paulo `71072`, Rio de Janeiro `60011`, Belo Horizonte `41238`, Vitória `57053`.

---

## Conectando pelo DBeaver

1. **Nova conexão → SQL Server**.
2. Host `localhost`, porta `1433`, banco `tse_warehouse` (ou o valor de `MSSQL_DATABASE`), usuário `sa` e a senha do `.env`.
3. Aba **Driver properties**: defina `trustServerCertificate` = `true` (o certificado do container é autoassinado).
4. Baixe o driver quando o DBeaver pedir e clique em **Test Connection**.

Os dados brutos ficam em `stg.stg_<dataset>`, por exemplo `stg.stg_votacao_secao` e `stg.stg_detalhe_votacao_secao`.
Todas as colunas são texto (`NVARCHAR`), com os valores sentinela do TSE (como `#NULO`) preservados para você tratar em T-SQL.

---

## Scripts T-SQL

Coloque os scripts em `sql/` com prefixo numérico, para a ordem ficar explícita:

```
sql/01_criar_schemas.sql
sql/02_limpeza_stg.sql
sql/03_dimensoes.sql
sql/04_fatos.sql
sql/05_views_bi.sql
```

`03_run_tsql.py` divide cada arquivo nas linhas `GO` e executa um lote por vez. Se um lote falhar, a execução para e mostra o erro.

---

## Visualização: Power BI no Linux

O **Power BI Desktop só roda no Windows**. Opções:

- **Quem monta o `.pbix` usa Windows** (máquina própria, outro integrante ou VM) e conecta no SQL Server do Docker
  (`localhost,1433`) ou em tabelas exportadas para CSV/Parquet.
- **Metabase** (open source, roda no navegador), para quem está no Linux e quer explorar e montar dashboards:
  ```bash
  docker compose --profile bi up -d
  ```
  Abra <http://localhost:3000>, escolha **SQL Server** e use host `sqlserver`, porta `1433`, usuário `sa`,
  a senha do `.env` e o banco `tse_warehouse`.
- O **Power BI Service (web)** edita relatórios no navegador, mas não enxerga um SQL Server local sem o
  *on-premises data gateway*, que só existe para Windows.

---

## Problemas comuns

| Sintoma | Causa provável e solução |
|---|---|
| `Can't open lib 'ODBC Driver 18 for SQL Server'` / `Data source name not found` | Só no modo desenvolvedor: o driver ODBC não está instalado ou registrado. Refaça o passo do ODBC e confira com `odbcinst -q -d` (Linux), ou use o `iniciar`, que não precisa do driver. |
| `Cannot connect to the Docker daemon` / `error during connect` | O Docker não está rodando. Windows: abra o Docker Desktop. Linux: `sudo systemctl start docker`. |
| `permission denied` ao usar `docker` no Linux | Seu usuário não está no grupo `docker`: `sudo usermod -aG docker $USER` e faça logout/login. |
| `MSSQL_SA_PASSWORD` não definida / compose reclama da variável | Falta o `.env`. Rode o `iniciar`, que cria um, ou copie o `.env.example`. |
| Windows: o `iniciar.bat` para em "Docker Desktop instalado" ou "WSL instalado" | É esperado: reinicie o computador se pedido, abra o Docker Desktop uma vez (aceite os termos) e dê duplo clique no `iniciar.bat` de novo. |
| Container reinicia sozinho e o log fala em senha | Senha fora da política do SQL Server. Use 8+ caracteres, com 3 tipos diferentes. Depois: `docker compose down -v` e suba de novo. |
| `Login timeout expired` / `connection refused` | O banco ainda está subindo (leva de 10 a 30 s): o `02_load_staging.py` já espera até 120 s. Se persistir: `docker compose logs sqlserver`. |
| `SSL Provider` / `certificate verify failed` | Falta `TrustServerCertificate=yes` (já está nos scripts) ou `trustServerCertificate=true` no DBeaver. |
| Porta 1433 em uso | Outro SQL Server na máquina. Troque `MSSQL_PORT` no `.env` (ex.: `14330`) e suba de novo. |
| Download falha no meio | Rode de novo: o arquivo só é aceito depois de baixado por inteiro (`.part`) e há 3 tentativas automáticas. |
| `MemoryError` / máquina travando | Reduza `LINHAS_POR_BLOCO` em `pipelines/tse_io.py` (ex.: 200_000). |
| Quero apagar o banco e recomeçar | `docker compose down -v` (apaga o volume do SQL Server) e rode o pipeline de novo. |

---

## Estrutura do repositório

```
.
├── iniciar.sh / iniciar.bat   início rápido: configura o ambiente e roda tudo
├── scripts/iniciar.ps1    lógica do iniciar.bat (PowerShell)
├── Dockerfile             imagem do pipeline (Python + uv + ODBC Driver 18)
├── docker-compose.yml     SQL Server 2022 e serviço do pipeline
├── .env.example           modelo de configuração (o iniciar cria o .env)
├── pyproject.toml / uv.lock
├── pipelines/
│   ├── config.py              caminhos, banco e catálogo de bases
│   ├── tse_io.py              download, filtro e Parquet
│   ├── 01_extract_tse.py      extração (bronze -> silver)
│   ├── 02_load_staging.py     carga no SQL Server (stg)
│   ├── 03_run_tsql.py         executa sql/*.sql
│   └── run_all.py             roda tudo
├── sql/                   scripts T-SQL numerados
├── docs/                  Termo de Abertura e conferências (conferencias.sql)
├── powerbi/               dashboard (Power BI Project, .pbip)
└── data/                  (fora do Git) bronze, silver
```

## Segurança

- Nenhuma senha no código ou no Git: tudo vem do `.env` (já no `.gitignore`). **Se a senha antiga (`SenhaForte123@`) já foi commitada, troque-a e considere-a pública.**
- O SQL Server só escuta em `127.0.0.1`.
- Os dados são públicos e o projeto trabalha com agregados por zona e seção. Não carregue CPF nem dados pessoais.
