/* ============================================================
   02_limpeza_stg.sql
   Converte as tabelas brutas stg.stg_* (tudo texto) em tabelas tipadas stg.*_limpa.
   - valores sentinela do TSE (#NULO, #NE, vazio) viram NULL
   - números e datas recebem tipo
   - bases com vários CSVs por ZIP (5, 6, 7, 8 e 11) passam por DISTINCT sobre
     TODAS as colunas brutas, para remover linhas repetidas caso os arquivos
     _BR/_BRASIL repitam dados dos arquivos por UF
   - só ficam os 5 cargos do projeto (1 Presidente, 3 Governador, 5 Senador,
     6 Dep. Federal, 7 Dep. Estadual)
   Pode ser executado várias vezes (as tabelas *_limpa são recriadas).
   ============================================================ */

DROP FUNCTION IF EXISTS stg.fn_nulo;
GO

CREATE FUNCTION stg.fn_nulo(@x NVARCHAR(4000))
RETURNS NVARCHAR(4000)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE WHEN LTRIM(RTRIM(@x)) IN (N'', N'#NULO', N'#NULO#', N'#NE', N'#NE#')
                THEN NULL ELSE LTRIM(RTRIM(@x)) END;
END;
GO

/* ---------- Votação por seção (bases 1 a 4 e 9) ---------- */
DROP TABLE IF EXISTS stg.votacao_secao_limpa;
GO

WITH u AS (
    SELECT ANO_ELEICAO, NR_TURNO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, SQ_CANDIDATO FROM stg.stg_votacao_secao_es
    UNION ALL
    SELECT ANO_ELEICAO, NR_TURNO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, SQ_CANDIDATO FROM stg.stg_votacao_secao_mg
    UNION ALL
    SELECT ANO_ELEICAO, NR_TURNO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, SQ_CANDIDATO FROM stg.stg_votacao_secao_rj
    UNION ALL
    SELECT ANO_ELEICAO, NR_TURNO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, SQ_CANDIDATO FROM stg.stg_votacao_secao_sp
    UNION ALL
    SELECT ANO_ELEICAO, NR_TURNO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, SQ_CANDIDATO FROM stg.stg_votacao_secao_br
),
t AS (
    SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT) AS ano,
           TRY_CAST(NR_TURNO AS TINYINT)     AS turno,
           TRY_CAST(CD_MUNICIPIO AS INT)     AS cd_municipio,
           TRY_CAST(NR_ZONA AS INT)          AS nr_zona,
           TRY_CAST(NR_SECAO AS INT)         AS nr_secao,
           TRY_CAST(CD_CARGO AS INT)         AS cd_cargo,
           TRY_CAST(NR_VOTAVEL AS INT)       AS nr_votavel,
           stg.fn_nulo(NM_VOTAVEL)           AS nm_votavel,
           TRY_CAST(QT_VOTOS AS INT)         AS qt_votos,
           TRY_CAST(SQ_CANDIDATO AS BIGINT)  AS sq_candidato
    FROM u
),
v AS (
    SELECT t.*,
           CASE
               WHEN nr_votavel = 95 OR UPPER(nm_votavel) = N'VOTO BRANCO' THEN 'BRANCO'
               WHEN nr_votavel = 96 OR UPPER(nm_votavel) = N'VOTO NULO'   THEN 'NULO'
               WHEN cd_cargo IN (6, 7) AND nr_votavel BETWEEN 10 AND 99    THEN 'LEGENDA'  -- número de 2 dígitos em cargo proporcional
               ELSE 'NOMINAL'
           END AS tipo_voto
    FROM t
)
SELECT ano, turno, cd_municipio, nr_zona, nr_secao, cd_cargo, nr_votavel, nm_votavel,
       qt_votos, sq_candidato, tipo_voto,
       -- partido = 2 primeiros dígitos do número votável (brancos e nulos não têm partido)
       CASE WHEN tipo_voto IN ('BRANCO', 'NULO') THEN NULL
            ELSE TRY_CAST(LEFT(CAST(nr_votavel AS VARCHAR(10)), 2) AS INT) END AS nr_partido
