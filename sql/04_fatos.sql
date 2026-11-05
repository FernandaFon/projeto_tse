/* ============================================================
   04_fatos.sql
   Cria e carrega as 7 tabelas fato do schema dw (rode depois de 03_dimensoes.sql).
   Só medidas aditivas ficam nas fatos; taxas (K1, K2b, ...) são calculadas
   como razão das somas no BI. Cada INSERT agrega pelo grão da tabela, então a
   chave primária garante que não haja linhas duplicadas.
   03_dimensoes.sql apaga as fatos; este script as recria do zero.
   ============================================================ */

/* ---------- FATO_DETALHE_SECAO: seção x eleição x cargo (fato âncora) ---------- */
CREATE TABLE dw.FATO_DETALHE_SECAO (
    sk_eleicao          INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_cargo            INT NOT NULL REFERENCES dw.DIM_CARGO (sk_cargo),
    sk_municipio        INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona             INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_secao            INT NOT NULL REFERENCES dw.DIM_SECAO (sk_secao),
    qt_aptos            INT NULL,
    qt_comparecimento   INT NULL,
    qt_abstencoes       INT NULL,
    qt_votos_nominais   INT NULL,
    qt_votos_legenda    INT NULL,
    qt_votos_brancos    INT NULL,
    qt_votos_nulos      INT NULL,
    fl_secao_instalada  BIT NULL,
    fl_secao_anulada    BIT NULL,
    PRIMARY KEY (sk_eleicao, sk_cargo, sk_secao)
);
GO

INSERT INTO dw.FATO_DETALHE_SECAO
    (sk_eleicao, sk_cargo, sk_municipio, sk_zona, sk_secao,
     qt_aptos, qt_comparecimento, qt_abstencoes, qt_votos_nominais, qt_votos_legenda,
     qt_votos_brancos, qt_votos_nulos, fl_secao_instalada, fl_secao_anulada)
SELECT e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, s.sk_secao,
       SUM(d.qt_aptos), SUM(d.qt_comparecimento), SUM(d.qt_abstencoes),
       SUM(d.qt_votos_nominais), SUM(d.qt_votos_legenda),
       SUM(d.qt_votos_brancos), SUM(d.qt_votos_nulos),
       MAX(CAST(d.fl_secao_instalada AS TINYINT)), MAX(CAST(d.fl_secao_anulada AS TINYINT))
FROM stg.detalhe_secao_limpa d
JOIN dw.DIM_ELEICAO   e ON e.ano = d.ano AND e.turno = d.turno
JOIN dw.DIM_CARGO     c ON c.cd_cargo = d.cd_cargo
JOIN dw.DIM_MUNICIPIO m ON m.cd_municipio_tse = d.cd_municipio
JOIN dw.DIM_ZONA      z ON z.ano = d.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = d.nr_zona
JOIN dw.DIM_SECAO     s ON s.sk_zona = z.sk_zona AND s.nr_secao = d.nr_secao
GROUP BY e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, s.sk_secao;
GO

/* ---------- FATO_DETALHE_ZONA: zona x eleição x cargo ---------- */
CREATE TABLE dw.FATO_DETALHE_ZONA (
    sk_eleicao          INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_cargo            INT NOT NULL REFERENCES dw.DIM_CARGO (sk_cargo),
    sk_municipio        INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona             INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    qt_aptos            INT NULL,
    qt_comparecimento   INT NULL,
    qt_abstencoes       INT NULL,
    qt_votos_nominais   INT NULL,
    qt_votos_legenda    INT NULL,
    qt_votos_brancos    INT NULL,
    qt_votos_nulos      INT NULL,
    PRIMARY KEY (sk_eleicao, sk_cargo, sk_zona)
);
GO

INSERT INTO dw.FATO_DETALHE_ZONA
    (sk_eleicao, sk_cargo, sk_municipio, sk_zona,
     qt_aptos, qt_comparecimento, qt_abstencoes, qt_votos_nominais, qt_votos_legenda,
     qt_votos_brancos, qt_votos_nulos)
