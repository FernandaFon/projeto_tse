"""Gera o projeto Power BI (PBIP: modelo em TMDL + relatório em PBIR) sobre o modelo dw.

Uso (na raiz do projeto):
    uv run powerbi/gerar_pbip.py                 # Servidor = localhost
    uv run powerbi/gerar_pbip.py 172.18.0.1      # outro servidor (ex.: Power BI no WinBoat)

ATENÇÃO: sobrescreve powerbi/DashboardTSE.SemanticModel e powerbi/DashboardTSE.Report.
Ajustes feitos à mão no Power BI Desktop e salvos no .pbip se perdem: ou passe-os para
este script, ou pare de usá-lo e edite o relatório só pelo Desktop.
"""

import json
import shutil
import sys
import uuid
from pathlib import Path

RAIZ = Path(__file__).resolve().parent
SERVIDOR = sys.argv[1] if len(sys.argv) > 1 else "localhost"
NOME = "DashboardTSE"
SM = RAIZ / f"{NOME}.SemanticModel"
RP = RAIZ / f"{NOME}.Report"
NS = uuid.UUID("6f1c1e0a-1d2b-4c3d-9e8f-0a1b2c3d4e5f")


def tag(*partes):  # lineageTag estável entre execuções
    return str(uuid.uuid5(NS, "/".join(partes)))


def q(nome):  # aspas em nomes TMDL que não sejam identificadores simples
    simples = nome.replace("_", "")
    return nome if simples.isascii() and simples.isalnum() else "'" + nome.replace("'", "''") + "'"


def escrever(caminho: Path, texto: str):
    caminho.parent.mkdir(parents=True, exist_ok=True)
    caminho.write_text(texto, encoding="utf-8")


def escrever_json(caminho: Path, obj):
    escrever(caminho, json.dumps(obj, ensure_ascii=False, indent=2) + "\n")


# =========================================================== modelo semântico
I, S, D, B, DT = "int64", "string", "double", "boolean", "dateTime"
FDS, FDZ = "FATO_DETALHE_SECAO", "FATO_DETALHE_ZONA"
FVSP, FVPZ, FVCZ = "FATO_VOTACAO_SECAO_PARTIDO", "FATO_VOTACAO_PARTIDO_ZONA", "FATO_VOTACAO_CANDIDATO_ZONA"
FPES, FPCZ = "FATO_PERFIL_ELEITORADO_SECAO", "FATO_PERFIL_COMPARECIMENTO_ZONA"
LIMITE = "Limite de disputa"


def col(nome, origem, tipo, oculta=False, fmt=None, ordenar=None):
    return dict(nome=nome, origem=origem, tipo=tipo, oculta=oculta, fmt=fmt, ordenar=ordenar)


def sk(*nomes):
    return [col(n, n, I, True) for n in nomes]


PCT = "0.0%;-0.0%;0.0%"
INT = "#,0"

# tabela -> (objeto no SQL Server, colunas importadas)
TABELAS = {
    "DIM_ELEICAO": ("DIM_ELEICAO", [
        *sk("sk_eleicao"), col("Ano", "ano", I), col("nr_turno", "turno", I, True),
        col("Data da eleição", "dt_eleicao", DT, fmt="dd/mm/yyyy")]),
    "DIM_CARGO": ("DIM_CARGO", [
        *sk("sk_cargo", "cd_cargo"), col("Cargo", "ds_cargo", S, ordenar="cd_cargo"),
        col("Majoritário", "fl_majoritario", B), col("Proporcional", "fl_proporcional", B)]),
    "DIM_MUNICIPIO": ("DIM_MUNICIPIO", [
        *sk("sk_municipio"), col("Capital", "nm_municipio", S), col("UF", "sg_uf", S),
        col("Código TSE", "cd_municipio_tse", I), col("Código IBGE", "cd_municipio_ibge", I)]),
    "DIM_ZONA": ("VW_ZONA_BI", [
        *sk("sk_zona", "sk_municipio"), col("Zona", "nr_zona", I),
        col("Zona (capital)", "ds_zona", S), col("Periferia", "ds_periferia", S),
        col("Distância ao centro (km)", "distancia_centro_km", D, fmt="#,0.0")]),
    "DIM_SECAO": ("VW_SECAO_BI", [
        *sk("sk_secao"), col("Seção", "nr_secao", I),
        col("Seção (capital/zona)", "ds_secao", S),
        col("Local de votação", "nm_local_votacao", S), col("Bairro", "nm_bairro", S),
        col("Latitude", "latitude", D), col("Longitude", "longitude", D),
        col("% sem médio completo · K11a", "pct_sem_medio", D, fmt=PCT),
        col("% superior completo · K11b", "pct_superior", D, fmt=PCT),
        col("pr_sem_medio", "pr_sem_medio", D, True), col("pr_superior", "pr_superior", D, True),
        col("Aptos (referência)", "qt_aptos_referencia", I, fmt=INT),
        col("quartil_aptos", "quartil_aptos", I, True)]),
    "DIM_PERFIL": ("DIM_PERFIL", [
        *sk("sk_perfil"), col("Gênero", "ds_genero", S), col("Faixa etária", "ds_faixa_etaria", S),
        col("Escolaridade", "ds_grau_escolaridade", S), col("Feminino", "fl_feminino", B),
        col("Jovem 18–24", "fl_jovem_18_24", B), col("60–69", "fl_60_69", B),
        col("70 ou mais", "fl_70_mais", B), col("Voto facultativo", "fl_facultativo", B),
        col("Escolaridade informada", "fl_escolaridade_informada", B),
        col("Sem médio completo", "fl_sem_medio_completo", B),
        col("Superior completo", "fl_superior_completo", B)]),
    "DIM_AGREMIACAO": ("DIM_AGREMIACAO", [
        *sk("sk_agremiacao"), col("Partido", "sg_partido", S), col("Nome do partido", "nm_partido", S),
        col("Número do partido", "nr_partido", I), col("Federação", "sg_federacao", S),
        col("Partido do cliente", "fl_cliente", B)]),
    "DIM_CANDIDATO": ("DIM_CANDIDATO", [
        *sk("sk_candidato", "cd_cargo"), col("Candidato", "nm_urna_candidato", S),
        col("Número do candidato", "nr_candidato", I),
        col("Partido do candidato", "sg_partido", S),
        col("Situação da candidatura", "ds_situacao_candidatura", S)]),
    "DIM_TIPO_VOTO": ("DIM_TIPO_VOTO", [
        *sk("sk_tipo_voto"), col("Tipo de voto", "ds_tipo_voto", S), col("Voto válido", "fl_valido", B)]),
    FDS: (FDS, [
        *sk("sk_eleicao", "sk_cargo", "sk_municipio", "sk_zona", "sk_secao", "qt_aptos",
            "qt_comparecimento", "qt_abstencoes", "qt_votos_nominais", "qt_votos_legenda",
            "qt_votos_brancos", "qt_votos_nulos"),
        col("fl_secao_instalada", "fl_secao_instalada", B, True)]),
    FDZ: (FDZ, sk("sk_eleicao", "sk_cargo", "sk_municipio", "sk_zona", "qt_aptos",
                  "qt_comparecimento", "qt_abstencoes", "qt_votos_nominais", "qt_votos_legenda",
                  "qt_votos_brancos", "qt_votos_nulos")),
    FVSP: (FVSP, sk("sk_eleicao", "sk_cargo", "sk_municipio", "sk_zona", "sk_secao",
                    "sk_agremiacao", "sk_tipo_voto", "qt_votos")),
    FVPZ: (FVPZ, sk("sk_eleicao", "sk_cargo", "sk_municipio", "sk_zona", "sk_agremiacao",
                    "qt_votos_nominais", "qt_votos_legenda")),
    FVCZ: (FVCZ, [
        *sk("sk_eleicao", "sk_cargo", "sk_municipio", "sk_zona", "sk_candidato", "sk_agremiacao",
            "qt_votos_nominais", "qt_votos_nominais_validos"),
        col("Situação no turno", "ds_sit_tot_turno", S)]),
    FPES: (FPES, sk("sk_eleicao", "sk_municipio", "sk_zona", "sk_secao", "sk_perfil",
                    "qt_eleitores_perfil")),
    FPCZ: (FPCZ, sk("sk_eleicao", "sk_municipio", "sk_zona", "sk_perfil", "qt_aptos",
                    "qt_comparecimento", "qt_abstencao")),
}