INTO stg.votacao_secao_limpa
FROM v
WHERE cd_cargo IN (1, 3, 5, 6, 7);
GO

/* ---------- Detalhe da apuração por seção (base 8) ---------- */
DROP TABLE IF EXISTS stg.detalhe_secao_limpa;
GO

SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)         AS ano,
       TRY_CAST(NR_TURNO AS TINYINT)             AS turno,
       TRY_CAST(CD_MUNICIPIO AS INT)             AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)                  AS nr_zona,
       TRY_CAST(NR_SECAO AS INT)                 AS nr_secao,
       TRY_CAST(CD_CARGO AS INT)                 AS cd_cargo,
       TRY_CAST(QT_APTOS AS INT)                 AS qt_aptos,
       TRY_CAST(QT_COMPARECIMENTO AS INT)        AS qt_comparecimento,
       TRY_CAST(QT_ABSTENCOES AS INT)            AS qt_abstencoes,
       TRY_CAST(QT_VOTOS_NOMINAIS AS INT)        AS qt_votos_nominais,
       TRY_CAST(QT_VOTOS_LEGENDA AS INT)         AS qt_votos_legenda,
       TRY_CAST(QT_VOTOS_BRANCOS AS INT)         AS qt_votos_brancos,
       TRY_CAST(QT_VOTOS_NULOS AS INT)           AS qt_votos_nulos,
       TRY_CAST(NR_LOCAL_VOTACAO AS INT)         AS nr_local_votacao,
       stg.fn_nulo(NM_LOCAL_VOTACAO)             AS nm_local_votacao,
       stg.fn_nulo(DS_LOCAL_VOTACAO_ENDERECO)    AS ds_endereco,
       stg.fn_nulo(DS_ORIGEM_VOTO)               AS ds_origem_voto,
       CASE WHEN UPPER(stg.fn_nulo(ST_SECAO_INSTALADA)) IN (N'S', N'SIM') THEN CAST(1 AS BIT)
            WHEN UPPER(stg.fn_nulo(ST_SECAO_INSTALADA)) IN (N'N', N'NÃO', N'NAO') THEN CAST(0 AS BIT) END AS fl_secao_instalada,
       CASE WHEN UPPER(stg.fn_nulo(ST_SECAO_ANULADA)) IN (N'S', N'SIM') THEN CAST(1 AS BIT)
            WHEN UPPER(stg.fn_nulo(ST_SECAO_ANULADA)) IN (N'N', N'NÃO', N'NAO') THEN CAST(0 AS BIT) END AS fl_secao_anulada
INTO stg.detalhe_secao_limpa
FROM (SELECT DISTINCT * FROM stg.stg_detalhe_votacao_secao) s
WHERE TRY_CAST(CD_CARGO AS INT) IN (1, 3, 5, 6, 7);
GO

/* ---------- Detalhe da apuração por zona (base 7) ---------- */
DROP TABLE IF EXISTS stg.detalhe_zona_limpa;
GO

SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)         AS ano,
       TRY_CAST(NR_TURNO AS TINYINT)             AS turno,
       TRY_CONVERT(DATE, stg.fn_nulo(DT_ELEICAO), 103) AS dt_eleicao,
       stg.fn_nulo(DS_ELEICAO)                   AS ds_eleicao,
       stg.fn_nulo(NM_TIPO_ELEICAO)              AS nm_tipo_eleicao,
       TRY_CAST(CD_MUNICIPIO AS INT)             AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)                  AS nr_zona,
       TRY_CAST(CD_CARGO AS INT)                 AS cd_cargo,
       stg.fn_nulo(ST_VOTO_EM_TRANSITO)          AS st_voto_em_transito,
       TRY_CAST(QT_APTOS AS INT)                 AS qt_aptos,
       TRY_CAST(QT_COMPARECIMENTO AS INT)        AS qt_comparecimento,
       TRY_CAST(QT_ABSTENCOES AS INT)            AS qt_abstencoes,
       TRY_CAST(QT_VOTOS_NOMINAIS_VALIDOS AS INT) AS qt_votos_nominais,
       TRY_CAST(QT_VOTOS_LEG_VALIDOS AS INT)     AS qt_votos_legenda,
       TRY_CAST(QT_VOTOS_BRANCOS AS INT)         AS qt_votos_brancos,
       TRY_CAST(QT_VOTOS_NULOS AS INT)           AS qt_votos_nulos
INTO stg.detalhe_zona_limpa
FROM (SELECT DISTINCT * FROM stg.stg_detalhe_votacao_munzona) s
WHERE TRY_CAST(CD_CARGO AS INT) IN (1, 3, 5, 6, 7);
GO

/* ---------- Votação em partido por zona (base 5) ---------- */
DROP TABLE IF EXISTS stg.votacao_partido_zona_limpa;
GO

SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)         AS ano,
       TRY_CAST(NR_TURNO AS TINYINT)             AS turno,
       TRY_CAST(CD_MUNICIPIO AS INT)             AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)                  AS nr_zona,
       TRY_CAST(CD_CARGO AS INT)                 AS cd_cargo,
       TRY_CAST(NR_PARTIDO AS INT)               AS nr_partido,
       stg.fn_nulo(SG_PARTIDO)                   AS sg_partido,
       stg.fn_nulo(NM_PARTIDO)                   AS nm_partido,
       NULLIF(TRY_CAST(NR_FEDERACAO AS INT), -1) AS nr_federacao,
       stg.fn_nulo(SG_FEDERACAO)                 AS sg_federacao,
       stg.fn_nulo(NM_FEDERACAO)                 AS nm_federacao,
       stg.fn_nulo(ST_VOTO_EM_TRANSITO)          AS st_voto_em_transito,
       TRY_CAST(QT_VOTOS_NOMINAIS_VALIDOS AS INT) AS qt_votos_nominais,
       TRY_CAST(QT_VOTOS_LEGENDA_VALIDOS AS INT) AS qt_votos_legenda
INTO stg.votacao_partido_zona_limpa
FROM (SELECT DISTINCT * FROM stg.stg_votacao_partido_munzona) s
WHERE TRY_CAST(CD_CARGO AS INT) IN (1, 3, 5, 6, 7);
GO

/* ---------- Votação nominal por zona (base 6) ---------- */
DROP TABLE IF EXISTS stg.votacao_candidato_zona_limpa;
GO

SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)         AS ano,
       TRY_CAST(NR_TURNO AS TINYINT)             AS turno,
       TRY_CAST(CD_MUNICIPIO AS INT)             AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)                  AS nr_zona,
       TRY_CAST(CD_CARGO AS INT)                 AS cd_cargo,
       TRY_CAST(SQ_CANDIDATO AS BIGINT)          AS sq_candidato,
       TRY_CAST(NR_CANDIDATO AS INT)             AS nr_candidato,
       stg.fn_nulo(NM_URNA_CANDIDATO)            AS nm_urna_candidato,
       stg.fn_nulo(DS_SITUACAO_CANDIDATURA)      AS ds_situacao_candidatura,
       stg.fn_nulo(DS_SIT_TOT_TURNO)             AS ds_sit_tot_turno,
       TRY_CAST(NR_PARTIDO AS INT)               AS nr_partido,
       stg.fn_nulo(SG_PARTIDO)                   AS sg_partido,
       stg.fn_nulo(NM_PARTIDO)                   AS nm_partido,
       NULLIF(TRY_CAST(NR_FEDERACAO AS INT), -1) AS nr_federacao,
       stg.fn_nulo(SG_FEDERACAO)                 AS sg_federacao,
       stg.fn_nulo(NM_FEDERACAO)                 AS nm_federacao,
       stg.fn_nulo(ST_VOTO_EM_TRANSITO)          AS st_voto_em_transito,
       TRY_CAST(QT_VOTOS_NOMINAIS AS INT)        AS qt_votos_nominais,
       TRY_CAST(QT_VOTOS_NOMINAIS_VALIDOS AS INT) AS qt_votos_nominais_validos
