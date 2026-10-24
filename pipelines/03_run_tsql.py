"""Executa os scripts T-SQL da pasta sql/ em ordem alfabética (sql/01_*.sql, sql/02_*.sql, ...).

Cada arquivo é dividido nas linhas "GO" (que não é T-SQL, e sim um separador do SSMS/DBeaver)
e cada lote é executado separadamente.

Uso:
    uv run pipelines/03_run_tsql.py                    # todos os .sql de sql/
    uv run pipelines/03_run_tsql.py --arquivo sql/02_limpeza.sql
    uv run pipelines/03_run_tsql.py --listar           # só mostra a ordem de execução
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

import pyodbc

from config import BASE_DIR, SQL_DIR, string_conexao


def dividir_em_lotes(sql: str) -> list[str]:
    lotes = re.split(r"^\s*GO\s*(?:--.*)?$", sql, flags=re.IGNORECASE | re.MULTILINE)
    return [lote.strip() for lote in lotes if lote.strip()]


def executar(arquivo: Path, conn: pyodbc.Connection) -> None:
    lotes = dividir_em_lotes(arquivo.read_text(encoding="utf-8-sig"))
    print(f"\n[T-SQL] {arquivo.relative_to(BASE_DIR)} ({len(lotes)} lote(s))")
    inicio = time.time()
    for i, lote in enumerate(lotes, 1):
        try:
            cur = conn.cursor()
            cur.execute(lote)
            while cur.nextset():  # consome resultados intermediários
                pass
        except pyodbc.Error as e:
            raise SystemExit(f"[ERRO] lote {i} de {arquivo.name} falhou:\n{e}")
    print(f"   concluído em {time.time() - inicio:.1f}s")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--arquivo", type=Path, help="executa só este arquivo")
    ap.add_argument("--listar", action="store_true")
    args = ap.parse_args()

    arquivos = [args.arquivo] if args.arquivo else sorted(SQL_DIR.glob("*.sql"))
    if not arquivos:
        print(f"[AVISO] Nenhum .sql em {SQL_DIR}")
        return 1
    if args.listar:
        for a in arquivos:
            print(a.relative_to(BASE_DIR) if a.is_absolute() else a)
        return 0

    with pyodbc.connect(string_conexao(), autocommit=True) as conn:
        for a in arquivos:
            executar(a.resolve(), conn)
    print("\nTransformações T-SQL concluídas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
