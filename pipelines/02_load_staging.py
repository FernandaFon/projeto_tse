from pathlib import Path
import pandas as pd
import pyodbc
from sqlalchemy import create_engine, text

# --- CONFIGURAÇÕES DE CONEXÃO AO SQL SERVER ---
DB_USER = "sa"
DB_PASSWORD = "SenhaForte123@"
DB_HOST = "127.0.0.1"
DB_PORT = "1433"
DB_NAME = "tse_warehouse"


# Função criadora de conexão customizada para resolver o handshake do ODBC Driver 18 no Docker/Arch Linux
def get_connection():
    conn_str = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={DB_HOST},{DB_PORT};"
        f"DATABASE={DB_NAME};"
        f"UID={DB_USER};"
        f"PWD={DB_PASSWORD};"
        f"TrustServerCertificate=yes;"
    )
    return pyodbc.connect(conn_str)


# Cria o engine do SQLAlchemy injetando o creator personalizado
engine = create_engine("mssql+pyodbc://", creator=get_connection)

# Diretórios base
BASE_DIR = Path(__file__).resolve().parent.parent
SILVER_DIR = BASE_DIR / "data" / "silver"


def criar_esquema_stg(engine):
    """Cria o esquema 'stg' no SQL Server se ele não existir."""
    print("[BANCO DE DADOS] Garantindo a existência do esquema [stg]...")
    with engine.begin() as conn:
        conn.execute(
            text(
                "IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'stg') EXEC('CREATE SCHEMA stg');"
            )
        )


def carregar_parquet_para_staging():
    if not SILVER_DIR.exists():
        print(
            f"[ERRO] Diretório Silver não encontrado: {SILVER_DIR}. Execute a extração primeiro."
        )
        return

    print(
        f"[CONEXÃO] Conectando ao SQL Server em {DB_HOST}:{DB_PORT} (container: sql-server)..."
    )
    try:
        criar_esquema_stg(engine)
    except Exception as e:
        print(f"[ERRO] Falha ao conectar ao SQL Server: {e}")
        return

    # Varre todas as pastas dentro de data/silver/
    datasets = [d for d in SILVER_DIR.iterdir() if d.is_dir()]

    if not datasets:
        print("[AVISO] Nenhum dataset encontrado na camada Silver para carregar.")
        return

    for dataset_path in datasets:
        dataset_name = dataset_path.name
        tabela_stg = f"stg_{dataset_name}"

        print(
            f"\n[CARGA] Processando dataset: {dataset_name} -> Tabela: stg.{tabela_stg}"
        )

        # Localiza todos os ficheiros data.parquet dentro da estrutura (suportando partições)
        arquivos_parquet = list(dataset_path.glob("**/*.parquet"))

        if not arquivos_parquet:
            print(f"  -> Nenhum ficheiro Parquet encontrado para {dataset_name}.")
            continue

        is_first_file = True
        total_linhas_dataset = 0

        # Processamento ficheiro a ficheiro para poupar memória RAM
        for arq in arquivos_parquet:
            try:
                df_part = pd.read_parquet(arq)

                # Extrai metadados de partições do caminho (ex: ano=2022, uf=SP) se existirem
                for parte in arq.parts:
                    if "=" in parte:
                        k, v = parte.split("=")
                        df_part[k.upper()] = v

                # Padroniza os nomes das colunas para maiúsculas e substitui pontos por underscores
                df_part.columns = [
                    c.strip().replace(".", "_").upper() for c in df_part.columns
                ]

                # O primeiro ficheiro substitui/cria a tabela; os seguintes fazem append
                modo_escrita = "replace" if is_first_file else "append"

                print(
                    f"  -> A inserir {len(df_part)} registos de {arq.name} (modo: {modo_escrita})..."
                )

                df_part.to_sql(
                    name=tabela_stg,
                    con=engine,
                    schema="stg",
                    if_exists=modo_escrita,
                    index=False,
                    chunksize=50_000,
                )

                total_linhas_dataset += len(df_part)
                is_first_file = False

                # Liberta explicitamente a memória RAM do DataFrame deste ficheiro
                del df_part

            except Exception as e:
                print(f"  -> Erro ao processar o ficheiro {arq.name}: {e}")

        print(
            f"  -> Sucesso! Tabela stg.{tabela_stg} totalmente carregada ({total_linhas_dataset} registos)."
        )


if __name__ == "__main__":
    carregar_parquet_para_staging()