# colunas calculadas: tabela -> [(nome, dax, tipo, oculta)]
CALCULADAS = {
    "DIM_ELEICAO": [("Turno", 'FORMAT(DIM_ELEICAO[nr_turno], "0") & "º turno"', S, False)],
    "DIM_SECAO": [
        # P75 das seções das 4 capitais (Termo, definições operacionais); troque 0.75 para ajustar
        ("Baixa escolaridade", 'IF(DIM_SECAO[pr_sem_medio] >= 0.75, "Sim", "Não")', S, False),
        ("Alta escolaridade", 'IF(DIM_SECAO[pr_superior] >= 0.75, "Sim", "Não")', S, False),
        ("Quartil de tamanho",
         'SWITCH(DIM_SECAO[quartil_aptos], 1, "Q1 (menores)", 2, "Q2", 3, "Q3", 4, "Q4 (maiores)", "Sem dado")',
         S, False)],
    # Regra 6.1: taxas excluem seções com zero aptos e seções não instaladas
    FDS: [("considerar",
           f"IF({FDS}[qt_aptos] > 0 && COALESCE({FDS}[fl_secao_instalada], TRUE()), 1, 0)", I, True)],
}

RELACOES = {
    FDS: ["DIM_ELEICAO", "DIM_CARGO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_SECAO"],
    FDZ: ["DIM_ELEICAO", "DIM_CARGO", "DIM_MUNICIPIO", "DIM_ZONA"],
    FVSP: ["DIM_ELEICAO", "DIM_CARGO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_SECAO", "DIM_AGREMIACAO",
           "DIM_TIPO_VOTO"],
    FVPZ: ["DIM_ELEICAO", "DIM_CARGO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_AGREMIACAO"],
    FVCZ: ["DIM_ELEICAO", "DIM_CARGO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_CANDIDATO",
           "DIM_AGREMIACAO"],
    FPES: ["DIM_ELEICAO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_SECAO", "DIM_PERFIL"],
    FPCZ: ["DIM_ELEICAO", "DIM_MUNICIPIO", "DIM_ZONA", "DIM_PERFIL"],
}
CHAVE = {d: "sk_" + d.removeprefix("DIM_").lower() for r in RELACOES.values() for d in r}


def ref_cargo_turno(expr):
    # Aptos e comparecimento se repetem em cada cargo e turno: sem um único cargo/turno
    # no filtro, usa Presidente e 1º turno como referência (Termo: turno e cargo de referência).
    return [
        "VAR _cargo = IF(HASONEVALUE(DIM_CARGO[cd_cargo]), VALUES(DIM_CARGO[cd_cargo]), 1)",
        "VAR _turno = IF(HASONEVALUE(DIM_ELEICAO[nr_turno]), VALUES(DIM_ELEICAO[nr_turno]), 1)",
        "RETURN",
        f"    CALCULATE({expr}, DIM_CARGO[cd_cargo] = _cargo, DIM_ELEICAO[nr_turno] = _turno)",
    ]


def ref_turno(expr):
    return [
        "VAR _turno = IF(HASONEVALUE(DIM_ELEICAO[nr_turno]), VALUES(DIM_ELEICAO[nr_turno]), 1)",
        f"RETURN CALCULATE({expr}, DIM_ELEICAO[nr_turno] = _turno)",
    ]


def secao(expr):
    return ref_cargo_turno(f"{expr}, {FDS}[considerar] = 1")


def top20(medida):
    # Na linha, a própria zona (se estiver entre as 20); no total, a soma das 20 zonas
    return [
        "SUMX(FILTER(VALUES(DIM_ZONA[Zona (capital)]),",
        "            VAR _p = [Posição Q5] RETURN NOT ISBLANK(_p) && _p <= 20),",
        f"     [{medida}])",
    ]


