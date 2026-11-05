/* ============================================================
   03_dimensoes.sql
   Recria as dimensões do schema dw a partir das tabelas stg.*_limpa.
   - As fatos são apagadas primeiro (dependem das dimensões); 04_fatos.sql as recria.
   - dw.CFG_PARTIDO_ALVO NÃO é apagada: é a configuração do partido do cliente.
       INSERT INTO dw.CFG_PARTIDO_ALVO (nr_partido) VALUES (13);   -- exemplo
     e depois rode este script de novo para refletir em DIM_AGREMIACAO.fl_cliente.
   ============================================================ */

/* ---------- 0. Limpeza na ordem das dependências ---------- */
DROP TABLE IF EXISTS dw.FATO_PERFIL_COMPARECIMENTO_ZONA;
DROP TABLE IF EXISTS dw.FATO_PERFIL_ELEITORADO_SECAO;
DROP TABLE IF EXISTS dw.FATO_VOTACAO_CANDIDATO_ZONA;
DROP TABLE IF EXISTS dw.FATO_VOTACAO_PARTIDO_ZONA;
DROP TABLE IF EXISTS dw.FATO_VOTACAO_SECAO_PARTIDO;
DROP TABLE IF EXISTS dw.FATO_DETALHE_ZONA;
DROP TABLE IF EXISTS dw.FATO_DETALHE_SECAO;
DROP TABLE IF EXISTS dw.BRIDGE_ZONA;
DROP TABLE IF EXISTS dw.DIM_SECAO;
DROP TABLE IF EXISTS dw.DIM_ZONA;
DROP TABLE IF EXISTS dw.DIM_PERFIL;
DROP TABLE IF EXISTS dw.DIM_CANDIDATO;
DROP TABLE IF EXISTS dw.DIM_AGREMIACAO;
DROP TABLE IF EXISTS dw.DIM_TIPO_VOTO;
DROP TABLE IF EXISTS dw.DIM_CARGO;
DROP TABLE IF EXISTS dw.DIM_ELEICAO;
DROP TABLE IF EXISTS dw.DIM_MUNICIPIO;

IF OBJECT_ID('dw.CFG_PARTIDO_ALVO', 'U') IS NULL
    CREATE TABLE dw.CFG_PARTIDO_ALVO (nr_partido INT NOT NULL PRIMARY KEY);
GO

/* ---------- 1. DIM_MUNICIPIO (4 capitais) ---------- */
-- lat/lon_centro: ponto de referência do centro de cada capital (ajustável),
-- usado para a distância das zonas ao centro.
CREATE TABLE dw.DIM_MUNICIPIO (
    sk_municipio      INT           NOT NULL PRIMARY KEY,
    cd_municipio_tse  INT           NOT NULL UNIQUE,
    cd_municipio_ibge INT           NOT NULL,
    nm_municipio      NVARCHAR(60)  NOT NULL,
    sg_uf             CHAR(2)       NOT NULL,
    fl_capital        BIT           NOT NULL,
    lat_centro        DECIMAL(9, 6) NOT NULL,
    lon_centro        DECIMAL(9, 6) NOT NULL
);

INSERT INTO dw.DIM_MUNICIPIO
    (sk_municipio, cd_municipio_tse, cd_municipio_ibge, nm_municipio, sg_uf, fl_capital, lat_centro, lon_centro)
VALUES
    (1, 71072, 3550308, N'SÃO PAULO',      'SP', 1, -23.550520, -46.633308),
    (2, 60011, 3304557, N'RIO DE JANEIRO', 'RJ', 1, -22.906847, -43.172897),
    (3, 41238, 3106200, N'BELO HORIZONTE', 'MG', 1, -19.916681, -43.934493),
    (4, 57053, 3205309, N'VITÓRIA',        'ES', 1, -20.315500, -40.312800);
GO

/* ---------- 2. DIM_ELEICAO ---------- */
CREATE TABLE dw.DIM_ELEICAO (
    sk_eleicao      INT IDENTITY(1, 1) PRIMARY KEY,
    ano             SMALLINT      NOT NULL,
    turno           TINYINT       NOT NULL,
    dt_eleicao      DATE          NULL,
    ds_eleicao      NVARCHAR(100) NULL,
    nm_tipo_eleicao NVARCHAR(60)  NULL,
    CONSTRAINT UQ_DIM_ELEICAO UNIQUE (ano, turno)
);

