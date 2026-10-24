"""Configuração central do projeto: caminhos, conexão com o banco e catálogo de bases do TSE.

Todos os scripts em pipelines/ importam daqui. Segredos vêm do arquivo .env
(copie .env.example para .env); nenhuma senha fica no código.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

# --- Caminhos ---------------------------------------------------------------
DATA_DIR = BASE_DIR / "data"
BRONZE_DIR = DATA_DIR / "bronze"  # ZIPs originais, intocados
SILVER_DIR = DATA_DIR / "silver"  # Parquet filtrado nas 4 capitais
MANIFESTO = BRONZE_DIR / "manifesto.jsonl"  # url, sha256, tamanho, data do download
SQL_DIR = BASE_DIR / "sql"
DOCS_DIR = BASE_DIR / "docs"

# --- Escopo -----------------------------------------------------------------
ANO = int(os.getenv("TSE_ANO", "2022"))
BASE_URL = "https://cdn.tse.jus.br/estatistica/sead/odsele/"

# Códigos TSE (não IBGE) dos municípios das 4 capitais (Termo, seção 4.3)
CAPITAIS = {
    71072: "São Paulo",
    60011: "Rio de Janeiro",
    41238: "Belo Horizonte",
    57053: "Vitória",
}
CAPITAL_POR_UF = {"SP": 71072, "RJ": 60011, "MG": 41238, "ES": 57053}
UFS = list(CAPITAL_POR_UF)

# --- Banco de dados ---------------------------------------------------------
DB_USER = os.getenv("MSSQL_USER", "sa")
DB_HOST = os.getenv(
    "MSSQL_HOST", "127.0.0.1"
)  # 127.0.0.1 evita problemas com IPv6 do "localhost"
DB_PORT = os.getenv("MSSQL_PORT", "1433")
DB_NAME = os.getenv("MSSQL_DATABASE", "tse_warehouse")
ODBC_DRIVER = os.getenv("ODBC_DRIVER", "ODBC Driver 18 for SQL Server")


def obter_senha() -> str:
    senha = os.getenv("MSSQL_SA_PASSWORD")
    if not senha:
        raise SystemExit(
            "[ERRO] MSSQL_SA_PASSWORD não definida. Copie .env.example para .env "
            "e preencha a senha (veja o README)."
        )
    return senha


def string_conexao(banco: str | None = None) -> str:
    """String ODBC para o SQL Server. TrustServerCertificate=yes é necessário porque o
    ODBC Driver 18 exige criptografia e o container usa certificado autoassinado."""
    senha = obter_senha().replace("}", "}}")
    return (
        f"DRIVER={{{ODBC_DRIVER}}};SERVER={DB_HOST},{DB_PORT};DATABASE={banco or DB_NAME};"
        f"UID={DB_USER};PWD={{{senha}}};TrustServerCertificate=yes;"
    )


# --- Catálogo de bases ------------------------------------------------------
# Colunas que o Termo (seção 4.5) espera encontrar. O script 00_validar_bases.py
# compara com o cabeçalho real do CSV e aponta o que faltar.
COLS_VOTACAO_SECAO = (
    "ANO_ELEICAO",
    "NR_TURNO",
    "SG_UF",
    "CD_MUNICIPIO",
    "NR_ZONA",
    "NR_SECAO",
    "CD_CARGO",
    "NR_VOTAVEL",
    "QT_VOTOS",
)
COLS_DETALHE_ZONA = (
    "ANO_ELEICAO",
    "NR_TURNO",
    "CD_MUNICIPIO",
    "NR_ZONA",
    "CD_CARGO",
    "QT_APTOS",
    "QT_COMPARECIMENTO",
    "QT_ABSTENCOES",
    "QT_VOTOS_BRANCOS",
    "QT_VOTOS_NULOS",
)
COLS_DETALHE_SECAO = COLS_DETALHE_ZONA + ("NR_SECAO",)
# --- Em pipelines/config.py ---

# ALTERAR DE:
# COLS_PARTIDO = ("CD_MUNICIPIO", "NR_ZONA", "SG_PARTIDO", "NR_PARTIDO",
#                 "QT_VOTOS_NOMINAIS", "QT_VOTOS_LEGENDA")

# PARA (Nomes reais do TSE em 2022):
COLS_PARTIDO = (
    "CD_MUNICIPIO",
    "NR_ZONA",
    "SG_PARTIDO",
    "NR_PARTIDO",
    "QT_VOTOS_NOMINAIS_VALIDOS",
    "QT_VOTOS_LEGENDA_VALIDOS",
)
COLS_CANDIDATO = (
    "CD_MUNICIPIO",
    "NR_ZONA",
    "SQ_CANDIDATO",
    "NR_CANDIDATO",
    "NM_URNA_CANDIDATO",
    "SG_PARTIDO",
    "QT_VOTOS_NOMINAIS",
)
COLS_PERFIL_SECAO = (
    "CD_MUNICIPIO",
    "NR_ZONA",
    "NR_SECAO",
    "DS_GENERO",
    "DS_FAIXA_ETARIA",
    "DS_GRAU_ESCOLARIDADE",
    "QT_ELEITORES_PERFIL",
)
COLS_COMPARECIMENTO = (
    "CD_MUNICIPIO",
    "NR_ZONA",
    "DS_GENERO",
    "DS_FAIXA_ETARIA",
    "DS_GRAU_ESCOLARIDADE",
)
COLS_LOCAL_VOTACAO = ("CD_MUNICIPIO", "NR_ZONA", "NR_SECAO", "NR_LOCAL_VOTACAO")


@dataclass(frozen=True)
class Base:
    num: int  # número da base na tabela da seção 4 do Termo
    nome: str
    pasta_cdn: str  # subpasta em BASE_URL
    arquivo: str  # nome do ZIP
    silver: str  # pasta de destino em data/silver/
    uf: str | None = None
    esperadas: tuple[str, ...] = ()

    @property
    def url(self) -> str:
        return f"{BASE_URL}{self.pasta_cdn}/{self.arquivo}"

    @property
    def zip_path(self) -> Path:
        return BRONZE_DIR / self.arquivo

    def parquet_path(self, ano: int) -> Path:
        partes = [SILVER_DIR, *self.silver.split("/")]
        if self.uf:
            partes.append(f"uf={self.uf}")
        partes.append(f"ano={ano}")
        return Path(*partes) / "data.parquet"

    @property
    def rotulo(self) -> str:
        return f"{self.num:>2} {self.nome}" + (f" [{self.uf}]" if self.uf else "")

    @property
    def capitais_esperadas(self) -> set[int]:
        return {CAPITAL_POR_UF[self.uf]} if self.uf else set(CAPITAIS)


def catalogo(ano: int = ANO) -> list[Base]:
    bases: list[Base] = []
    # 1 a 4: votação por seção, um arquivo por UF (Gov, Sen, Dep. Fed., Dep. Est.; SEM Presidente)
    for num, uf in zip((1, 2, 3, 4), ("ES", "MG", "RJ", "SP")):
        bases.append(
            Base(
                num,
                "Votação por seção",
                "votacao_secao",
                f"votacao_secao_{ano}_{uf}.zip",
                "votacao_secao",
                uf,
                COLS_VOTACAO_SECAO,
            )
        )
    bases += [
        Base(
            5,
            "Votação em partido por município/zona",
            "votacao_partido_munzona",
            f"votacao_partido_munzona_{ano}.zip",
            "votacao_partido_munzona",
            None,
            COLS_PARTIDO,
        ),
        Base(
            6,
            "Votação nominal por município/zona",
            "votacao_candidato_munzona",
            f"votacao_candidato_munzona_{ano}.zip",
            "votacao_candidato_munzona",
            None,
            COLS_CANDIDATO,
        ),
        Base(
            7,
            "Detalhe da apuração por município/zona",
            "detalhe_votacao_munzona",
            f"detalhe_votacao_munzona_{ano}.zip",
            "detalhe_votacao_munzona",
            None,
            COLS_DETALHE_ZONA,
        ),
        Base(
            8,
            "Detalhe da apuração por seção",
            "detalhe_votacao_secao",
            f"detalhe_votacao_secao_{ano}.zip",
            "detalhe_votacao_secao",
            None,
            COLS_DETALHE_SECAO,
        ),
        # 9: Presidente fica em arquivo próprio (BR), com todas as UFs
        Base(
            9,
            "Presidente: votação por seção (BR)",
            "votacao_secao",
            f"votacao_secao_{ano}_BR.zip",
            "votacao_secao_br",
            None,
            COLS_VOTACAO_SECAO,
        ),
    ]
    # 10: perfil do eleitorado por seção, um arquivo por UF
    for uf in ("ES", "MG", "RJ", "SP"):
        bases.append(
            Base(
                10,
                "Perfil do eleitorado por seção",
                "perfil_eleitor_secao",
                f"perfil_eleitor_secao_{ano}_{uf}.zip",
                "perfil_eleitor_secao",
                uf,
                COLS_PERFIL_SECAO,
            )
        )
    bases += [
        Base(
            11,
            "Perfil do comparecimento e abstenção",
            "perfil_comparecimento_abstencao",
            f"perfil_comparecimento_abstencao_{ano}.zip",
            "perfil_comparecimento_abstencao",
            None,
            COLS_COMPARECIMENTO,
        ),
        Base(
            12,
            "Eleitorado por local de votação",
            "eleitorado_locais_votacao",
            f"eleitorado_local_votacao_{ano}.zip",
            "eleitorado_local_votacao",
            None,
            COLS_LOCAL_VOTACAO,
        ),
    ]
    return bases