INTO stg.votacao_candidato_zona_limpa
FROM (SELECT DISTINCT * FROM stg.stg_votacao_candidato_munzona) s
WHERE TRY_CAST(CD_CARGO AS INT) IN (1, 3, 5, 6, 7);
GO

/* ---------- Perfil do eleitorado por seção (base 10) ---------- */
DROP TABLE IF EXISTS stg.perfil_eleitor_secao_limpa;
GO

WITH u AS (
    SELECT ANO_ELEICAO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_GENERO, DS_GENERO, CD_FAIXA_ETARIA, DS_FAIXA_ETARIA, CD_GRAU_ESCOLARIDADE, DS_GRAU_ESCOLARIDADE, QT_ELEITORES_PERFIL, QT_ELEITORES_BIOMETRIA, QT_ELEITORES_DEFICIENCIA FROM stg.stg_perfil_eleitor_secao_es
    UNION ALL
    SELECT ANO_ELEICAO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_GENERO, DS_GENERO, CD_FAIXA_ETARIA, DS_FAIXA_ETARIA, CD_GRAU_ESCOLARIDADE, DS_GRAU_ESCOLARIDADE, QT_ELEITORES_PERFIL, QT_ELEITORES_BIOMETRIA, QT_ELEITORES_DEFICIENCIA FROM stg.stg_perfil_eleitor_secao_mg
    UNION ALL
    SELECT ANO_ELEICAO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_GENERO, DS_GENERO, CD_FAIXA_ETARIA, DS_FAIXA_ETARIA, CD_GRAU_ESCOLARIDADE, DS_GRAU_ESCOLARIDADE, QT_ELEITORES_PERFIL, QT_ELEITORES_BIOMETRIA, QT_ELEITORES_DEFICIENCIA FROM stg.stg_perfil_eleitor_secao_rj
    UNION ALL
    SELECT ANO_ELEICAO, CD_MUNICIPIO, NR_ZONA, NR_SECAO, CD_GENERO, DS_GENERO, CD_FAIXA_ETARIA, DS_FAIXA_ETARIA, CD_GRAU_ESCOLARIDADE, DS_GRAU_ESCOLARIDADE, QT_ELEITORES_PERFIL, QT_ELEITORES_BIOMETRIA, QT_ELEITORES_DEFICIENCIA FROM stg.stg_perfil_eleitor_secao_sp
)
SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)  AS ano,
       TRY_CAST(CD_MUNICIPIO AS INT)      AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)           AS nr_zona,
       TRY_CAST(NR_SECAO AS INT)          AS nr_secao,
       ISNULL(TRY_CAST(CD_GENERO AS INT), -1)           AS cd_genero,
       COALESCE(stg.fn_nulo(DS_GENERO), N'NÃO INFORMADO') AS ds_genero,
       ISNULL(TRY_CAST(CD_FAIXA_ETARIA AS INT), -1)     AS cd_faixa_etaria,
       COALESCE(stg.fn_nulo(DS_FAIXA_ETARIA), N'NÃO INFORMADO') AS ds_faixa_etaria,
       ISNULL(TRY_CAST(CD_GRAU_ESCOLARIDADE AS INT), -1) AS cd_grau_escolaridade,
       COALESCE(stg.fn_nulo(DS_GRAU_ESCOLARIDADE), N'NÃO INFORMADO') AS ds_grau_escolaridade,
       TRY_CAST(QT_ELEITORES_PERFIL AS INT)     AS qt_eleitores_perfil,
       TRY_CAST(QT_ELEITORES_BIOMETRIA AS INT)  AS qt_eleitores_biometria,
       TRY_CAST(QT_ELEITORES_DEFICIENCIA AS INT) AS qt_eleitores_deficiencia