INSERT INTO dw.DIM_ELEICAO (ano, turno, dt_eleicao, ds_eleicao, nm_tipo_eleicao)
SELECT ano, turno, MAX(dt_eleicao), MAX(ds_eleicao), MAX(nm_tipo_eleicao)
FROM stg.detalhe_zona_limpa
WHERE ano IS NOT NULL AND turno IS NOT NULL
GROUP BY ano, turno;
GO

/* ---------- 3. DIM_CARGO ---------- */
CREATE TABLE dw.DIM_CARGO (
    sk_cargo         INT           IDENTITY(1, 1) PRIMARY KEY,
    cd_cargo         INT           NOT NULL UNIQUE,
    ds_cargo         NVARCHAR(40)  NOT NULL,
    fl_majoritario   BIT           NOT NULL,
    fl_proporcional  BIT           NOT NULL
);

INSERT INTO dw.DIM_CARGO (cd_cargo, ds_cargo, fl_majoritario, fl_proporcional)
VALUES (1, N'Presidente', 1, 0),
       (3, N'Governador', 1, 0),
       (5, N'Senador', 1, 0),
       (6, N'Deputado Federal', 0, 1),
       (7, N'Deputado Estadual', 0, 1);
GO

/* ---------- 4. DIM_TIPO_VOTO ---------- */
CREATE TABLE dw.DIM_TIPO_VOTO (
    sk_tipo_voto  TINYINT     NOT NULL PRIMARY KEY,
    ds_tipo_voto  VARCHAR(10) NOT NULL UNIQUE,
    fl_valido     BIT         NOT NULL
);

INSERT INTO dw.DIM_TIPO_VOTO (sk_tipo_voto, ds_tipo_voto, fl_valido)
VALUES (1, 'NOMINAL', 1), (2, 'LEGENDA', 1), (3, 'BRANCO', 0), (4, 'NULO', 0);
GO

/* ---------- 5. DIM_ZONA (uma linha por ano) ---------- */
CREATE TABLE dw.DIM_ZONA (
    sk_zona              INT IDENTITY(1, 1) PRIMARY KEY,
    ano                  SMALLINT     NOT NULL,
    sk_municipio         INT          NOT NULL REFERENCES dw.DIM_MUNICIPIO (sk_municipio),
    nr_zona              INT          NOT NULL,
    sk_zona_estavel      INT          NULL,   -- liga a mesma zona entre anos (ver BRIDGE_ZONA)
    distancia_centro_km  DECIMAL(8, 3) NULL,
    fl_zona_periferica   BIT          NULL,   -- quartil mais distante do centro da capital
    CONSTRAINT UQ_DIM_ZONA UNIQUE (ano, sk_municipio, nr_zona)
);
GO

WITH k AS (
    SELECT ano, cd_municipio, nr_zona FROM stg.detalhe_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.detalhe_zona_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.votacao_partido_zona_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.votacao_candidato_zona_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.perfil_eleitor_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.perfil_comparecimento_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.votacao_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona FROM stg.local_votacao_limpa
)
INSERT INTO dw.DIM_ZONA (ano, sk_municipio, nr_zona)
SELECT k.ano, m.sk_municipio, k.nr_zona
FROM k
JOIN dw.DIM_MUNICIPIO m ON m.cd_municipio_tse = k.cd_municipio
WHERE k.ano IS NOT NULL AND k.nr_zona IS NOT NULL;

-- Em 2022 a zona estável é ela mesma; as zonas de 2026 apontarão para estas via BRIDGE_ZONA.
UPDATE dw.DIM_ZONA SET sk_zona_estavel = sk_zona WHERE ano = 2022;
GO

/* ---------- 6. DIM_SECAO (uma linha por ano) ---------- */
CREATE TABLE dw.DIM_SECAO (
    sk_secao          INT IDENTITY(1, 1) PRIMARY KEY,
    sk_zona           INT           NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    nr_secao          INT           NOT NULL,
    nr_local_votacao  INT           NULL,
    nm_local_votacao  NVARCHAR(200) NULL,
    ds_endereco       NVARCHAR(300) NULL,
    nm_bairro         NVARCHAR(100) NULL,
    latitude          DECIMAL(9, 6) NULL,
    longitude         DECIMAL(9, 6) NULL,
    CONSTRAINT UQ_DIM_SECAO UNIQUE (sk_zona, nr_secao)
);
GO