SELECT e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona,
       SUM(d.qt_aptos), SUM(d.qt_comparecimento), SUM(d.qt_abstencoes),
       SUM(d.qt_votos_nominais), SUM(d.qt_votos_legenda),
       SUM(d.qt_votos_brancos), SUM(d.qt_votos_nulos)
FROM stg.detalhe_zona_limpa d
JOIN dw.DIM_ELEICAO   e ON e.ano = d.ano AND e.turno = d.turno
JOIN dw.DIM_CARGO     c ON c.cd_cargo = d.cd_cargo
JOIN dw.DIM_MUNICIPIO m ON m.cd_municipio_tse = d.cd_municipio
JOIN dw.DIM_ZONA      z ON z.ano = d.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = d.nr_zona
GROUP BY e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona;
GO

/* ---------- FATO_VOTACAO_SECAO_PARTIDO: seção x eleição x cargo x agremiação x tipo de voto ---------- */
CREATE TABLE dw.FATO_VOTACAO_SECAO_PARTIDO (
    sk_eleicao     INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_cargo       INT NOT NULL REFERENCES dw.DIM_CARGO (sk_cargo),
    sk_municipio   INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona        INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_secao       INT NOT NULL REFERENCES dw.DIM_SECAO (sk_secao),
    sk_agremiacao  INT NOT NULL REFERENCES dw.DIM_AGREMIACAO (sk_agremiacao),
    sk_tipo_voto   TINYINT NOT NULL REFERENCES dw.DIM_TIPO_VOTO (sk_tipo_voto),
    qt_votos       INT NOT NULL,
    PRIMARY KEY (sk_eleicao, sk_cargo, sk_secao, sk_agremiacao, sk_tipo_voto)
);
GO

INSERT INTO dw.FATO_VOTACAO_SECAO_PARTIDO
    (sk_eleicao, sk_cargo, sk_municipio, sk_zona, sk_secao, sk_agremiacao, sk_tipo_voto, qt_votos)
SELECT e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, s.sk_secao,
       COALESCE(a.sk_agremiacao, 0), t.sk_tipo_voto, x.qt_votos
FROM (
    SELECT ano, turno, cd_municipio, nr_zona, nr_secao, cd_cargo, nr_partido, tipo_voto,
           SUM(COALESCE(qt_votos, 0)) AS qt_votos
    FROM stg.votacao_secao_limpa
    GROUP BY ano, turno, cd_municipio, nr_zona, nr_secao, cd_cargo, nr_partido, tipo_voto
) x
JOIN dw.DIM_ELEICAO    e ON e.ano = x.ano AND e.turno = x.turno
JOIN dw.DIM_CARGO      c ON c.cd_cargo = x.cd_cargo
JOIN dw.DIM_MUNICIPIO  m ON m.cd_municipio_tse = x.cd_municipio
JOIN dw.DIM_ZONA       z ON z.ano = x.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = x.nr_zona
JOIN dw.DIM_SECAO      s ON s.sk_zona = z.sk_zona AND s.nr_secao = x.nr_secao
JOIN dw.DIM_TIPO_VOTO  t ON t.ds_tipo_voto = x.tipo_voto
LEFT JOIN dw.DIM_AGREMIACAO a ON a.nr_partido = x.nr_partido AND a.fl_atual = 1;
GO

/* ---------- FATO_VOTACAO_PARTIDO_ZONA: zona x eleição x cargo x agremiação ---------- */
CREATE TABLE dw.FATO_VOTACAO_PARTIDO_ZONA (
    sk_eleicao         INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_cargo           INT NOT NULL REFERENCES dw.DIM_CARGO (sk_cargo),
    sk_municipio       INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona            INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_agremiacao      INT NOT NULL REFERENCES dw.DIM_AGREMIACAO (sk_agremiacao),
    qt_votos_nominais  INT NULL,
    qt_votos_legenda   INT NULL,
    PRIMARY KEY (sk_eleicao, sk_cargo, sk_zona, sk_agremiacao)
);
GO

