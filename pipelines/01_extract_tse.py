from pathlib import Path
import zipfile
import requests
import pandas as pd

# --- CONFIGURAÇÕES DO ESCOPO ---
# Códigos TSE dos municípios das capitais do Sudeste (Termo de Abertura - Seção 4.3)
CAPITAIS = {
    71072,  # São Paulo (SP)
    60011,  # Rio de Janeiro (RJ)
    41238,  # Belo Horizonte (MG)
    57053,  # Vitória (ES)
}

UFS = ["SP", "RJ", "MG", "ES"]
BASE_URL = "https://cdn.tse.jus.br/estatistica/sead/odsele/"

BASE_DIR = Path(__file__).resolve().parent.parent
BRONZE_DIR = BASE_DIR / "data" / "bronze"
SILVER_DIR = BASE_DIR / "data" / "silver"


def garantir_diretorios():
    BRONZE_DIR.mkdir(parents=True, exist_ok=True)
    SILVER_DIR.mkdir(parents=True, exist_ok=True)


def baixar_arquivo(url: str, caminho_destino: Path) -> bool:
    if caminho_destino.exists():
        print(f"[CACHE] Já existe: {caminho_destino.name}")
        return True

    print(f"[DOWNLOAD] Descarregando: {url}")
    try:
        response = requests.get(url, stream=True, timeout=120)
        response.raise_for_status()
        with open(caminho_destino, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        return True
    except requests.exceptions.RequestException as e:
        print(f"[ERRO] Falha ao descarregar {url}: {e}")
        return False


def processar_e_filtrar_dataset(
    url: str, nome_arquivo_zip: str, pasta_silver_destino: str, ano: int
):
    """Descarrega o ZIP, normaliza colunas, filtra por blocos (capitais ou estados) e guarda em Parquet."""
    caminho_bronze = BRONZE_DIR / nome_arquivo_zip

    if not baixar_arquivo(url, caminho_bronze):
        return

    chunks_filtrados = []
    print(f"[PROCESSAMENTO] Filtrando registos de {nome_arquivo_zip}...")

    try:
        with zipfile.ZipFile(caminho_bronze) as z:
            nome_csv = next(n for n in z.namelist() if n.lower().endswith(".csv"))

            with z.open(nome_csv) as f:
                for bloco in pd.read_csv(
                    f, sep=";", encoding="latin-1", dtype=str, chunksize=500_000
                ):
                    # Normaliza os nomes das colunas: remove espaços, BOM (\ufeff) e converte para maiúsculas
                    bloco.columns = [
                        c.strip().replace("\ufeff", "").upper() for c in bloco.columns
                    ]

                    # Cenário 1: Bases detalhadas por Município (filtra estritamente pelas 4 capitais)
                    if "CD_MUNICIPIO" in bloco.columns:
                        bloco["CD_MUNICIPIO_INT"] = pd.to_numeric(
                            bloco["CD_MUNICIPIO"], errors="coerce"
                        )
                        bloco_filtrado = bloco[bloco["CD_MUNICIPIO_INT"].isin(CAPITAIS)]
                        bloco_filtrado = bloco_filtrado.drop(
                            columns=["CD_MUNICIPIO_INT"], errors="ignore"
                        )

                    # Cenário 2: Bases agregadas por UF (ex: Perfil de Comparecimento e Abstenção)
                    elif "SG_UF" in bloco.columns:
                        bloco_filtrado = bloco[bloco["SG_UF"].isin(UFS)]

                    # Cenário 3: Demais bases que não possuem essas chaves diretas no bloco atual
                    else:
                        bloco_filtrado = bloco

                    if not bloco_filtrado.empty:
                        chunks_filtrados.append(bloco_filtrado)

    except Exception as e:
        print(f"[ERRO] Falha ao processar o conteúdo de {nome_arquivo_zip}: {e}")
        return

    if chunks_filtrados:
        df_final = pd.concat(chunks_filtrados, ignore_index=True)
        pasta_destino = SILVER_DIR / pasta_silver_destino / f"ano={ano}"
        pasta_destino.mkdir(parents=True, exist_ok=True)
        caminho_parquet = pasta_destino / "data.parquet"

        df_final.to_parquet(caminho_parquet, index=False, engine="pyarrow")
        print(
            f"[SALVO] {caminho_parquet} gerado com sucesso! ({len(df_final)} registos)."
        )
    else:
        print(f"[AVISO] Nenhum registo correspondente em {nome_arquivo_zip}.")


def executar_pipeline_completo(ano: int):
    print(f"\n==============================================")
    print(f" INICIANDO EXTRAÇÃO DE TODAS AS BASES - {ano} ")
    print(f"==============================================")

    # 1 a 4. Votação por Seção Eleitoral por UF (ES, MG, RJ, SP)
    for uf in UFS:
        zip_name = f"votacao_secao_{ano}_{uf}.zip"
        processar_e_filtrar_dataset(
            f"{BASE_URL}votacao_secao/{zip_name}",
            zip_name,
            f"votacao_secao/uf={uf}",
            ano=ano,
        )

    # 9. Votação de Presidente por Seção - Nacional (BR)
    zip_name_br = f"votacao_secao_{ano}_BR.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}votacao_secao/{zip_name_br}",
        zip_name_br,
        "votacao_secao_br",
        ano=ano,
    )

    # 6. Votação Nominal de Candidatos por Município/Zona (Todas as UFs)
    zip_cand = f"votacao_candidato_munzona_{ano}.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}votacao_candidato_munzona/{zip_cand}",
        zip_cand,
        "votacao_candidato_munzona",
        ano=ano,
    )

    # 5. Votação em Partido por Município/Zona (Todas as UFs)
    zip_partido = f"votacao_partido_munzona_{ano}.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}votacao_partido_munzona/{zip_partido}",
        zip_partido,
        "votacao_partido_munzona",
        ano=ano,
    )

    # 7. Detalhe da Apuração por Município/Zona (Todas as UFs)
    zip_det_mun = f"detalhe_votacao_munzona_{ano}.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}detalhe_votacao_munzona/{zip_det_mun}",
        zip_det_mun,
        "detalhe_votacao_munzona",
        ano=ano,
    )

    # 8. Detalhe da Apuração por Seção Eleitoral (Todas as UFs)
    zip_det_sec = f"detalhe_votacao_secao_{ano}.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}detalhe_votacao_secao/{zip_det_sec}",
        zip_det_sec,
        "detalhe_votacao_secao",
        ano=ano,
    )

    # 10. Perfil do Eleitorado por Seção Eleitoral por UF
    for uf in UFS:
        zip_perfil = f"perfil_eleitor_secao_{ano}_{uf}.zip"
        processar_e_filtrar_dataset(
            f"{BASE_URL}perfil_eleitor_secao/{zip_perfil}",
            zip_perfil,
            f"perfil_eleitor_secao/uf={uf}",
            ano=ano,
        )

    # 11. Perfil do Comparecimento e Abstenção (Nacional/Geral filtrado por UF)
    zip_comp = f"perfil_comparecimento_abstencao_{ano}.zip"
    processar_e_filtrar_dataset(
        f"{BASE_URL}perfil_comparecimento_abstencao/{zip_comp}",
        zip_comp,
        "perfil_comparecimento_abstencao",
        ano=ano,
    )


if __name__ == "__main__":
    garantir_diretorios()
    # Executa a extração completa para o ciclo de 2022
    executar_pipeline_completo(ano=2022)