R = "0.00"
# tabela -> [(nome, dax (str ou lista de linhas), formato, descrição)]
MEDIDAS = {
    FDZ: [
        ("Aptos (zona)", ref_cargo_turno(f"SUM({FDZ}[qt_aptos])"), INT, "Base 7. Eleitores aptos."),
        ("Comparecimento (zona)", ref_cargo_turno(f"SUM({FDZ}[qt_comparecimento])"), INT, None),
        ("Abstenções (zona) · K6", ref_cargo_turno(f"SUM({FDZ}[qt_abstencoes])"), INT,
         "K6: abstenções em número absoluto."),
        ("Taxa de abstenção (zona) · K1", "DIVIDE([Abstenções (zona) · K6], [Aptos (zona)])", PCT,
         "K1 total: abstenções ÷ aptos."),
        ("Votos válidos (zona)",
         ref_cargo_turno(f"SUM({FDZ}[qt_votos_nominais]) + SUM({FDZ}[qt_votos_legenda])"), INT,
         "Nominais + legenda."),
        ("Brancos e nulos (zona) · K2",
         ref_cargo_turno(f"SUM({FDZ}[qt_votos_brancos]) + SUM({FDZ}[qt_votos_nulos])"), INT, None),
        ("Taxa de brancos e nulos (zona) · K2b",
         "DIVIDE([Brancos e nulos (zona) · K2], [Comparecimento (zona)])", PCT, None),
        ("Engajamento global · K8", "DIVIDE([Votos válidos (zona)], [Aptos (zona)])", PCT,
         "K8: votos válidos ÷ aptos."),
        ("Válidos por abstenção · K9", "DIVIDE([Votos válidos (zona)], [Abstenções (zona) · K6])", R,
         "K9: votos válidos ÷ abstenções."),
        ("Posição Q5", [
            "VAR _taxa = [Taxa de abstenção (zona) · K1]",
            "RETURN",
            "    IF(_taxa > 0.20,",
            "        RANKX(FILTER(ALLSELECTED(DIM_ZONA[Zona (capital)]), [Taxa de abstenção (zona) · K1] > 0.20),",
            "              [Aptos (zona)], , DESC))"], "0", "Ranking por aptos entre zonas com abstenção acima de 20%."),
        ("Aptos · Top 20 (Q5)", top20("Aptos (zona)"), INT, None),
        ("Abstenções · Top 20 (Q5)", top20("Abstenções (zona) · K6"), INT, None),
        ("Taxa de abstenção · Top 20 (Q5)",
         "DIVIDE([Abstenções · Top 20 (Q5)], [Aptos · Top 20 (Q5)])", PCT, None),
    ],
    FDS: [
        ("Aptos (seção)", secao(f"SUM({FDS}[qt_aptos])"), INT,
         "Base 8, sem seções não instaladas ou com zero aptos (regra 6.1)."),
        ("Comparecimento (seção)", secao(f"SUM({FDS}[qt_comparecimento])"), INT, None),
        ("Abstenções (seção)", secao(f"SUM({FDS}[qt_abstencoes])"), INT, None),
        ("Seções consideradas", secao(f"COUNTROWS({FDS})"), INT, None),
        ("Taxa de abstenção (seção) · K1", "DIVIDE([Abstenções (seção)], [Aptos (seção)])", PCT, None),
        ("Aptos médios por seção", "DIVIDE([Aptos (seção)], [Seções consideradas])", INT, None),
        ("Brancos e nulos (seção) · K2",
         secao(f"SUM({FDS}[qt_votos_brancos]) + SUM({FDS}[qt_votos_nulos])"), INT, None),
        ("Taxa de brancos e nulos (seção) · K2b",
         "DIVIDE([Brancos e nulos (seção) · K2], [Comparecimento (seção)])", PCT,
         "K2b: (brancos + nulos) ÷ comparecimento."),
        ("% sem médio da seção · K11a",
         "IF(HASONEVALUE(DIM_SECAO[sk_secao]), MAX(DIM_SECAO[% sem médio completo · K11a]))", PCT,
         "Atributo da seção: vazio em totais."),
        ("K11a · baixa escolaridade (Q2)",
         'CALCULATE([% sem médio da seção · K11a], DIM_SECAO[Baixa escolaridade] = "Sim")', PCT, None),
        ("K2 · baixa escolaridade (Q2)",
         'CALCULATE([Brancos e nulos (seção) · K2], DIM_SECAO[Baixa escolaridade] = "Sim")', INT, None),
        ("K2b · baixa escolaridade (Q2)",
         'CALCULATE([Taxa de brancos e nulos (seção) · K2b], DIM_SECAO[Baixa escolaridade] = "Sim")',
         PCT, None),
        ("K2b · alta escolaridade (Q6)",
         'CALCULATE([Taxa de brancos e nulos (seção) · K2b], DIM_SECAO[Alta escolaridade] = "Sim")',
         PCT, None),
    ],
    FVSP: [
        ("Votos (seção × partido)", f"SUM({FVSP}[qt_votos])", INT, "Bases 1 a 4 e 9."),
        ("Votos de legenda (seção)",
         'CALCULATE([Votos (seção × partido)], DIM_TIPO_VOTO[Tipo de voto] = "LEGENDA")', INT, None),
        ("Votos válidos (seção)",
         "CALCULATE([Votos (seção × partido)], DIM_TIPO_VOTO[Voto válido] = TRUE())", INT, None),
        ("Índice de legenda (seção) · K5", "DIVIDE([Votos de legenda (seção)], [Votos válidos (seção)])",
         PCT, "K5 por seção: legenda ÷ (nominais + legenda)."),
    ],
    FVPZ: [
        ("Votos nominais do partido (zona)", f"SUM({FVPZ}[qt_votos_nominais])", INT, "Base 5."),
        ("Votos de legenda do partido (zona)", f"SUM({FVPZ}[qt_votos_legenda])", INT, None),
        ("Votos válidos do partido (zona)",
         "[Votos nominais do partido (zona)] + [Votos de legenda do partido (zona)]", INT, None),
        ("Índice de legenda (zona) · K5",
         "DIVIDE([Votos de legenda do partido (zona)], [Votos válidos do partido (zona)])", PCT, None),
        ("Participação do partido nos válidos", [
            "-- Sem partido escolhido no seletor seria sempre 100%: fica vazio",
            "IF(ISFILTERED(DIM_AGREMIACAO[Partido]),",
            "    DIVIDE([Votos válidos do partido (zona)],",
            "           CALCULATE([Votos válidos do partido (zona)], ALL(DIM_AGREMIACAO))))"],
         PCT, "Votos válidos do(s) partido(s) selecionado(s) ÷ votos válidos de todos os partidos."),
    ],
    FVCZ: [
        ("Votos nominais válidos (candidato)", f"SUM({FVCZ}[qt_votos_nominais_validos])", INT, "Base 6."),
        ("% dos válidos (candidato)",
         "DIVIDE([Votos nominais válidos (candidato)], CALCULATE([Votos nominais válidos (candidato)], ALL(DIM_CANDIDATO)))",
         PCT, None),
        ("Margem de competitividade (p.p.) · K4", [
            f"VAR _t = ADDCOLUMNS(SUMMARIZE({FVCZ}, DIM_CANDIDATO[sk_candidato]),",
            f'                    "@v", CALCULATE(SUM({FVCZ}[qt_votos_nominais_validos])))',
            "VAR _total = SUMX(_t, [@v])",
            "VAR _top2 = TOPN(2, _t, [@v], DESC)",
            "RETURN",
            "    IF(COUNTROWS(_top2) >= 2, 100 * DIVIDE(MAXX(_top2, [@v]) - MINX(_top2, [@v]), _total))"],
         '#,0.0" p.p."', "K4: |% 1º colocado − % 2º colocado| sobre os votos válidos."),
        ("Limite de disputa (p.p.)", f"SELECTEDVALUE('{LIMITE}'[Limite (p.p.)], 5)", "0", None),
        ("Zona de disputa?", [
            "VAR _m = [Margem de competitividade (p.p.) · K4]",
            "RETURN",
            "    IF(ISINSCOPE(DIM_ZONA[Zona (capital)]) && NOT ISBLANK(_m),",
            '       IF(_m < [Limite de disputa (p.p.)], "Sim", "Não"))'], None,
         "Só por zona: no total fica vazio."),
        ("Zonas de disputa", [
            "COUNTROWS(",
            "    FILTER(VALUES(DIM_ZONA[sk_zona]),",
            "        VAR _m = [Margem de competitividade (p.p.) · K4]",
            "        RETURN NOT ISBLANK(_m) && _m < [Limite de disputa (p.p.)]))"], INT, None),
    ],
    FPCZ: [
        ("Aptos (perfil)", ref_turno(f"SUM({FPCZ}[qt_aptos])"), INT, "Base 11."),
        ("Comparecimento (perfil)", ref_turno(f"SUM({FPCZ}[qt_comparecimento])"), INT, None),
        ("Abstenção (perfil)", ref_turno(f"SUM({FPCZ}[qt_abstencao])"), INT, None),
        ("Taxa de abstenção segmentada · K1", "DIVIDE([Abstenção (perfil)], [Aptos (perfil)])", PCT,
         "K1: abstenções do perfil ÷ aptos do perfil."),
        ("Aptos jovens 18–24", "CALCULATE([Aptos (perfil)], DIM_PERFIL[Jovem 18–24] = TRUE())", INT, None),
        ("Abstenção jovens 18–24 (Q1)",
         "CALCULATE([Taxa de abstenção segmentada · K1], DIM_PERFIL[Jovem 18–24] = TRUE())", PCT, None),
        ("Comparecimento 60–69 · K7",
         "CALCULATE(DIVIDE([Comparecimento (perfil)], [Aptos (perfil)]), DIM_PERFIL[60–69] = TRUE())",
         PCT, "K7: comparecimento ÷ aptos, 60 a 69 anos (voto obrigatório)."),
        ("Comparecimento 70+ · K7",
         "CALCULATE(DIVIDE([Comparecimento (perfil)], [Aptos (perfil)]), DIM_PERFIL[70 ou mais] = TRUE())",
         PCT, "K7: comparecimento ÷ aptos, 70 anos ou mais (voto facultativo)."),
        ("Eleitorado feminino ativo · K3",
         "DIVIDE(CALCULATE([Comparecimento (perfil)], DIM_PERFIL[Feminino] = TRUE()), [Comparecimento (perfil)])",
         PCT, "K3: mulheres que compareceram ÷ total que compareceu."),
        ("Zona prioritária (Q3)", [
            "VAR _cap = SELECTEDVALUE(DIM_ZONA[sk_municipio])",
            "VAR _zonas = CALCULATETABLE(VALUES(DIM_ZONA[sk_zona]), ALLSELECTED(DIM_ZONA), DIM_ZONA[sk_municipio] = _cap)",
            "VAR _p75 = PERCENTILEX.INC(_zonas, [Eleitorado feminino ativo · K3], 0.75)",
            "VAR _p25 = PERCENTILEX.INC(_zonas, [Participação do partido nos válidos], 0.25)",
            "VAR _k3 = [Eleitorado feminino ativo · K3]",
            "VAR _part = [Participação do partido nos válidos]",
            "RETURN",
            "    IF(NOT ISBLANK(_cap) && NOT ISBLANK(_k3) && NOT ISBLANK(_part),",
            '        IF(_k3 >= _p75 && _part <= _p25, "Sim", "Não"))'], None,
         "K3 ≥ P75 das zonas da capital e participação do partido ≤ P25 (Termo, pergunta 3)."),
    ],
    FPES: [("Eleitores do perfil (seção)", f"SUM({FPES}[qt_eleitores_perfil])", INT, "Base 10.")],
}
DONO = {m[0]: t for t, ms in MEDIDAS.items() for m in ms}