INSERT INTO dw.FATO_VOTACAO_PARTIDO_ZONA
    (sk_eleicao, sk_cargo, sk_municipio, sk_zona, sk_agremiacao, qt_votos_nominais, qt_votos_legenda)
SELECT e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, COALESCE(a.sk_agremiacao, 0),
       SUM(p.qt_votos_nominais), SUM(p.qt_votos_legenda)
FROM stg.votacao_partido_zona_limpa p
JOIN dw.DIM_ELEICAO   e ON e.ano = p.ano AND e.turno = p.turno
JOIN dw.DIM_CARGO     c ON c.cd_cargo = p.cd_cargo
JOIN dw.DIM_MUNICIPIO m ON m.cd_municipio_tse = p.cd_municipio
JOIN dw.DIM_ZONA      z ON z.ano = p.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = p.nr_zona
LEFT JOIN dw.DIM_AGREMIACAO a ON a.nr_partido = p.nr_partido AND a.fl_atual = 1
GROUP BY e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, COALESCE(a.sk_agremiacao, 0);
GO

/* ---------- FATO_VOTACAO_CANDIDATO_ZONA: zona x eleição x cargo x candidato ---------- */
CREATE TABLE dw.FATO_VOTACAO_CANDIDATO_ZONA (
    sk_eleicao                 INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_cargo                   INT NOT NULL REFERENCES dw.DIM_CARGO (sk_cargo),
    sk_municipio               INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona                    INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_candidato               INT NOT NULL REFERENCES dw.DIM_CANDIDATO (sk_candidato),
    sk_agremiacao              INT NOT NULL REFERENCES dw.DIM_AGREMIACAO (sk_agremiacao),
    qt_votos_nominais          INT NULL,
    qt_votos_nominais_validos  INT NULL,
    ds_sit_tot_turno           NVARCHAR(60) NULL,   -- situação do candidato no turno (eleito, 2º turno, ...)
    PRIMARY KEY (sk_eleicao, sk_cargo, sk_zona, sk_candidato)
);
GO

INSERT INTO dw.FATO_VOTACAO_CANDIDATO_ZONA
    (sk_eleicao, sk_cargo, sk_municipio, sk_zona, sk_candidato, sk_agremiacao,
     qt_votos_nominais, qt_votos_nominais_validos, ds_sit_tot_turno)
SELECT e.sk_eleicao, c.sk_cargo, m.sk_municipio, z.sk_zona, k.sk_candidato,
       COALESCE(a.sk_agremiacao, 0), x.qt_votos_nominais, x.qt_votos_nominais_validos, x.ds_sit_tot_turno
FROM (
    SELECT ano, turno, cd_municipio, nr_zona, cd_cargo, sq_candidato,
           MAX(nr_partido) AS nr_partido, MAX(ds_sit_tot_turno) AS ds_sit_tot_turno,
           SUM(qt_votos_nominais) AS qt_votos_nominais,
           SUM(qt_votos_nominais_validos) AS qt_votos_nominais_validos
    FROM stg.votacao_candidato_zona_limpa
    WHERE sq_candidato IS NOT NULL
    GROUP BY ano, turno, cd_municipio, nr_zona, cd_cargo, sq_candidato
) x
JOIN dw.DIM_ELEICAO    e ON e.ano = x.ano AND e.turno = x.turno
JOIN dw.DIM_CARGO      c ON c.cd_cargo = x.cd_cargo
JOIN dw.DIM_MUNICIPIO  m ON m.cd_municipio_tse = x.cd_municipio
JOIN dw.DIM_ZONA       z ON z.ano = x.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = x.nr_zona
JOIN dw.DIM_CANDIDATO  k ON k.sq_candidato = x.sq_candidato
LEFT JOIN dw.DIM_AGREMIACAO a ON a.nr_partido = x.nr_partido AND a.fl_atual = 1;
GO

