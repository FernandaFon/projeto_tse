"""Roda o pipeline inteiro: Docker (SQL Server) -> extração -> carga -> T-SQL.

Uso:
    uv run pipelines/run_all.py
    uv run pipelines/run_all.py --pular-extracao      # reaproveita data/silver/
    uv run pipelines/run_all.py --sem-tsql            # para depois da carga em stg
    uv run pipelines/run_all.py --forcar              # refaz downloads e Parquet

Funciona igual em Linux e Windows.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from config import BASE_DIR, SQL_DIR

PIPELINES = Path(__file__).resolve().parent


def rodar(cmd: list[str], descricao: str) -> None:
    print(f"\n########## {descricao} ##########")
    resultado = subprocess.run(cmd, cwd=BASE_DIR)
    if resultado.returncode != 0:
        raise SystemExit(f"\n[ERRO] Etapa falhou: {descricao}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--pular-extracao", action="store_true")
    ap.add_argument("--sem-tsql", action="store_true")
    ap.add_argument("--forcar", action="store_true")
    args = ap.parse_args()

    if not (BASE_DIR / ".env").exists():
        raise SystemExit("[ERRO] Arquivo .env não encontrado. Copie .env.example para .env (veja o README).")
    if shutil.which("docker") is None:
        raise SystemExit("[ERRO] Docker não encontrado. Instale o Docker (veja o README) e tente de novo.")

    py = sys.executable
    rodar(["docker", "compose", "up", "-d", "sqlserver"], "1/4 Subindo o SQL Server (Docker)")

    if not args.pular_extracao:
        cmd = [py, str(PIPELINES / "01_extract_tse.py")] + (["--forcar"] if args.forcar else [])
        rodar(cmd, "2/4 Extração (TSE -> bronze -> silver)")

    rodar([py, str(PIPELINES / "02_load_staging.py")], "3/4 Carga (silver -> SQL Server stg)")

    if args.sem_tsql:
        print("\nParou antes do T-SQL (--sem-tsql).")
    elif not list(SQL_DIR.glob("*.sql")):
        print(f"\n[AVISO] Nenhum .sql em {SQL_DIR}; pulando a etapa de T-SQL.")
    else:
        rodar([py, str(PIPELINES / "03_run_tsql.py")], "4/4 Transformação T-SQL")

    print("\nPipeline concluído. Abra o DBeaver (ou outro cliente SQL) e confira o banco.")


if __name__ == "__main__":
    main()