def tmdl_tabela(nome, objeto, colunas):
    l = [f"table {q(nome)}", f"\tlineageTag: {tag(nome)}", ""]
    for med, dax, fmt, desc in MEDIDAS.get(nome, []):
        if desc:
            l.append(f"\t/// {desc}")
        if isinstance(dax, str):
            l.append(f"\tmeasure {q(med)} = {dax}")
        else:  # expressão em várias linhas: dois níveis de recuo a mais que a medida
            l.append(f"\tmeasure {q(med)} =")
            l += ["\t\t\t" + linha for linha in dax]
        if fmt:
            l.append(f"\t\tformatString: {fmt}")
        l += [f"\t\tlineageTag: {tag(nome, 'm', med)}", ""]
    for c, dax, tipo, oculta in CALCULADAS.get(nome, []):
        l += [f"\tcolumn {q(c)} = {dax}", f"\t\tdataType: {tipo}"]
        if oculta:
            l.append("\t\tisHidden")
        l += [f"\t\tlineageTag: {tag(nome, c)}", "\t\tsummarizeBy: none", "",
              "\t\tannotation SummarizationSetBy = Automatic", ""]
    for c in colunas:
        l += [f"\tcolumn {q(c['nome'])}", f"\t\tdataType: {c['tipo']}"]
        if c["fmt"]:
            l.append(f"\t\tformatString: {c['fmt']}")
        elif c["tipo"] == I:
            l.append("\t\tformatString: 0")
        if c["oculta"]:
            l.append("\t\tisHidden")
        # o M renomeia as colunas, então sourceColumn é o nome final
        l += [f"\t\tlineageTag: {tag(nome, c['nome'])}", "\t\tsummarizeBy: none",
              f"\t\tsourceColumn: {c['nome']}"]
        if c["ordenar"]:
            l.append(f"\t\tsortByColumn: {q(c['ordenar'])}")
        l += ["", "\t\tannotation SummarizationSetBy = Automatic", ""]
    origem = ", ".join(f'"{c["origem"]}"' for c in colunas)
    renomes = ", ".join(f'{{"{c["origem"]}", "{c["nome"]}"}}' for c in colunas if c["origem"] != c["nome"])
    passos = [
        "\t\t\t\tlet",
        "\t\t\t\t    Fonte = Sql.Database(Servidor, Banco),",
        f'\t\t\t\t    Tabela = Fonte{{[Schema="dw", Item="{objeto}"]}}[Data],',
        f"\t\t\t\t    Colunas = Table.SelectColumns(Tabela, {{{origem}}})" + ("," if renomes else ""),
    ]
    if renomes:
        passos.append(f"\t\t\t\t    Renomeadas = Table.RenameColumns(Colunas, {{{renomes}}})")
    passos += ["\t\t\t\tin", "\t\t\t\t    " + ("Renomeadas" if renomes else "Colunas")]
    l += [f"\tpartition {q(nome)} = m", "\t\tmode: import", "\t\tsource =", *passos, "",
          "\tannotation PBI_NavigationStepName = Navigation", "", "\tannotation PBI_ResultType = Table", ""]
    return "\n".join(l)


