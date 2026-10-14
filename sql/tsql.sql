USE tse_warehouse;

-- =========================================================================
-- 1. LIMPEZA E RECRIAÇÃO DO STAR SCHEMA (Ordem correta de dependência)
-- =========================================================================
IF OBJECT_ID('gold.fat_votacao_secao', 'U') IS NOT NULL DROP TABLE gold.fat_votacao_secao;
IF OBJECT_ID('gold.dim_candidato', 'U') IS NOT NULL DROP TABLE gold.dim_candidato;
IF OBJECT_ID('gold.dim_partido', 'U') IS NOT NULL DROP TABLE gold.dim_partido;
IF OBJECT_ID('gold.dim_localidade', 'U') IS NOT NULL DROP TABLE gold.dim_localidade;

-- Dimensão Partido
CREATE TABLE gold.dim_partido (
    id_partido INT IDENTITY(1,1) PRIMARY KEY,
    nr_partido INT UNIQUE,
    sg_partido VARCHAR(20),
    nm_partido VARCHAR(150)
);

-- Dimensão Candidato
CREATE TABLE gold.dim_candidato (
    id_candidato INT IDENTITY(1,1) PRIMARY KEY,
    nr_candidato INT,
    nm_candidato VARCHAR(200),
    sg_uf VARCHAR(2)
);

-- Dimensão Localidade (Município / Zona / Seção)
CREATE TABLE gold.dim_localidade (
    id_localidade INT IDENTITY(1,1) PRIMARY KEY,
    sg_uf VARCHAR(2),
    cd_municipio INT,
    nm_municipio VARCHAR(150),
    nr_zona INT,
    nr_secao INT
);

-- Tabela de Fatos: Votação por Seção
CREATE TABLE gold.fat_votacao_secao (
    id_fato BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_candidato INT FOREIGN KEY REFERENCES gold.dim_candidato(id_candidato),
    id_partido INT FOREIGN KEY REFERENCES gold.dim_partido(id_partido),
    id_localidade INT FOREIGN KEY REFERENCES gold.dim_localidade(id_localidade),
    qt_votos INT,
    ano_eleicao INT,
    dt_carga DATETIME DEFAULT GETDATE()
);

-- =========================================================================
-- 2. PROCEDURE T-SQL PARA POPULAR AS DIMENSÕES E FATOS
-- =========================================================================

CREATE OR ALTER PROCEDURE gold.sp_transformar_gold
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

            -- -------------------------------------------------------------
            -- PASSO A: Popular Dimensão Localidade
            -- -------------------------------------------------------------
            PRINT '[T-SQL] A popular dim_localidade...';
            INSERT INTO gold.dim_localidade (sg_uf, cd_municipio, nm_municipio, nr_zona, nr_secao)
            SELECT DISTINCT 
                SG_UF,
                CAST(CD_MUNICIPIO AS INT),
                NM_MUNICIPIO,
                CAST(NR_ZONA AS INT),
                CAST(NR_SECAO AS INT)
            FROM stg.stg_votacao_secao;

            -- -------------------------------------------------------------
            -- PASSO B: Popular Dimensão Candidato (Apenas registos válidos de candidatos)
            -- -------------------------------------------------------------
            PRINT '[T-SQL] A popular dim_candidato...';
            INSERT INTO gold.dim_candidato (nr_candidato, nm_candidato, sg_uf)
            SELECT DISTINCT 
                CAST(NR_VOTAVEL AS INT),
                NM_VOTAVEL,
                SG_UF
            FROM stg.stg_votacao_secao
            WHERE SQ_CANDIDATO IS NOT NULL 
              AND CAST(SQ_CANDIDATO AS BIGINT) > 0
              AND NR_VOTAVEL < 90000; -- Ignora votos nulos/brancos (geralmente códigos 95, 96, etc.)

            -- -------------------------------------------------------------
            -- PASSO C: Popular Dimensão Partido (Inferido dos dados)
            -- -------------------------------------------------------------
            PRINT '[T-SQL] A popular dim_partido...';
            INSERT INTO gold.dim_partido (nr_partido, sg_partido, nm_partido)
            SELECT DISTINCT 
                CAST(NR_VOTAVEL AS INT),
                'PARTIDO_' + CAST(NR_VOTAVEL AS VARCHAR), -- Placeholder caso venha agregado por legenda
                NM_VOTAVEL
            FROM stg.stg_votacao_secao
            WHERE SQ_CANDIDATO IS NULL OR CAST(SQ_CANDIDATO AS BIGINT) <= 0;

            -- -------------------------------------------------------------
            -- PASSO D: Carga da Tabela de Fatos
            -- -------------------------------------------------------------
            PRINT '[T-SQL] A popular fat_votacao_secao...';
            INSERT INTO gold.fat_votacao_secao (id_candidato, id_partido, id_localidade, qt_votos, ano_eleicao)
            SELECT 
                c.id_candidato,
                p.id_partido,
                l.id_localidade,
                CAST(s.QT_VOTOS AS INT),
                CAST(s.ANO_ELEICAO AS INT)
            FROM stg.stg_votacao_secao s
            LEFT JOIN gold.dim_candidato c 
                ON c.nr_candidato = CAST(s.NR_VOTAVEL AS INT) AND c.sg_uf = s.SG_UF
            LEFT JOIN gold.dim_partido p 
                ON p.nr_partido = CAST(s.NR_VOTAVEL AS INT)
            INNER JOIN gold.dim_localidade l 
                ON l.sg_uf = s.SG_UF 
               AND l.cd_municipio = CAST(s.CD_MUNICIPIO AS INT) 
               AND l.nr_zona = CAST(s.NR_ZONA AS INT) 
               AND l.nr_secao = CAST(s.NR_SECAO AS INT);

        COMMIT TRANSACTION;
        PRINT '[SUCESSO] Camada Gold totalmente transformada e populada!';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;

EXEC gold.sp_transformar_gold;
