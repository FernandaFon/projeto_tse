"""Carga: lê os Parquets filtrados em data/silver/ e carrega no SQL Server (schema stg).

Cada Parquet é lido em lotes (nunca inteiro na memória) e as colunas são criadas
como NVARCHAR com a largura realmente necessária, o que mantém o fast_executemany leve.

Uso:
    uv run pipelines/02_load_staging.py                # pula tabelas já carregadas por completo
    uv run pipelines/02_load_staging.py --forcar       # recria todas as tabelas stg
    uv run pipelines/02_load_staging.py --lote 5000    # lote menor, se faltar memória
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import pyarrow.compute as pc
import pyarrow.parquet as pq
import pyodbc

from config import ANO, BASE_DIR, DB_NAME, ODBC_DRIVER, catalogo, string_conexao

LOTE_PADRAO = 20_000
LIMITE_NVARCHAR = 4000  # acima disso a coluna vira NVARCHAR(MAX)
ESPERA_BANCO = 120  # segundos aguardando o container do SQL Server aceitar conexões


def garantir_banco() -> None:
    """Espera o SQL Server responder e cria o banco DB_NAME, se ainda não existir."""
    if ODBC_DRIVER not in pyodbc.drivers():
        raise SystemExit(
            f"[ERRO] Driver '{ODBC_DRIVER}' não encontrado (instalados: {pyodbc.drivers()}). "
            "Instale o ODBC Driver 18 (veja o README)."
        )
    limite = time.time() + ESPERA_BANCO
    while True:
        try:
            conn = pyodbc.connect(string_conexao("master"), autocommit=True, timeout=10)
            break
        except pyodbc.Error as e:
            if time.time() > limite:
                raise SystemExit(f"[ERRO] SQL Server não respondeu em {ESPERA_BANCO}s: {e}")
            print("   aguardando o SQL Server ficar pronto...")
            time.sleep(5)
    with conn:
        conn.cursor().execute(
            f"IF DB_ID(N'{DB_NAME}') IS NULL CREATE DATABASE [{DB_NAME}];"
            # O DW é recriado do zero a cada carga: sem backup de log, o modelo FULL só faz
            # o log de transações crescer (dezenas de GB). SIMPLE recicla o log.
            f"ALTER DATABASE [{DB_NAME}] SET RECOVERY SIMPLE;"
        )
    conn.close()


def medir_larguras(pf: pq.ParquetFile, lote: int) -> dict[str, int]:
    """Maior comprimento de texto de cada coluna, em uma única passada pelo arquivo."""
    larguras = {c: 1 for c in pf.schema_arrow.names}
    for batch in pf.iter_batches(batch_size=lote):
        for nome, coluna in zip(batch.schema.names, batch.columns):
            maior = pc.max(pc.utf8_length(coluna)).as_py()
            if maior and maior > larguras[nome]:
                larguras[nome] = maior
    return larguras


def tipo_sql(largura: int) -> str:
    if largura > LIMITE_NVARCHAR:
        return "NVARCHAR(MAX)"
    # margem de segurança, arredondando para cima em múltiplos de 10
    return f"NVARCHAR({min(((largura + 9) // 10) * 10, LIMITE_NVARCHAR)})"


def contar_linhas(conn: pyodbc.Connection, tabela: str) -> int | None:
    """Linhas atuais em stg.<tabela>, ou None se a tabela não existe."""
    cur = conn.cursor()
    cur.execute("SELECT OBJECT_ID(?, 'U')", f"stg.{tabela}")
    if cur.fetchone()[0] is None:
        return None
    cur.execute(f"SELECT COUNT_BIG(*) FROM stg.{tabela}")
    return int(cur.fetchone()[0])


def recriar_tabela(
    conn: pyodbc.Connection, tabela: str, larguras: dict[str, int]
) -> None:
    cur = conn.cursor()
    cur.execute(
        "IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'stg') EXEC('CREATE SCHEMA stg');"
    )
    colunas = ", ".join(f"[{c}] {tipo_sql(w)} NULL" for c, w in larguras.items())
    cur.execute(
        f"IF OBJECT_ID('stg.{tabela}', 'U') IS NOT NULL DROP TABLE stg.{tabela}; "
        f"CREATE TABLE stg.{tabela} ({colunas});"
    )
    conn.commit()


def carregar_parquet_para_stg(
    parquet_file: Path,
    tabela: str,
    conn: pyodbc.Connection,
    lote: int,
    forcar: bool,
) -> int:
    pf = pq.ParquetFile(parquet_file)
    esperado = pf.metadata.num_rows
    rotulo = parquet_file.relative_to(BASE_DIR)
    print(f"[CARGA] {rotulo} -> stg.{tabela}")

    if esperado == 0:
        print("   [AVISO] Parquet vazio; nada a carregar")
        return 0

    if not forcar:
        existentes = contar_linhas(conn, tabela)
        if existentes == esperado:
            print(f"   [CACHE] já carregada ({existentes:,} linhas)")
            return existentes

    larguras = medir_larguras(pf, lote)
    recriar_tabela(conn, tabela, larguras)

    colunas = ", ".join(f"[{c}]" for c in larguras)
    marcas = ", ".join("?" * len(larguras))
    sql_insert = (
        f"INSERT INTO stg.{tabela} WITH (TABLOCK) ({colunas}) VALUES ({marcas})"
    )

    cur = conn.cursor()
    cur.fast_executemany = True
    total = 0
    inicio = time.time()
    for batch in pf.iter_batches(batch_size=lote):
        # None vira NULL no banco (valores vazios do CSV do TSE)
        linhas = [tuple(l.values()) for l in batch.to_pylist()]
        cur.executemany(sql_insert, linhas)
        conn.commit()
        total += len(linhas)
        print(f"   {total:,} / {esperado:,}", end="\r", flush=True)

    print(f"   [OK] {total:,} linhas em stg.{tabela} ({time.time() - inicio:.0f}s)   ")
    return total


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    ap.add_argument("--forcar", action="store_true", help="recria as tabelas stg")
    ap.add_argument("--lote", type=int, default=LOTE_PADRAO, help="linhas por lote")
    ap.add_argument("--ano", type=int, default=ANO)
    args = ap.parse_args()

    print("\n=== Carga Staging no SQL Server ===")
    garantir_banco()
    falhas: list[str] = []

    for base in catalogo(args.ano):
        parquet_file = base.parquet_path(args.ano)
        if not parquet_file.exists():
            print(f"[PULANDO] {base.rotulo} (Parquet não encontrado em {parquet_file})")
            falhas.append(f"{base.rotulo}: sem Parquet")
            continue

        tabela = f"stg_{base.silver}"
        if base.uf:
            tabela += f"_{base.uf.lower()}"

        # Uma conexão por tabela: se uma cair, as demais não são afetadas.
        try:
            with pyodbc.connect(string_conexao(), autocommit=False) as conn:
                conn.timeout = 0  # sem limite por comando
                carregar_parquet_para_stg(
                    parquet_file, tabela, conn, args.lote, args.forcar
                )
        except Exception as e:  # noqa: BLE001
            print(f"\n   [ERRO] {tabela}: {e}")
            falhas.append(f"{tabela}: {e}")

    if falhas:
        print(f"\n[ATENÇÃO] {len(falhas)} tabela(s) com problema:")
        for f in falhas:
            print(f"  - {f}")
        print("Rode de novo: as tabelas já completas são puladas.")
        return 1

    print("\nCarga para staging concluída com sucesso.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