def gerar_modelo():
    escrever_json(SM / "definition.pbism", {
        "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/semanticModel/definitionProperties/1.0.0/schema.json",
        "version": "4.0", "settings": {}})
    escrever(SM / "definition/database.tmdl", "database\n\tcompatibilityLevel: 1550\n\n")
    ordem = ["Servidor", "Banco", *TABELAS, LIMITE]
    escrever(SM / "definition/model.tmdl", "\n".join([
        "model Model",
        "\tculture: pt-BR",
        "\tdefaultPowerBIDataSourceVersion: powerBI_V3",
        "\tsourceQueryCulture: pt-BR",
        "\tdataAccessOptions",
        "\t\tlegacyRedirects",
        "\t\treturnErrorValuesAsNull",
        "",
        f"annotation PBI_QueryOrder = {json.dumps(ordem, ensure_ascii=False)}",
        "",
        "annotation __PBI_TimeIntelligenceEnabled = 0",
        "",
        *[f"ref table {q(t)}" for t in [*TABELAS, LIMITE]],
        "",
    ]))
    escrever(SM / "definition/expressions.tmdl", "\n".join([
        f'expression Servidor = "{SERVIDOR}" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
        f"\tlineageTag: {tag('Servidor')}", "", "\tannotation PBI_ResultType = Text", "",
        'expression Banco = "tse_warehouse" meta [IsParameterQuery=true, Type="Text", IsParameterQueryRequired=true]',
        f"\tlineageTag: {tag('Banco')}", "", "\tannotation PBI_ResultType = Text", "",
    ]))
    rels = []
    for fato, dims in RELACOES.items():
        for dim in dims:
            k = CHAVE[dim]
            rels += [f"relationship {tag('rel', fato, dim)}", f"\tfromColumn: {fato}.{k}",
                     f"\ttoColumn: {dim}.{k}", ""]
    escrever(SM / "definition/relationships.tmdl", "\n".join(rels))
    for nome, (objeto, colunas) in TABELAS.items():
        escrever(SM / f"definition/tables/{nome}.tmdl", tmdl_tabela(nome, objeto, colunas))
    escrever(SM / f"definition/tables/{LIMITE}.tmdl", "\n".join([
        f"table {q(LIMITE)}", f"\tlineageTag: {tag(LIMITE)}", "",
        "\tcolumn 'Limite (p.p.)'", "\t\tdataType: int64", "\t\tformatString: 0",
        f"\t\tlineageTag: {tag(LIMITE, 'col')}", "\t\tsummarizeBy: none",
        "\t\tsourceColumn: Limite (p.p.)", "", "\t\tannotation SummarizationSetBy = Automatic", "",
        f"\tpartition {q(LIMITE)} = m", "\t\tmode: import", "\t\tsource =",
        "\t\t\t\tlet",
        '\t\t\t\t    // Corte da "zona de disputa" (Termo: 3, 5 ou 10 p.p.)',
        '\t\t\t\t    Fonte = #table(type table [#"Limite (p.p.)" = Int64.Type], {{3}, {5}, {10}})',
        "\t\t\t\tin", "\t\t\t\t    Fonte", "",
        "\tannotation PBI_ResultType = Table", ""]))


# =========================================================== relatório (PBIR)
URL = "https://developer.microsoft.com/json-schemas/fabric"
VC = f"{URL}/item/report/definition/visualContainer/2.1.0/schema.json"


def lit(v):
    return {"expr": {"Literal": {"Value": v}}}


def txt(s):
    return lit("'" + s.replace("'", "''") + "'")