WITH k AS (
    SELECT ano, cd_municipio, nr_zona, nr_secao FROM stg.detalhe_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona, nr_secao FROM stg.votacao_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona, nr_secao FROM stg.perfil_eleitor_secao_limpa
    UNION SELECT ano, cd_municipio, nr_zona, nr_secao FROM stg.local_votacao_limpa
),
loc AS (   -- local de votação segundo a apuração (último turno disponível)
    SELECT ano, cd_municipio, nr_zona, nr_secao, nr_local_votacao, nm_local_votacao, ds_endereco,
           ROW_NUMBER() OVER (PARTITION BY ano, cd_municipio, nr_zona, nr_secao ORDER BY turno DESC) AS rn
    FROM stg.detalhe_secao_limpa
    WHERE nr_local_votacao IS NOT NULL
),
geo AS (   -- endereço, bairro e coordenadas segundo a base de eleitorado por local
    SELECT ano, cd_municipio, nr_zona, nr_secao, nr_local_votacao, nm_local_votacao, ds_endereco,
           nm_bairro, latitude, longitude,
           ROW_NUMBER() OVER (PARTITION BY ano, cd_municipio, nr_zona, nr_secao ORDER BY turno) AS rn
    FROM stg.local_votacao_limpa
)
INSERT INTO dw.DIM_SECAO
    (sk_zona, nr_secao, nr_local_votacao, nm_local_votacao, ds_endereco, nm_bairro, latitude, longitude)
SELECT z.sk_zona,
       k.nr_secao,
       COALESCE(l.nr_local_votacao, g.nr_local_votacao),
       COALESCE(l.nm_local_votacao, g.nm_local_votacao),
       COALESCE(l.ds_endereco, g.ds_endereco),
       g.nm_bairro,
       -- descarta coordenadas fora de ~0,5 grau do centro da capital (geocodificação errada)
       CASE WHEN ABS(g.latitude - m.lat_centro) <= 0.5 AND ABS(g.longitude - m.lon_centro) <= 0.5
            THEN g.latitude END,
       CASE WHEN ABS(g.latitude - m.lat_centro) <= 0.5 AND ABS(g.longitude - m.lon_centro) <= 0.5
            THEN g.longitude END
FROM k
JOIN dw.DIM_MUNICIPIO m ON m.cd_municipio_tse = k.cd_municipio
JOIN dw.DIM_ZONA z ON z.ano = k.ano AND z.sk_municipio = m.sk_municipio AND z.nr_zona = k.nr_zona
LEFT JOIN loc l ON l.rn = 1 AND l.ano = k.ano AND l.cd_municipio = k.cd_municipio
               AND l.nr_zona = k.nr_zona AND l.nr_secao = k.nr_secao
LEFT JOIN geo g ON g.rn = 1 AND g.ano = k.ano AND g.cd_municipio = k.cd_municipio
               AND g.nr_zona = k.nr_zona AND g.nr_secao = k.nr_secao
WHERE k.nr_secao IS NOT NULL;
GO

/* ---------- 7. Distância ao centro e zona periférica (quartil mais distante) ---------- */
WITH c AS (
    SELECT z.sk_zona, z.sk_municipio, m.lat_centro, m.lon_centro,
           AVG(CAST(s.latitude AS FLOAT))  AS lat,
           AVG(CAST(s.longitude AS FLOAT)) AS lon
    FROM dw.DIM_ZONA z
    JOIN dw.DIM_MUNICIPIO m ON m.sk_municipio = z.sk_municipio
    JOIN dw.DIM_SECAO s ON s.sk_zona = z.sk_zona
    WHERE s.latitude IS NOT NULL AND s.longitude IS NOT NULL
    GROUP BY z.sk_zona, z.sk_municipio, m.lat_centro, m.lon_centro
),
d AS (
    SELECT sk_zona, sk_municipio,
           geography::Point(lat, lon, 4326).STDistance(
               geography::Point(CAST(lat_centro AS FLOAT), CAST(lon_centro AS FLOAT), 4326)) / 1000.0 AS km
    FROM c
),
q AS (
    SELECT sk_zona, km, NTILE(4) OVER (PARTITION BY sk_municipio ORDER BY km) AS quartil
    FROM d
)
UPDATE z
SET z.distancia_centro_km = q.km,
    z.fl_zona_periferica  = CASE WHEN q.quartil = 4 THEN 1 ELSE 0 END
FROM dw.DIM_ZONA z
JOIN q ON q.sk_zona = z.sk_zona;
GO

/* ---------- 8. BRIDGE_ZONA (estrutura; será preenchida quando houver 2026) ---------- */
CREATE TABLE dw.BRIDGE_ZONA (
    sk_zona_2022       INT          NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    sk_zona_2026       INT          NOT NULL REFERENCES dw.DIM_ZONA (sk_zona),
    pct_locais_comuns  DECIMAL(5, 2) NOT NULL,
    fl_comparavel      AS (CASE WHEN pct_locais_comuns >= 80 THEN 1 ELSE 0 END),
    PRIMARY KEY (sk_zona_2022, sk_zona_2026)
);
GO

