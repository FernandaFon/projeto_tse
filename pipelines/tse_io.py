"""Download dos ZIPs do TSE, filtro nas 4 capitais e gravação em Parquet."""

from __future__ import annotations

import hashlib
import json
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import requests

from config import BRONZE_DIR, CAPITAIS, MANIFESTO, UFS, Base

HEADERS = {"User-Agent": "projeto-tse-devlivery/1.0 (projeto academico)"}
LINHAS_POR_BLOCO = 500_000
TENTATIVAS = 3


def normalizar_colunas(colunas) -> list[str]:
    """Remove BOM (lido como 'ï»¿' em latin-1), aspas e espaços; converte para maiúsculas."""
    return [
        str(c).replace("ï»¿", "").replace("\ufeff", "").replace('"', "").strip().upper()
        for c in colunas
    ]


def _registrar_manifesto(base: Base, sha256: str, tamanho: int) -> None:
    BRONZE_DIR.mkdir(parents=True, exist_ok=True)
    registro = {
        "arquivo": base.arquivo,
        "url": base.url,
        "sha256": sha256,
        "bytes": tamanho,
        "baixado_em": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    with open(MANIFESTO, "a", encoding="utf-8") as f:
        f.write(json.dumps(registro, ensure_ascii=False) + "\n")


def baixar(base: Base, forcar: bool = False) -> Path | None:
    """Baixa o ZIP para data/bronze/. Escreve em .part e só renomeia ao terminar,
    para que um download interrompido nunca seja confundido com um arquivo completo."""
    destino = base.zip_path
    destino.parent.mkdir(parents=True, exist_ok=True)

    if destino.exists() and not forcar:
        if zipfile.is_zipfile(destino):
            print(f"[CACHE] {destino.name}")
            return destino
        print(f"[AVISO] {destino.name} está corrompido; baixando de novo.")
        destino.unlink()

    tmp = destino.with_name(destino.name + ".part")
    for tentativa in range(1, TENTATIVAS + 1):
        try:
            print(f"[DOWNLOAD] {base.url}")
            sha = hashlib.sha256()
            baixado = 0
            proximo_aviso = 0.1
            with requests.get(
                base.url, headers=HEADERS, stream=True, timeout=(15, 120)
            ) as r:
                r.raise_for_status()
                total = int(r.headers.get("content-length", 0))
                with open(tmp, "wb") as f:
                    for pedaco in r.iter_content(chunk_size=1 << 20):
                        f.write(pedaco)
                        sha.update(pedaco)
                        baixado += len(pedaco)
                        if total and baixado / total >= proximo_aviso:
                            print(
                                f"           {baixado / total:.0%} de {total / 1e6:.0f} MB"
                            )
                            proximo_aviso += 0.1
            if total and baixado != total:
                raise OSError(f"download incompleto ({baixado} de {total} bytes)")
            tmp.replace(destino)
            _registrar_manifesto(base, sha.hexdigest(), baixado)
            return destino
        except (requests.RequestException, OSError) as e:
            print(f"[ERRO] tentativa {tentativa}/{TENTATIVAS} falhou: {e}")
            tmp.unlink(missing_ok=True)
            if tentativa < TENTATIVAS:
                time.sleep(5 * tentativa)
    return None


def _nomes_csv(z: zipfile.ZipFile) -> list[str]:
    nomes = sorted(n for n in z.namelist() if n.lower().endswith(".csv"))
    if not nomes:
        raise ValueError("nenhum .csv dentro do ZIP")
    return nomes


def _abrir_csv(z: zipfile.ZipFile, nome: str, **kwargs):
    # Todo o conteúdo é lido como texto: a limpeza de tipos e dos valores sentinela
    # do TSE ("#NULO", "#NE") é feita depois, em T-SQL.
    f = z.open(nome)
    leitor = pd.read_csv(
        f,
        sep=";",
        encoding="latin-1",
        dtype=str,
        keep_default_na=False,
        na_values=[""],
        **kwargs,
    )
    return f, leitor


def espiar(zip_path: Path, linhas: int = 3, indice: int = 0) -> pd.DataFrame:
    """Lê só as primeiras linhas de um dos CSVs do ZIP (padrão: o primeiro)."""
    z = zipfile.ZipFile(zip_path)
    try:
        nomes = _nomes_csv(z)
        print(f"CSVs no ZIP: {nomes}")
        f, df = _abrir_csv(z, nomes[indice], nrows=linhas)
        f.close()
        df.columns = normalizar_colunas(df.columns)
        return df
    finally:
        z.close()


def _filtrar_bloco(bloco: pd.DataFrame, municipios: set[int]) -> pd.DataFrame:
    col_muni = next(
        (
            c
            for c in ["CD_MUNICIPIO", "CD_MUN_ZONA", "CD_MUNICIP", "CD_UE"]
            if c in bloco.columns
        ),
        None,
    )
    if col_muni:
        s_muni = (
            bloco[col_muni]
            .astype(str)
            .str.replace('"', "", regex=False)
            .str.replace("'", "", regex=False)
            .str.strip()
        )
        muni_num = pd.to_numeric(s_muni, errors="coerce")
        mask = muni_num.isin(set(CAPITAIS.keys()))
        municipios.update(muni_num[mask].dropna().astype(int).unique())
        return bloco[mask]

    if "SG_UF" in bloco.columns:
        print("   [AVISO] sem coluna de município: filtrando por UF")
        s_uf = (
            bloco["SG_UF"]
            .astype(str)
            .str.replace('"', "", regex=False)
            .str.replace("'", "", regex=False)
            .str.strip()
        )
        return bloco[s_uf.isin(UFS)]

    raise ValueError(f"Sem coluna de filtro válida. Colunas: {list(bloco.columns)[:8]}")


def filtrar_para_parquet(base: Base, ano: int, forcar: bool = False) -> dict | None:
    """Filtra TODOS os CSVs do ZIP em blocos (4 capitais) e grava um Parquet único."""
    destino = base.parquet_path(ano)
    if destino.exists() and not forcar:
        print(f"[CACHE] {destino} já existe")
        return {
            "base": base.rotulo,
            "linhas": None,
            "municipios": None,
            "status": "cache",
        }

    destino.parent.mkdir(parents=True, exist_ok=True)
    tmp = destino.with_suffix(".parquet.tmp")
    writer = None
    schema = None
    lidas = gravadas = 0
    municipios: set[int] = set()

    print(f"[FILTRO] {base.arquivo}")
    z = zipfile.ZipFile(base.zip_path)
    try:
        nomes = _nomes_csv(z)
        print(f"   {len(nomes)} CSV(s) no ZIP")
        for nome in nomes:
            print(f"   lendo {nome}")
            f, leitor = _abrir_csv(z, nome, chunksize=LINHAS_POR_BLOCO)
            try:
                for bloco in leitor:
                    bloco.columns = normalizar_colunas(bloco.columns)
                    lidas += len(bloco)
                    bloco = _filtrar_bloco(bloco, municipios)
                    if bloco.empty:
                        continue

                    if writer is None:
                        schema = pa.schema([(c, pa.string()) for c in bloco.columns])
                        writer = pq.ParquetWriter(tmp, schema, compression="snappy")
                    else:
                        # garante o mesmo conjunto/ordem de colunas entre CSVs diferentes
                        bloco = bloco.reindex(columns=schema.names)

                    writer.write_table(
                        pa.Table.from_pandas(bloco, schema=schema, preserve_index=False)
                    )
                    gravadas += len(bloco)
            finally:
                f.close()
    except Exception as e:
        if writer is not None:
            writer.close()
        tmp.unlink(missing_ok=True)
        print(f"[ERRO] {base.arquivo}: {e}")
        return {
            "base": base.rotulo,
            "linhas": 0,
            "municipios": municipios,
            "status": f"erro: {e}",
        }
    finally:
        z.close()

    if writer is None:
        print(f"[AVISO] nenhum registro das 4 capitais em {base.arquivo}")
        return {
            "base": base.rotulo,
            "linhas": 0,
            "municipios": municipios,
            "status": "vazio",
        }

    writer.close()
    tmp.replace(destino)

    faltando = base.capitais_esperadas - municipios
    status = (
        "ok"
        if not faltando
        else "capital ausente: " + ", ".join(CAPITAIS[c] for c in faltando)
    )
    print(f"[SALVO] {gravadas:,} de {lidas:,} linhas -> {destino.name} ({status})")
    return {
        "base": base.rotulo,
        "linhas": gravadas,
        "municipios": municipios,
        "status": status,
    }