def campo(ent, prop):
    tipo = "Measure" if DONO.get(prop) == ent else "Column"
    return {tipo: {"Expression": {"SourceRef": {"Entity": ent}}, "Property": prop}}


def c(ent, prop, rotulo=None):
    p = {"field": campo(ent, prop), "queryRef": f"{ent}.{prop}", "nativeQueryRef": prop}
    if rotulo:  # nome curto no cabeçalho da tabela ou na legenda
        p["displayName"] = rotulo
    return p


def m(nome, rotulo=None):
    return c(DONO[nome], nome, rotulo)


def larguras_tabela(projecoes, largura):
    # Larguras fixas que cabem no visual: 1ª coluna (texto) mais larga, demais iguais
    util = largura - 30
    n = len(projecoes)
    primeira = util if n == 1 else max(120, min(220, util * 0.36))
    resto = (util - primeira) / max(n - 1, 1)
    return [{"properties": {"value": lit(f"{(primeira if i == 0 else resto):.1f}D")},
             "selector": {"metadata": p["queryRef"]}} for i, p in enumerate(projecoes)]


def visual(nome, tipo, pos, papeis=None, titulo=None, objects=None, ordenar=None, extra=None):
    x, y, w, h, z = pos
    v = {"visualType": tipo}
    if papeis:
        v["query"] = {"queryState": {r: {"projections": p} for r, p in papeis.items()}}
        if ordenar:
            alvo, direcao = ordenar
            v["query"]["sortDefinition"] = {
                "sort": [{"field": campo(DONO[alvo], alvo), "direction": direcao}],
                "isDefaultSort": True}
    if tipo == "tableEx":
        objects = dict(objects or {})
        objects["columnHeaders"] = [{"properties": {"autoSizeColumnWidth": lit("false"),
                                                    "wordWrap": lit("true")}}]
        objects["columnWidth"] = larguras_tabela(papeis["Values"], w)
    if objects:
        v["objects"] = objects
    v["visualContainerObjects"] = (
        {"title": [{"properties": {"show": lit("true"), "text": txt(titulo)}}]} if titulo
        else {"title": [{"properties": {"show": lit("false")}}]})
    v["drillFilterOtherVisuals"] = True
    if extra:
        v.update(extra)
    return {"$schema": VC, "name": nome,
            "position": {"x": x, "y": y, "z": z, "height": h, "width": w, "tabOrder": z},
            "visual": v}


def literal(valor):
    return f"{valor}L" if isinstance(valor, int) else "'" + valor.replace("'", "''") + "'"


def filtro_in(ent, prop, valores):
    return {"filter": {
        "Version": 2,
        "From": [{"Name": "f", "Entity": ent, "Type": 0}],
        "Where": [{"Condition": {"In": {
            "Expressions": [{"Column": {"Expression": {"SourceRef": {"Source": "f"}}, "Property": prop}}],
            "Values": [[{"Literal": {"Value": literal(v)}}] for v in valores]}}}]}}


def slicer(pagina, ent, prop, titulo, pos, padrao=None, unico=False):
    obj = {"data": [{"properties": {"mode": txt("Dropdown")}}]}
    if padrao:
        obj["general"] = [{"properties": {"filter": filtro_in(ent, prop, padrao)}}]
    if unico:
        obj["selection"] = [{"properties": {"singleSelect": lit("true")}}]
    nome = f"{pagina}_sl_{''.join(ch for ch in prop if ch.isalnum())}"
    return visual(nome, "slicer", pos, {"Values": [c(ent, prop)]}, titulo, obj)


def cabecalho(pagina, titulo, subtitulo):
    runs = [{"value": titulo, "textStyle": {"fontWeight": "bold", "fontSize": "18pt"}}]
    obj = {"general": [{"properties": {"paragraphs": [
        {"textRuns": runs},
        {"textRuns": [{"value": subtitulo, "textStyle": {"fontSize": "10pt"}}]}]}}]}
    return visual(f"{pagina}_titulo", "textbox", (10, 5, 600, 75, 0), objects=obj)


def slicers(pagina, specs):
    # até 4 seletores alinhados à direita do título
    return [slicer(pagina, ent, prop, titulo, (620 + i * 165, 10, 155, 65, 1 + i), padrao, unico)
            for i, (ent, prop, titulo, padrao, unico) in enumerate(specs)]


def card(pagina, i, medida, x, y, w=200):
    return visual(f"{pagina}_card{i}", "card", (x, y, w, 90, 10 + i), {"Values": [m(medida)]}, medida)


ROT = {"labels": [{"properties": {"show": lit("true")}}]}


def TURNO(padrao="1º turno"):
    return ("DIM_ELEICAO", "Turno", "Turno", [padrao], True)


def CARGO(padrao=None):
    return ("DIM_CARGO", "Cargo", "Cargo", [padrao] if padrao else None, True)


def CAPITAL(padrao=None):
    return ("DIM_MUNICIPIO", "Capital", "Capital", padrao, False)


def PARTIDO(unico):
    return ("DIM_AGREMIACAO", "Partido", "Partido", None, unico)


ZONA = c("DIM_ZONA", "Zona (capital)", "Zona")
SEC = c("DIM_SECAO", "Seção (capital/zona)", "Seção")
CAP = c("DIM_MUNICIPIO", "Capital")