/* ---------- 9. DIM_PERFIL (gênero x faixa etária x escolaridade) ---------- */
CREATE TABLE dw.DIM_PERFIL (
    sk_perfil                 INT IDENTITY(1, 1) PRIMARY KEY,
    cd_genero                 INT           NOT NULL,
    ds_genero                 NVARCHAR(40)  NOT NULL,
    fl_feminino               BIT           NOT NULL,
    cd_faixa_etaria           INT           NOT NULL,
    ds_faixa_etaria           NVARCHAR(40)  NOT NULL,
    cd_grau_escolaridade      INT           NOT NULL,
    ds_grau_escolaridade      NVARCHAR(60)  NOT NULL,
    fl_jovem_18_24            BIT           NOT NULL,
    fl_60_69                  BIT           NOT NULL,
    fl_70_mais                BIT           NOT NULL,
    fl_facultativo            BIT           NOT NULL,  -- 16-17 anos, 70+ e analfabetos
    fl_escolaridade_informada BIT           NOT NULL,
    fl_sem_medio_completo     BIT           NOT NULL,  -- analfabeto até médio incompleto
    fl_superior_completo      BIT           NOT NULL,
    CONSTRAINT UQ_DIM_PERFIL UNIQUE (cd_genero, cd_faixa_etaria, cd_grau_escolaridade)
);

INSERT INTO dw.DIM_PERFIL
    (cd_genero, ds_genero, fl_feminino, cd_faixa_etaria, ds_faixa_etaria,
     cd_grau_escolaridade, ds_grau_escolaridade,
     fl_jovem_18_24, fl_60_69, fl_70_mais, fl_facultativo,
     fl_escolaridade_informada, fl_sem_medio_completo, fl_superior_completo)
SELECT cd_genero,
       MAX(ds_genero),
       MAX(CASE WHEN UPPER(ds_genero) = N'FEMININO' THEN 1 ELSE 0 END),
       cd_faixa_etaria,
       MAX(ds_faixa_etaria),
       cd_grau_escolaridade,
       MAX(ds_grau_escolaridade),
       CASE WHEN cd_faixa_etaria IN (1800, 1900, 2000, 2124) THEN 1 ELSE 0 END,
       CASE WHEN cd_faixa_etaria IN (6064, 6569) THEN 1 ELSE 0 END,
       CASE WHEN cd_faixa_etaria IN (7074, 7579, 8084, 8589, 9094, 9599, 9999) THEN 1 ELSE 0 END,
       CASE WHEN cd_faixa_etaria IN (1600, 1700, 7074, 7579, 8084, 8589, 9094, 9599, 9999)
                 OR cd_grau_escolaridade = 1 THEN 1 ELSE 0 END,
       CASE WHEN cd_grau_escolaridade BETWEEN 1 AND 8 THEN 1 ELSE 0 END,
       CASE WHEN cd_grau_escolaridade BETWEEN 1 AND 5 THEN 1 ELSE 0 END,
       CASE WHEN cd_grau_escolaridade = 8 THEN 1 ELSE 0 END
FROM (
    SELECT cd_genero, ds_genero, cd_faixa_etaria, ds_faixa_etaria, cd_grau_escolaridade, ds_grau_escolaridade
    FROM stg.perfil_comparecimento_limpa
    UNION
    SELECT cd_genero, ds_genero, cd_faixa_etaria, ds_faixa_etaria, cd_grau_escolaridade, ds_grau_escolaridade
    FROM stg.perfil_eleitor_secao_limpa
) p
GROUP BY cd_genero, cd_faixa_etaria, cd_grau_escolaridade;
GO

/* ---------- 10. DIM_AGREMIACAO (SCD tipo 2; carga inicial = vigência 2022) ---------- */
CREATE TABLE dw.DIM_AGREMIACAO (
    sk_agremiacao    INT IDENTITY(1, 1) PRIMARY KEY,
    nr_partido       INT           NOT NULL,
    sg_partido       NVARCHAR(30)  NULL,
    nm_partido       NVARCHAR(100) NULL,
    nr_federacao     INT           NULL,
    sg_federacao     NVARCHAR(50)  NULL,
    nm_federacao     NVARCHAR(150) NULL,
    fl_cliente       BIT           NOT NULL DEFAULT 0,
    vigencia_inicio  DATE          NOT NULL,
    vigencia_fim     DATE          NOT NULL,
    fl_atual         BIT           NOT NULL,
    CONSTRAINT UQ_DIM_AGREMIACAO UNIQUE (nr_partido, vigencia_inicio)
);
GO

