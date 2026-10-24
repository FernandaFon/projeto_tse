"""Extração: baixa os ZIPs do TSE (bronze) e grava Parquet filtrado nas 4 capitais (silver).

Uso:
    uv run pipelines/01_extract_tse.py                  # todas as bases do ano configurado
    uv run pipelines/01_extract_tse.py --bases 5 6 7    # só algumas (números da tabela do Termo)
    uv run pipelines/01_extract_tse.py --forcar         # baixa e refaz o Parquet mesmo se já existir
"""

from __future__ import annotations

import argparse
import sys

from config import ANO, BRONZE_DIR, SILVER_DIR, catalogo
from tse_io import baixar, filtrar_para_parquet


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--ano", type=int, default=ANO)
    ap.add_argument("--bases", type=int, nargs="*", help="números das bases (padrão: todas)")
    ap.add_argument("--forcar", action="store_true", help="ignora o cache")
    args = ap.parse_args()

    BRONZE_DIR.mkdir(parents=True, exist_ok=True)
    SILVER_DIR.mkdir(parents=True, exist_ok=True)

    bases = [b for b in catalogo(args.ano) if not args.bases or b.num in args.bases]
    print(f"\n=== Extração TSE {args.ano}: {len(bases)} arquivo(s) ===")

    resumo = []
    for base in bases:
        print(f"\n--- Base {base.rotulo} ---")
        if baixar(base, forcar=args.forcar) is None:
            resumo.append({"base": base.rotulo, "linhas": 0, "status": "download falhou"})
            continue
        resumo.append(filtrar_para_parquet(base, args.ano, forcar=args.forcar))

    print("\n=== Resumo ===")
    problemas = 0
    for r in resumo:
        linhas = "-" if r["linhas"] is None else f"{r['linhas']:,}"
        print(f"{r['base']:<52} {linhas:>12}  {r['status']}")
        if r["status"] not in ("ok", "cache"):
            problemas += 1
    if problemas:
        print(f"\n[ATENÇÃO] {problemas} arquivo(s) com problema. Corrija antes de carregar no banco.")
        return 1
    print("\nExtração concluída. Próximo passo: uv run pipelines/02_load_staging.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