def paginas_do_relatorio():
    paginas = {}

    p = "executiva"
    paginas[p] = ("Visão executiva", [
        cabecalho(p, "Visão executiva", "Pergunta 10 · K8 engajamento e K9 válidos/abstenção · bases 7 e 8"),
        *slicers(p, [TURNO(), CARGO("Presidente"), CAPITAL()]),
        *[card(p, i, k, 10 + i * 212, 85) for i, k in enumerate([
            "Aptos (zona)", "Comparecimento (zona)", "Taxa de abstenção (zona) · K1",
            "Votos válidos (zona)", "Engajamento global · K8", "Válidos por abstenção · K9"])],
        visual(f"{p}_barra", "clusteredBarChart", (10, 185, 520, 525, 20),
               {"Category": [CAP], "Y": [m("Engajamento global · K8")]},
               "Q10 · Engajamento global por capital (válidos ÷ aptos)", ROT,
               ("Engajamento global · K8", "Descending")),
        visual(f"{p}_tabela", "tableEx", (540, 185, 730, 525, 21),
               {"Values": [CAP, m("Aptos (zona)", "Aptos"), m("Comparecimento (zona)", "Comparec."),
                           m("Abstenções (zona) · K6", "Abstenções K6"),
                           m("Taxa de abstenção (zona) · K1", "Abstenção K1"),
                           m("Votos válidos (zona)", "Válidos"),
                           m("Taxa de brancos e nulos (zona) · K2b", "Brancos e nulos K2b"),
                           m("Engajamento global · K8", "Engajam. K8"),
                           m("Válidos por abstenção · K9", "Válidos/abst. K9")]},
               "Resumo por capital", ordenar=("Engajamento global · K8", "Descending")),
    ])

    p = "abstencao"
    paginas[p] = ("Abstenção e perfil", [
        cabecalho(p, "Abstenção e perfil", "Perguntas 1, 4 e 5 · K1, K6, K7 · bases 7 e 11"),
        *slicers(p, [TURNO(), CAPITAL()]),
        visual(f"{p}_q1", "tableEx", (10, 85, 410, 625, 10),
               {"Values": [ZONA, m("Aptos jovens 18–24", "Aptos 18–24"),
                           m("Abstenção jovens 18–24 (Q1)", "Abstenção 18–24")]},
               "Q1 · Abstenção de jovens (18–24) por zona",
               ordenar=("Abstenção jovens 18–24 (Q1)", "Descending")),
        visual(f"{p}_q4", "tableEx", (430, 85, 410, 625, 11),
               {"Values": [ZONA, m("Comparecimento 60–69 · K7", "Comparec. 60–69"),
                           m("Comparecimento 70+ · K7", "Comparec. 70+")]},
               "Q4 · Comparecimento de 60–69 e 70+ (menor primeiro)",
               ordenar=("Comparecimento 60–69 · K7", "Ascending")),
        visual(f"{p}_q5", "tableEx", (850, 85, 420, 625, 12),
               {"Values": [ZONA, m("Aptos · Top 20 (Q5)", "Aptos"),
                           m("Taxa de abstenção · Top 20 (Q5)", "Abstenção"),
                           m("Abstenções · Top 20 (Q5)", "Abstenções")]},
               "Q5 · 20 zonas com mais aptos e abstenção > 20%",
               ordenar=("Aptos · Top 20 (Q5)", "Descending")),
    ])

    p = "rejeicao"
    paginas[p] = ("Rejeição", [
        cabecalho(p, "Rejeição (brancos e nulos)", "Perguntas 2 e 6 · K2, K2b, K11 · bases 8 e 10"),
        *slicers(p, [TURNO(), CARGO(), CAPITAL()]),
        visual(f"{p}_q2", "tableEx", (10, 85, 620, 625, 10),
               {"Values": [SEC, m("K11a · baixa escolaridade (Q2)", "% sem médio K11a"),
                           m("K2 · baixa escolaridade (Q2)", "Brancos e nulos K2"),
                           m("K2b · baixa escolaridade (Q2)", "Taxa K2b")]},
               "Q2 · Seções de baixa escolaridade (≥ P75) com mais brancos e nulos",
               ordenar=("K2b · baixa escolaridade (Q2)", "Descending")),
        visual(f"{p}_q6", "clusteredBarChart", (640, 85, 630, 300, 11),
               {"Category": [CAP], "Y": [m("K2b · alta escolaridade (Q6)", "Seções de alta escolaridade"),
                                         m("Taxa de brancos e nulos (seção) · K2b", "Todas as seções")]},
               "Q6 · Brancos e nulos (K2b): seções de alta escolaridade × todas", ROT,
               ("K2b · alta escolaridade (Q6)", "Descending")),
        visual(f"{p}_disp", "scatterChart", (640, 395, 630, 315, 12),
               {"Category": [SEC], "X": [m("% sem médio da seção · K11a")],
                "Y": [m("Taxa de brancos e nulos (seção) · K2b")]},
               "Escolaridade × brancos e nulos (cada ponto é uma seção)"),
    ])

    p = "genero"
    paginas[p] = ("Gênero e partido-alvo", [
        cabecalho(p, "Gênero e partido-alvo", "Pergunta 3 · K3 e K5 · bases 5 e 11 · escolha o partido no seletor"),
        *slicers(p, [TURNO(), CARGO("Deputado Federal"), PARTIDO(True), CAPITAL()]),
        visual(f"{p}_disp", "scatterChart", (10, 85, 620, 625, 10),
               {"Category": [ZONA], "X": [m("Eleitorado feminino ativo · K3")],
                "Y": [m("Participação do partido nos válidos")]},
               "Q3 · Mulheres no comparecimento × participação do partido (escolha um partido)"),
        visual(f"{p}_tabela", "tableEx", (640, 85, 630, 625, 11),
               {"Values": [ZONA, m("Eleitorado feminino ativo · K3", "Mulheres K3"),
                           m("Participação do partido nos válidos", "Partido nos válidos"),
                           m("Índice de legenda (zona) · K5", "Legenda K5"),
                           m("Zona prioritária (Q3)", "Prioritária?")]},
               "Zonas: K3 alto (≥ P75) e partido fraco (≤ P25) = prioritária",
               ordenar=("Eleitorado feminino ativo · K3", "Descending")),
    ])

    p = "disputa"
    paginas[p] = ("Disputa", [
        cabecalho(p, "Disputa (swing zones)", "Pergunta 7 · K4 · bases 6 e 9 · padrão: Presidente, 2º turno"),
        *slicers(p, [TURNO("2º turno"), CARGO("Presidente"),
                     (LIMITE, "Limite (p.p.)", "Limite (p.p.)", [5], True), CAPITAL()]),
        card(p, 0, "Zonas de disputa", 10, 85, 250),
        card(p, 1, "Limite de disputa (p.p.)", 270, 85, 250),
        visual(f"{p}_barra", "clusteredBarChart", (10, 185, 620, 525, 20),
               {"Category": [ZONA], "Y": [m("Margem de competitividade (p.p.) · K4")]},
               "Q7 · Margem entre 1º e 2º colocados por zona (menor = mais disputada)", ROT,
               ("Margem de competitividade (p.p.) · K4", "Ascending")),
        visual(f"{p}_tabela", "tableEx", (640, 85, 630, 625, 21),
               {"Values": [ZONA, m("Margem de competitividade (p.p.) · K4", "Margem K4"),
                           m("Zona de disputa?", "Disputa?"),
                           m("Votos nominais válidos (candidato)", "Votos válidos")]},
               "Zonas de disputa: margem abaixo do limite",
               ordenar=("Margem de competitividade (p.p.) · K4", "Ascending")),
    ])

    p = "bases"
    paginas[p] = ("Bases consolidadas", [
        cabecalho(p, "Bases consolidadas (voto de legenda)", "Pergunta 8 · K5 · bases 1 a 5"),
        *slicers(p, [TURNO(), CARGO("Deputado Federal"), PARTIDO(False), CAPITAL()]),
        visual(f"{p}_secoes", "tableEx", (10, 85, 620, 625, 10),
               {"Values": [SEC, m("Votos de legenda (seção)", "Legenda"),
                           m("Votos válidos (seção)", "Válidos"),
                           m("Índice de legenda (seção) · K5", "Índice K5")]},
               "Q8 · Seções com maior proporção de votos de legenda",
               ordenar=("Índice de legenda (seção) · K5", "Descending")),
        visual(f"{p}_partidos", "clusteredBarChart", (640, 85, 630, 625, 11),
               {"Category": [c("DIM_AGREMIACAO", "Partido")], "Y": [m("Índice de legenda (zona) · K5")]},
               "Índice de legenda por partido (legenda ÷ válidos do partido)", ROT,
               ("Índice de legenda (zona) · K5", "Descending")),
    ])

    p = "logistica"
    paginas[p] = ("Logística de seções", [
        cabecalho(p, "Logística de seções", "Pergunta 9 · K1 e K10 · bases 8, 10 e 12"),
        *slicers(p, [TURNO(), CAPITAL(["SÃO PAULO", "RIO DE JANEIRO"]),
                     ("DIM_ZONA", "Periferia", "Zona", ["Periférica"], False)]),
        visual(f"{p}_quartil", "clusteredColumnChart", (10, 85, 620, 625, 10),
               {"Category": [c("DIM_SECAO", "Quartil de tamanho")], "Series": [CAP],
                "Y": [m("Taxa de abstenção (seção) · K1")]},
               "Q9 · Abstenção por quartil de tamanho da seção (K10)", ROT),
        visual(f"{p}_tabela", "tableEx", (640, 85, 630, 300, 11),
               {"Values": [CAP, c("DIM_SECAO", "Quartil de tamanho", "Quartil"),
                           m("Seções consideradas", "Seções"),
                           m("Aptos médios por seção", "Aptos médios"),
                           m("Taxa de abstenção (seção) · K1", "Abstenção K1")]},
               "Tamanho médio e abstenção por quartil"),
        visual(f"{p}_disp", "scatterChart", (640, 395, 630, 315, 12),
               {"Category": [SEC], "X": [m("Aptos (seção)")], "Y": [m("Taxa de abstenção (seção) · K1")]},
               "Aptos × abstenção (cada ponto é uma seção)"),
    ])
    return paginas