/* ---------- FATO_PERFIL_ELEITORADO_SECAO: seção x eleição x perfil ---------- */
-- A base 10 não tem turno (perfil publicado antes da eleição): associada ao 1º turno.
CREATE TABLE dw.FATO_PERFIL_ELEITORADO_SECAO (
    sk_eleicao                INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_municipio              INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona                   INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_secao                  INT NOT NULL REFERENCES dw.DIM_SECAO (sk_secao),
    sk_perfil                 INT NOT NULL REFERENCES dw.DIM_PERFIL (sk_perfil),
    qt_eleitores_perfil       INT NULL,
    qt_eleitores_biometria    INT NULL,
    qt_eleitores_deficiencia  INT NULL,
    PRIMARY KEY (sk_eleicao, sk_secao, sk_perfil)
);
GO

INSERT INTO dw.FATO_PERFIL_ELEITORADO_SECAO
    (sk_eleicao, sk_municipio, sk_zona, sk_secao, sk_perfil,
     qt_eleitores_perfil, qt_eleitores_biometria, qt_eleitores_deficiencia)
SELECT e.sk_eleicao, m.sk_municipio, z.sk_zona, s.sk_secao, pf.sk_perfil,
       SUM(p.qt_eleitores_perfil), SUM(p.qt_eleitores_biometria), SUM(p.qt_eleitores_deficiencia)
FROM stg.perfil_eleitor_secao_limpa p
JOIN dw.DIM_ELEICAO   e  ON e.ano = p.ano AND e.turno = 1
JOIN dw.DIM_MUNICIPIO m  ON m.cd_municipio_tse = p.cd_municipio
JOIN dw.DIM_ZONA      z  ON z.ano = p.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = p.nr_zona
JOIN dw.DIM_SECAO     s  ON s.sk_zona = z.sk_zona AND s.nr_secao = p.nr_secao
JOIN dw.DIM_PERFIL    pf ON pf.cd_genero = p.cd_genero AND pf.cd_faixa_etaria = p.cd_faixa_etaria
                        AND pf.cd_grau_escolaridade = p.cd_grau_escolaridade
GROUP BY e.sk_eleicao, m.sk_municipio, z.sk_zona, s.sk_secao, pf.sk_perfil;
GO

/* ---------- FATO_PERFIL_COMPARECIMENTO_ZONA: zona x eleição(turno) x perfil ---------- */
CREATE TABLE dw.FATO_PERFIL_COMPARECIMENTO_ZONA (
    sk_eleicao         INT NOT NULL REFERENCES dw.DIM_ELEICAO (sk_eleicao),
    sk_municipio       INT NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    sk_zona            INT NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_perfil          INT NOT NULL REFERENCES dw.DIM_PERFIL (sk_perfil),
    qt_aptos           INT NULL,
    qt_comparecimento  INT NULL,
    qt_abstencao       INT NULL,
    PRIMARY KEY (sk_eleicao, sk_zona, sk_perfil)
);
GO

INSERT INTO dw.FATO_PERFIL_COMPARECIMENTO_ZONA
    (sk_eleicao, sk_municipio, sk_zona, sk_perfil, qt_aptos, qt_comparecimento, qt_abstencao)
SELECT e.sk_eleicao, m.sk_municipio, z.sk_zona, pf.sk_perfil,
       SUM(p.qt_aptos), SUM(p.qt_comparecimento), SUM(p.qt_abstencao)
FROM stg.perfil_comparecimento_limpa p
JOIN dw.DIM_ELEICAO   e  ON e.ano = p.ano AND e.turno = p.turno
JOIN dw.DIM_MUNICIPIO m  ON m.cd_municipio_tse = p.cd_municipio
JOIN dw.DIM_ZONA      z  ON z.ano = p.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = p.nr_zona
JOIN dw.DIM_PERFIL    pf ON pf.cd_genero = p.cd_genero AND pf.cd_faixa_etaria = p.cd_faixa_etaria
                        AND pf.cd_grau_escolaridade = p.cd_grau_escolaridade
GROUP BY e.sk_eleicao, m.sk_municipio, z.sk_zona, pf.sk_perfil;
GO