-- sk 0 = "não se aplica" (votos brancos e nulos não têm partido)
SET IDENTITY_INSERT dw.DIM_AGREMIACAO ON;
INSERT INTO dw.DIM_AGREMIACAO
    (sk_agremiacao, nr_partido, sg_partido, nm_partido, fl_cliente, vigencia_inicio, vigencia_fim, fl_atual)
VALUES (0, 0, N'N/A', N'Não se aplica', 0, '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dw.DIM_AGREMIACAO OFF;
GO

INSERT INTO dw.DIM_AGREMIACAO
    (nr_partido, sg_partido, nm_partido, nr_federacao, sg_federacao, nm_federacao,
     fl_cliente, vigencia_inicio, vigencia_fim, fl_atual)
SELECT p.nr_partido, p.sg_partido, p.nm_partido, p.nr_federacao, p.sg_federacao, p.nm_federacao,
       CASE WHEN c.nr_partido IS NOT NULL THEN 1 ELSE 0 END,
       '2022-01-01', '9999-12-31', 1
FROM (
    SELECT nr_partido, MAX(sg_partido) AS sg_partido, MAX(nm_partido) AS nm_partido,
           MAX(nr_federacao) AS nr_federacao, MAX(sg_federacao) AS sg_federacao, MAX(nm_federacao) AS nm_federacao
    FROM (
        SELECT nr_partido, sg_partido, nm_partido, nr_federacao, sg_federacao, nm_federacao
        FROM stg.votacao_partido_zona_limpa
        UNION ALL
        SELECT nr_partido, sg_partido, nm_partido, nr_federacao, sg_federacao, nm_federacao
        FROM stg.votacao_candidato_zona_limpa
    ) u
    WHERE nr_partido IS NOT NULL
    GROUP BY nr_partido
) p
LEFT JOIN dw.CFG_PARTIDO_ALVO c ON c.nr_partido = p.nr_partido;

-- números de partido que só aparecem na votação por seção (sem nome nas outras bases)
INSERT INTO dw.DIM_AGREMIACAO
    (nr_partido, sg_partido, nm_partido, fl_cliente, vigencia_inicio, vigencia_fim, fl_atual)
SELECT v.nr_partido, CONCAT(N'Nº ', v.nr_partido), NULL,
       CASE WHEN c.nr_partido IS NOT NULL THEN 1 ELSE 0 END,
       '2022-01-01', '9999-12-31', 1
FROM (SELECT DISTINCT nr_partido FROM stg.votacao_secao_limpa WHERE nr_partido IS NOT NULL) v
LEFT JOIN dw.CFG_PARTIDO_ALVO c ON c.nr_partido = v.nr_partido
WHERE NOT EXISTS (SELECT 1 FROM dw.DIM_AGREMIACAO a WHERE a.nr_partido = v.nr_partido);
GO

/* ---------- 11. DIM_CANDIDATO (sem CPF nem contatos) ---------- */
CREATE TABLE dw.DIM_CANDIDATO (
    sk_candidato             INT IDENTITY(1, 1) PRIMARY KEY,
    sq_candidato             BIGINT        NOT NULL UNIQUE,
    nr_candidato             INT           NULL,
    nm_urna_candidato        NVARCHAR(100) NULL,
    nr_partido               INT           NULL,
    sg_partido               NVARCHAR(30)  NULL,
    cd_cargo                 INT           NOT NULL,
    ds_situacao_candidatura  NVARCHAR(60)  NULL
);

INSERT INTO dw.DIM_CANDIDATO
    (sq_candidato, nr_candidato, nm_urna_candidato, nr_partido, sg_partido, cd_cargo, ds_situacao_candidatura)
SELECT sq_candidato, nr_candidato, nm_urna_candidato, nr_partido, sg_partido, cd_cargo, ds_situacao_candidatura
FROM (
    SELECT sq_candidato, nr_candidato, nm_urna_candidato, nr_partido, sg_partido, cd_cargo, ds_situacao_candidatura,
           ROW_NUMBER() OVER (PARTITION BY sq_candidato ORDER BY turno DESC) AS rn
    FROM stg.votacao_candidato_zona_limpa
    WHERE sq_candidato IS NOT NULL
) x
WHERE rn = 1;
GO
