/* ============================================================
   05_views_bi.sql
   Views de consumo do dashboard (Power BI). Não alteram o modelo dw:
   só juntam rótulos e pré-calculam classificações por seção que seriam
   caras demais em DAX (percentis sobre ~50 mil seções, linha a linha).
   As taxas continuam sendo calculadas no BI como razão das somas (Termo, 3.1).
   ============================================================ */

/* ---------- Zona com rótulo da capital ---------- */
CREATE OR ALTER VIEW dw.VW_ZONA_BI AS
SELECT z.sk_zona,
       z.sk_municipio,
       z.ano,
       z.nr_zona,
       m.sg_uf,
       m.nm_municipio,
       CONCAT(m.nm_municipio, N' · Zona ', z.nr_zona) AS ds_zona,
       z.distancia_centro_km,
       z.fl_zona_periferica,
       CASE z.fl_zona_periferica WHEN 1 THEN N'Periférica'
                                 WHEN 0 THEN N'Não periférica'
                                 ELSE N'Sem coordenadas' END AS ds_periferia
FROM dw.DIM_ZONA z
JOIN dw.DIM_MUNICIPIO m ON m.sk_municipio = z.sk_municipio;
GO

/* ---------- Seção com perfil de escolaridade (K11) e quartil de tamanho (K10) ----------
   - pct_sem_medio (K11a) e pct_superior (K11b): denominador = aptos com escolaridade
     informada (Termo, definições operacionais).
   - pr_sem_medio / pr_superior: posição percentual da seção entre as seções das 4 capitais
     (PERCENT_RANK). "Baixa/alta escolaridade" = posição >= 0,75 (P75), ajustável no BI.
   - quartil_aptos (K10): quartil de QT_APTOS da seção dentro de cada capital, medido no
     1º turno para Presidente (todos os eleitores votam para esse cargo). */
CREATE OR ALTER VIEW dw.VW_SECAO_BI AS
WITH esc AS (
    SELECT f.sk_secao,
           SUM(CASE WHEN p.fl_escolaridade_informada = 1 THEN f.qt_eleitores_perfil ELSE 0 END) AS eleitores_informados,
           SUM(CASE WHEN p.fl_sem_medio_completo = 1 THEN f.qt_eleitores_perfil ELSE 0 END)     AS eleitores_sem_medio,
           SUM(CASE WHEN p.fl_superior_completo = 1 THEN f.qt_eleitores_perfil ELSE 0 END)      AS eleitores_superior
    FROM dw.FATO_PERFIL_ELEITORADO_SECAO f
    JOIN dw.DIM_PERFIL p ON p.sk_perfil = f.sk_perfil
    GROUP BY f.sk_secao
),
k11 AS (
    SELECT sk_secao,
           CAST(eleitores_sem_medio AS FLOAT) / NULLIF(eleitores_informados, 0) AS pct_sem_medio,
           CAST(eleitores_superior AS FLOAT) / NULLIF(eleitores_informados, 0)  AS pct_superior
    FROM esc
),
tam AS (
    SELECT f.sk_secao, f.qt_aptos
    FROM dw.FATO_DETALHE_SECAO f
    JOIN dw.DIM_ELEICAO e ON e.sk_eleicao = f.sk_eleicao AND e.turno = 1
    JOIN dw.DIM_CARGO   c ON c.sk_cargo = f.sk_cargo AND c.cd_cargo = 1
),
base AS (
    SELECT s.sk_secao, s.sk_zona, z.sk_municipio, m.sg_uf, m.nm_municipio, z.nr_zona, s.nr_secao,
           s.nr_local_votacao, s.nm_local_votacao, s.nm_bairro, s.latitude, s.longitude,
           k.pct_sem_medio, k.pct_superior, t.qt_aptos
    FROM dw.DIM_SECAO s
    JOIN dw.DIM_ZONA z      ON z.sk_zona = s.sk_zona
    JOIN dw.DIM_MUNICIPIO m ON m.sk_municipio = z.sk_municipio
    LEFT JOIN k11 k ON k.sk_secao = s.sk_secao
    LEFT JOIN tam t ON t.sk_secao = s.sk_secao
)
SELECT sk_secao, sk_zona, sk_municipio, sg_uf, nm_municipio, nr_zona, nr_secao,
       CONCAT(nm_municipio, N' · Z', nr_zona, N' · S', nr_secao) AS ds_secao,
       nr_local_votacao, nm_local_votacao, nm_bairro, latitude, longitude,
       pct_sem_medio,
       pct_superior,
       -- PERCENT_RANK só entre seções com escolaridade conhecida (as demais ficam NULL)
       CASE WHEN pct_sem_medio IS NOT NULL THEN
            PERCENT_RANK() OVER (PARTITION BY CASE WHEN pct_sem_medio IS NULL THEN 0 ELSE 1 END
                                 ORDER BY pct_sem_medio) END AS pr_sem_medio,
       CASE WHEN pct_superior IS NOT NULL THEN
            PERCENT_RANK() OVER (PARTITION BY CASE WHEN pct_superior IS NULL THEN 0 ELSE 1 END
                                 ORDER BY pct_superior) END AS pr_superior,
       qt_aptos AS qt_aptos_referencia,
       CASE WHEN qt_aptos > 0 THEN
            NTILE(4) OVER (PARTITION BY sk_municipio, CASE WHEN qt_aptos > 0 THEN 1 ELSE 0 END
                           ORDER BY qt_aptos) END AS quartil_aptos
FROM base;
GO
