/* ============================================================
   conferencias.sql  (fica em docs/, NÃO é executado pelo pipeline)
   Rode no DBeaver depois de 02, 03 e 04. Cada bloco diz o que esperar.
   ============================================================ */

-- 1. Repetição por causa de _BR/_BRASIL: linhas brutas x linhas após DISTINCT.
--    Se forem diferentes, o DISTINCT da 02 removeu duplicatas.
SELECT 'detalhe_votacao_secao' AS base,
       (SELECT COUNT(*) FROM stg.stg_detalhe_votacao_secao) AS brutas,
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg.stg_detalhe_votacao_secao) x) AS distintas
UNION ALL
SELECT 'perfil_comparecimento_abstencao',
       (SELECT COUNT(*) FROM stg.stg_perfil_comparecimento_abstencao),
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg.stg_perfil_comparecimento_abstencao) x)
UNION ALL
SELECT 'votacao_candidato_munzona',
       (SELECT COUNT(*) FROM stg.stg_votacao_candidato_munzona),
       (SELECT COUNT(*) FROM (SELECT DISTINCT * FROM stg.stg_votacao_candidato_munzona) x);

-- 2. Detalhe por seção: deve retornar ZERO linhas (uma linha por seção x turno x cargo).
--    Se retornar linhas, veja ds_origem_voto: pode haver linhas separadas por origem do voto.
SELECT ano, turno, cd_municipio, nr_zona, nr_secao, cd_cargo, COUNT(*) AS linhas,
       MIN(ds_origem_voto) AS origem_min, MAX(ds_origem_voto) AS origem_max
FROM stg.detalhe_secao_limpa
GROUP BY ano, turno, cd_municipio, nr_zona, nr_secao, cd_cargo
HAVING COUNT(*) > 1;

-- 3. Detalhe por zona e voto em trânsito: se houver S e N, confira se QT_APTOS não está repetido.
SELECT st_voto_em_transito, COUNT(*) AS linhas, SUM(qt_aptos) AS aptos, SUM(qt_comparecimento) AS comparecimento
FROM stg.detalhe_zona_limpa
GROUP BY st_voto_em_transito;

-- 4. Códigos de branco e nulo na votação por seção: esperado 95 = branco e 96 = nulo.
SELECT nr_votavel, nm_votavel, tipo_voto, SUM(qt_votos) AS votos
FROM stg.votacao_secao_limpa
WHERE nr_votavel IN (95, 96) OR nm_votavel LIKE N'Voto%'
GROUP BY nr_votavel, nm_votavel, tipo_voto;

-- 5. Zona x seção: totais devem bater (diferenças pequenas apontam para a coluna de nulos).
SELECT z.cargo, z.aptos_zona, s.aptos_secao, z.nulos_zona, s.nulos_secao
FROM (SELECT c.ds_cargo AS cargo, SUM(f.qt_aptos) AS aptos_zona, SUM(f.qt_votos_nulos) AS nulos_zona
      FROM dw.FATO_DETALHE_ZONA f JOIN dw.DIM_CARGO c ON c.sk_cargo = f.sk_cargo
      JOIN dw.DIM_ELEICAO e ON e.sk_eleicao = f.sk_eleicao AND e.turno = 1
      GROUP BY c.ds_cargo) z
JOIN (SELECT c.ds_cargo AS cargo, SUM(f.qt_aptos) AS aptos_secao, SUM(f.qt_votos_nulos) AS nulos_secao
      FROM dw.FATO_DETALHE_SECAO f JOIN dw.DIM_CARGO c ON c.sk_cargo = f.sk_cargo
      JOIN dw.DIM_ELEICAO e ON e.sk_eleicao = f.sk_eleicao AND e.turno = 1
      GROUP BY c.ds_cargo) s ON s.cargo = z.cargo;

-- 6. Contagem de linhas por tabela do dw.
SELECT t.name AS tabela, SUM(p.rows) AS linhas
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id AND s.name = 'dw'
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0, 1)
GROUP BY t.name ORDER BY t.name;

-- 7. Abstenção por capital (1º turno, Presidente): sanidade geral (ordem de grandeza ~15 a 25%).
SELECT m.nm_municipio,
       SUM(f.qt_abstencoes) * 100.0 / NULLIF(SUM(f.qt_aptos), 0) AS taxa_abstencao_pct
FROM dw.FATO_DETALHE_ZONA f
JOIN dw.DIM_MUNICIPIO m ON m.sk_municipio = f.sk_municipio
JOIN dw.DIM_CARGO c ON c.sk_cargo = f.sk_cargo AND c.cd_cargo = 1
JOIN dw.DIM_ELEICAO e ON e.sk_eleicao = f.sk_eleicao AND e.turno = 1
GROUP BY m.nm_municipio;