INTO stg.perfil_eleitor_secao_limpa
FROM u;
GO

/* ---------- Perfil do comparecimento e abstenção (base 11) ---------- */
DROP TABLE IF EXISTS stg.perfil_comparecimento_limpa;
GO

SELECT TRY_CAST(ANO_ELEICAO AS SMALLINT)  AS ano,
       TRY_CAST(NR_TURNO AS TINYINT)      AS turno,
       TRY_CAST(CD_MUNICIPIO AS INT)      AS cd_municipio,
       TRY_CAST(NR_ZONA AS INT)           AS nr_zona,
       ISNULL(TRY_CAST(CD_GENERO AS INT), -1)           AS cd_genero,
       COALESCE(stg.fn_nulo(DS_GENERO), N'NÃO INFORMADO') AS ds_genero,
       ISNULL(TRY_CAST(CD_FAIXA_ETARIA AS INT), -1)     AS cd_faixa_etaria,
       COALESCE(stg.fn_nulo(DS_FAIXA_ETARIA), N'NÃO INFORMADO') AS ds_faixa_etaria,
       ISNULL(TRY_CAST(CD_GRAU_ESCOLARIDADE AS INT), -1) AS cd_grau_escolaridade,
       COALESCE(stg.fn_nulo(DS_GRAU_ESCOLARIDADE), N'NÃO INFORMADO') AS ds_grau_escolaridade,
       TRY_CAST(QT_APTOS AS INT)          AS qt_aptos,
       TRY_CAST(QT_COMPARECIMENTO AS INT) AS qt_comparecimento,
       TRY_CAST(QT_ABSTENCAO AS INT)      AS qt_abstencao
INTO stg.perfil_comparecimento_limpa
FROM (SELECT DISTINCT * FROM stg.stg_perfil_comparecimento_abstencao) s;
GO

/* ---------- Eleitorado por local de votação (base 12) ---------- */
DROP TABLE IF EXISTS stg.local_votacao_limpa;
GO

SELECT TRY_CAST(l.AA_ELEICAO AS SMALLINT)  AS ano,
       TRY_CAST(l.NR_TURNO AS TINYINT)     AS turno,
       TRY_CAST(l.CD_MUNICIPIO AS INT)     AS cd_municipio,
       TRY_CAST(l.NR_ZONA AS INT)          AS nr_zona,
       TRY_CAST(l.NR_SECAO AS INT)         AS nr_secao,
       TRY_CAST(l.NR_LOCAL_VOTACAO AS INT) AS nr_local_votacao,
       stg.fn_nulo(l.NM_LOCAL_VOTACAO)     AS nm_local_votacao,
       stg.fn_nulo(l.DS_ENDERECO)          AS ds_endereco,
       stg.fn_nulo(l.NM_BAIRRO)            AS nm_bairro,
       NULLIF(NULLIF(g.lat, 0), -1)        AS latitude,    -- 0 e -1 = coordenada ausente
       NULLIF(NULLIF(g.lon, 0), -1)        AS longitude,
       TRY_CAST(l.QT_ELEITOR_SECAO AS INT) AS qt_eleitor_secao
INTO stg.local_votacao_limpa
FROM stg.stg_eleitorado_local_votacao l
CROSS APPLY (SELECT TRY_CAST(REPLACE(l.NR_LATITUDE, N',', N'.') AS DECIMAL(9, 6))  AS lat,
                    TRY_CAST(REPLACE(l.NR_LONGITUDE, N',', N'.') AS DECIMAL(9, 6)) AS lon) g;
GO