def gerar_relatorio():
    paginas = paginas_do_relatorio()
    dd = RP / "definition"
    escrever_json(RP / "definition.pbir", {
        "$schema": f"{URL}/item/report/definitionProperties/2.0.0/schema.json",
        "version": "4.0",
        "datasetReference": {"byPath": {"path": f"../{NOME}.SemanticModel"}}})
    escrever_json(dd / "version.json", {
        "$schema": f"{URL}/item/report/definition/versionMetadata/1.0.0/schema.json", "version": "2.0.0"})
    escrever_json(dd / "report.json", {
        "$schema": f"{URL}/item/report/definition/report/2.0.0/schema.json",
        "themeCollection": {"baseTheme": {"name": "CY24SU10", "reportVersionAtImport": "5.61",
                                          "type": "SharedResources"}},
        "resourcePackages": [{"name": "SharedResources", "type": "SharedResources", "items": [
            {"name": "CY24SU10", "path": "BaseThemes/CY24SU10.json", "type": "BaseTheme"}]}],
        "settings": {"useStylableVisualContainerHeader": True, "exportDataMode": "AllowSummarized",
                     "defaultDrillFilterOtherVisuals": True, "allowChangeFilterTypes": True,
                     "useEnhancedTooltips": True, "useDefaultAggregateDisplayName": True}})
    escrever_json(dd / "pages/pages.json", {
        "$schema": f"{URL}/item/report/definition/pagesMetadata/1.0.0/schema.json",
        "pageOrder": list(paginas), "activePageName": next(iter(paginas))})
    for nome, (titulo, visuais) in paginas.items():
        escrever_json(dd / f"pages/{nome}/page.json", {
            "$schema": f"{URL}/item/report/definition/page/2.0.0/schema.json",
            "name": nome, "displayName": titulo, "displayOption": "FitToPage", "height": 720, "width": 1280})
        for v in visuais:
            escrever_json(dd / f"pages/{nome}/visuals/{v['name']}/visual.json", v)
    escrever_json(RAIZ / f"{NOME}.pbip", {
        "$schema": f"{URL}/pbip/pbipProperties/1.0.0/schema.json",
        "version": "1.0",
        "artifacts": [{"report": {"path": f"{NOME}.Report"}}],
        "settings": {"enableAutoRecovery": True}})
    return paginas


if __name__ == "__main__":
    # recria as definições do zero (o tema base em StaticResources é mantido)
    shutil.rmtree(SM / "definition", ignore_errors=True)
    shutil.rmtree(RP / "definition", ignore_errors=True)
    gerar_modelo()
    paginas = gerar_relatorio()
    print(f"PBIP gerado em {RAIZ} | servidor: {SERVIDOR} | páginas: {len(paginas)}"
          f" | visuais: {sum(len(v) for _, v in paginas.values())}"
          f" | medidas: {sum(len(v) for v in MEDIDAS.values())}")
