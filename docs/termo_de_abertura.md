# Termo de Abertura do Projeto — Dados Abertos de Votação do TSE

Definição do Cliente:

Coordenação de Estratégia de um partido político de alcance nacional. O cliente quer analisar o comportamento do eleitorado nas Eleições Gerais de 2022 nas capitais do Sudeste (São Paulo, Rio de Janeiro, Belo Horizonte e Vitória) para planejar a alocação de recursos partidários (Fundo Partidário e FEFC), direcionar as equipes de marketing e otimizar campanhas locais nas próximas eleições.

### 1.1 Escopo resumido

| Dimensão | Definição |
| --- | --- |
| Eleições | Gerais 2022 (1º e 2º turnos) |
| Territórios | Capitais SP, RJ, BH e Vitória. Grãos de análise: município, zona eleitoral e seção eleitoral |
| Cargos | Presidente, Governador, Senador, Deputado Federal e Deputado Estadual |
| Entregas | Engenharia de dados (pipeline e DW), ciência de dados (previsões) e BI (dashboard) |

## 2. Justificativa do Projeto

As Eleições Gerais de 2022 renovam os mesmos cargos: Presidente, Governadores, Senadores, Deputados Federais e Deputados Estaduais. O tema é relevante porque a abstenção é um problema crescente de mobilização: foi de 20,95% no 1º turno de 2022, o maior índice desde 1998, e a imprensa, com base em dados do TSE, reporta 21,08% no 1º turno de 2026.

A escolha pelas capitais de São Paulo, Rio de Janeiro, Belo Horizonte e Vitória se deve ao fato de serem as principais metrópoles do Sudeste, a região mais populosa do país, com eleitorado diversificado em idade, escolaridade e território. É nesse tipo de cenário que as decisões de campanha (tráfego pago, equipes de rua, comícios, propaganda de TV e rádio, pedidos de desmembramento de seções) mais dependem de evidência por zona e por seção. O projeto entrega ao cliente respostas para 10 perguntas estratégicas, um catálogo de KPIs padronizados, previsões por zona e um dashboard para apoiar a distribuição de recursos.

## 3. Bases de Dados Selecionadas

Todas as URLs começam com `https://cdn.tse.jus.br/estatistica/sead/odsele/` (chamada de `BASE` nas tabelas). Portal: https://dadosabertos.tse.jus.br/

### Bases do núcleo

| Nº | Descrição | Grão | Arquivo 2022 (status) | Atualização pelo produtor | Perguntas |
| --- | --- | --- | --- | --- | --- |
| 1 | ES: votação por seção eleitoral | seção × cargo × votável | `BASE/votacao_secao/votacao_secao_2022_ES.zip` (Listada) | Ao final de cada turno | 2, 6, 8, 9 |
| 2 | MG: votação por seção eleitoral | seção × cargo × votável | `BASE/votacao_secao/votacao_secao_2022_MG.zip` (Listada) | Ao final de cada turno | 2, 6, 8, 9 |
| 3 | RJ: votação por seção eleitoral | seção × cargo × votável | `BASE/votacao_secao/votacao_secao_2022_RJ.zip` (Listada) | Ao final de cada turno | 2, 6, 8, 9 |
| 4 | SP: votação por seção eleitoral | seção × cargo × votável | `BASE/votacao_secao/votacao_secao_2022_SP.zip` (Validada) | Ao final de cada turno | 2, 6, 8, 9 |
| 5 | Votação em partido por município e zona | zona × partido | `BASE/votacao_partido_munzona/votacao_partido_munzona_2022.zip` (Validada) | Frequente: muda quando mudam situações de registro de candidatura por decisão judicial | 3, 8 |
| 6 | Votação nominal por município e zona | zona × candidato | `BASE/votacao_candidato_munzona/votacao_candidato_munzona_2022.zip` (Validada) | Frequente (mesmo motivo da base 5) | 3, 7 |
| 7 | Detalhe da apuração por município e zona | zona × cargo | `BASE/detalhe_votacao_munzona/detalhe_votacao_munzona_2022.zip` (Validada) | Frequente (mesmo motivo da base 5) | 1, 5, 10 |
| 8 | Detalhe da apuração por seção eleitoral | seção × cargo | `BASE/detalhe_votacao_secao/detalhe_votacao_secao_2022.zip` (Validada) | Ao final de cada turno | 2, 6, 9 |
| 9 | Presidente: votação por seção eleitoral | seção × candidato | `BASE/votacao_secao/votacao_secao_2022_BR.zip` (Validada) | Ao final de cada turno | 7, 10 |

Observação: no portal, o dataset "Resultados - 2026" informa frequência de atualização diária, enquanto cada arquivo de votação por seção informa "atualizado ao final de cada turno". Os arquivos 5, 6 e 7 são do tipo "Todas as UFs" e cobrem os dois turnos.

### Bases complementares

| Nº | Descrição | Grão | 2022 | Atualização pelo produtor | Perguntas |
| --- | --- | --- | --- | --- | --- |
| 10 | Perfil do eleitorado por seção eleitoral (gênero, faixa etária, escolaridade, biometria, deficiência) | seção × perfil | `BASE/perfil_eleitor_secao/perfil_eleitor_secao_2022_{UF}.zip` (Validada para SP) | Publicado antes da eleição (2022: 15/07/2022;  | 2, 6, 9 e features |
| 11 | Perfil do comparecimento e abstenção | zona × perfil | `BASE/perfil_comparecimento_abstencao/perfil_comparecimento_abstencao_2022.zip` (Validada; todas as UFs) | "A cada eleição". Em 2022 o dataset foi criado em 20/10/2022 | 1, 3, 4 |
| 12 | Eleitorado por local de votação | local de votação | Dataset "Eleitorado - 2022" (Listada; URL a confirmar) | Publicado antes da eleição | 9 e mapas |
| 13 | IBGE: API de Localidades e malha municipal | município | https://servicodados.ibge.gov.br/api/v1/localidades/municipios | Anual | mapeamento TSE ↔ IBGE |
| 14 | Candidatos (consulta_cand), opcional | candidato | Dataset "Candidatos - 2022" | Contínua durante o registro de candidaturas | dimensão de candidato |
| 15 | Divulgação de resultados em JSON (`resultados.tse.jus.br`), opcional | seção, zona, município |  |  |  |

Nota sobre a base 12: o projeto precisa de coordenadas dos locais de votação para definir zona periférica e mapas. Confirme na primeira carga se o arquivo traz latitude e longitude em cada ano.

### 4.3 Regra de filtro por capital

| Capital | UF | Código TSE do município | Código IBGE | Arquivo de seção |
| --- | --- | --- | --- | --- |
| São Paulo | SP | 71072 | 3550308 | votacao_secao_{ano}_SP |
| Rio de Janeiro | RJ | 60011 | 3304557 | votacao_secao_{ano}_RJ |
| Belo Horizonte | MG | 41238 | 3106200 | votacao_secao_{ano}_MG |
| Vitória | ES | 57053 | 3205309 | votacao_secao_{ano}_ES |

### 4.5 Campos-chave esperados

Os nomes abaixo vêm do padrão dos arquivos do TSE e devem ser conferidos no leiaute que acompanha cada ZIP antes de fixar o DDL.

| Base | Campos principais |
| --- | --- |
| Votação por seção (1 a 4 e 9) | ANO_ELEICAO, NR_TURNO, SG_UF, CD_MUNICIPIO, NM_MUNICIPIO, NR_ZONA, NR_SECAO, CD_CARGO, DS_CARGO, NR_VOTAVEL, NM_VOTAVEL, QT_VOTOS, NR_LOCAL_VOTACAO |
| Detalhe da apuração (7 e 8) | chaves geográficas e de cargo, QT_APTOS, QT_COMPARECIMENTO, QT_ABSTENCOES, QT_VOTOS_NOMINAIS, QT_VOTOS_BRANCOS, QT_VOTOS_NULOS, QT_VOTOS_LEGENDA |
| Votação em partido por zona (5) | SG_PARTIDO, NR_PARTIDO, QT_VOTOS_NOMINAIS, QT_VOTOS_LEGENDA, chaves de zona e cargo |
| Votação nominal por zona (6) | SQ_CANDIDATO, NR_CANDIDATO, NM_URNA_CANDIDATO, SG_PARTIDO, QT_VOTOS_NOMINAIS, situação de totalização |
| Perfil do eleitorado por seção (10) | chaves de seção, DS_GENERO, DS_FAIXA_ETARIA, DS_GRAU_ESCOLARIDADE, QT_ELEITORES_PERFIL |
| Perfil do comparecimento (11) | chaves de zona e turno, gênero, faixa etária, escolaridade, eleitores do perfil, comparecimento e abstenção do perfil |

## 5. Perguntas Estratégicas de Negócio

### As 10 perguntas

| Nº | Pergunta de negócio estratégica | Decisão que ela apoia |
| --- | --- | --- |
| 1 | Quais zonas eleitorais das 4 capitais concentram a maior taxa de abstenção entre jovens de 18 a 24 anos (2022)? | Direcionar o orçamento de tráfego pago (Instagram e TikTok) para mobilização jovem especificamente nessas zonas. |
| 2 | Entre as seções com predominância de baixa escolaridade (sem Ensino Médio completo), quais têm as maiores taxas de votos brancos e nulos? | Enviar equipes de rua a essas regiões com cartilhas simples sobre como votar no número do partido. |
| 3 | Em quais zonas a proporção de mulheres entre os eleitores que compareceram é alta, mas a votação do partido-alvo é baixa? | Priorizar o lançamento de candidaturas femininas e propostas voltadas a esse público nessas zonas. |
| 4 | Em quais zonas das 4 capitais o comparecimento de eleitores de 60 a 69 anos (voto obrigatório) e de 70 anos ou mais (voto facultativo) foi menor? | Planejar logística de acessibilidade e comunicação em rádios locais para recuperar esse eleitorado. |
| 5 | Quais são as 20 zonas das 4 capitais com maior número de eleitores aptos e abstenção geral acima de 20%? | Concentrar os maiores eventos físicos (comícios e carreatas) nessas áreas, que têm o maior "estoque" de votos não utilizados. |
| 6 | Nas seções com alta proporção de eleitores com ensino superior, qual capital apresenta a maior rejeição (votos brancos e nulos)? | Ajustar o tom do discurso (mais técnico e econômico) na propaganda de TV e rádio dessa capital. |
| 7 | Em quais zonas das capitais foi menor a diferença percentual de votos entre os candidatos do 2º turno presidencial (2022)? | Classificar essas áreas como "Zonas de Disputa (Swing Zones)" e concentrar a verba de campanha corpo a corpo nelas. |
| 8 | Quais seções tiveram a maior proporção de votos de legenda nas eleições de deputado federal e estadual? | Mapear essas regiões como "Bases Consolidadas" e reduzir o custo de marketing nelas, focando na manutenção. |
| 9 | Como o tamanho da seção (quantidade de aptos) se associa à taxa de abstenção nas zonas periféricas de São Paulo e do Rio de Janeiro? | Solicitar formalmente ao TRE o desmembramento de seções superlotadas onde o partido tem forte base de apoio. |
| 10 | Qual das 4 capitais apresenta a melhor relação entre votos válidos e abstenções no público geral? | Definir a distribuição macro dos recursos partidários, priorizando a capital com o eleitorado mais engajado. |
|  |  |  |

### 5 Definições operacionais

Cada termo ambíguo do Termo v1.0 recebe uma definição e um parâmetro ajustável, para que o resultado seja reproduzível.

| Termo | Definição operacional | Parâmetro ajustável |
| --- | --- | --- |
| Jovem | 18 a 24 anos (faixas 18, 19, 20 e 21–24 do TSE; conferir os rótulos) | n/a |
| Idoso | 60–69 anos (voto obrigatório) e 70 anos ou mais (facultativo) | n/a |
| Baixa escolaridade (seção) | % de aptos sem Ensino Médio completo (analfabeto, lê e escreve, fundamental incompleto ou completo, médio incompleto), excluindo "não informado" do denominador, maior ou igual ao P75 das seções das 4 capitais | Percentil (padrão P75) |
| Alta escolaridade (seção) | % de aptos com ensino superior completo, maior ou igual ao P75 | Percentil; incluir ou não superior incompleto |
| Zona periférica (pergunta 9) | Zona cujo centro (média das coordenadas dos seus locais de votação) está no quartil mais distante do centro da capital. Definição alternativa por bairros, a validar com o professor | Quartil de distância |
| Votos válidos | Votos nominais + votos de legenda (exclui brancos e nulos) | n/a |
| Votos desperdiçados | Votos brancos + votos nulos | n/a |
| Voto de legenda | Voto no número do partido (2 dígitos) nas eleições proporcionais | n/a |
| Proporção alta de mulheres (pergunta 3) | K3 maior ou igual ao P75 das zonas da capital, e votação do partido-alvo menor ou igual ao P25 no cargo de referência | Percentis |
| Zona de disputa | Margem entre os dois candidatos do 2º turno menor que 5 p.p. | 3, 5 ou 10 p.p. |
| Turno e cargo de referência | Abstenção e comparecimento: 1º turno (2º turno quando disponível). Votação do partido-alvo: Deputado Federal, com sensibilidade em Deputado Estadual. Disputa: Presidente, 2º turno | Turno e cargo |
| Partido-alvo | Partido ou federação do cliente, definido na Sprint 0 e gravado em `dw.DIM_AGREMIACAO.fl_cliente` | Linha de configuração |

### 5.3 Perguntas preditivas (camada de ciência de dados opicional)

| Nº | Pergunta preditiva | Perguntas ligadas | Decisão | Critério de sucesso |
| --- | --- | --- | --- | --- |
| P1 | Qual será a abstenção por zona em 2026 (total e, quando houver dados, por 18–24, 60–69 e 70+), usando apenas o perfil do eleitorado de 2026 e o comportamento observado em 2022? | 1, 4, 5 | Priorizar zonas antes de uma próxima eleição | Reduzir em pelo menos 10% o MAE da linha de base "2026 = 2022", medido no resultado real do 1º turno de 2026 |
| P2 | Quais zonas terão margem menor que 5 p.p. no 2º turno presidencial de 25/10/2026, dado o 1º turno de 2026 e a relação entre 1º e 2º turno observada em 2022? | 7 | Classificar swing zones | Meta inicial: AUC ≥ 0,75 e precisão nas 20 primeiras zonas melhor que a linha de base. Previsão congelada no GitHub antes de 25/10 (experimento pré-registrado) |
| P3 | Que grupos de zonas e seções compartilham perfil demográfico e padrão de voto de legenda e do partido-alvo? | 3, 8, 10 | Criar personas territoriais para marketing | Silhueta ≥ 0,25 e leitura de negócio validada com o professor |
| P4 | Quanto da taxa de brancos e nulos é explicada pela escolaridade, controlando por zona? | 2, 6 | Ajustar o tom da comunicação | Coeficientes com o mesmo sinal e magnitude comparável em 2022 e 2026 |

### Rastreabilidade (pergunta → dados → KPI → modelo → visual)

| Pergunta | Bases | Fatos (seção 8) | KPIs | Modelo | Página do BI |
| --- | --- | --- | --- | --- | --- |
| 1 | 11, 7 | FATO_PERFIL_COMPARECIMENTO_ZONA, FATO_DETALHE_ZONA | K1, K6 | P1 | Abstenção e perfil |
| 2 | 8, 10 | FATO_DETALHE_SECAO, FATO_PERFIL_ELEITORADO_SECAO | K2, K2b, K11 | P4 | Rejeição |
| 3 | 11, 5 | FATO_PERFIL_COMPARECIMENTO_ZONA, FATO_VOTACAO_PARTIDO_ZONA | K3, K5 | P3 | Gênero e partido-alvo |
| 4 | 11 | FATO_PERFIL_COMPARECIMENTO_ZONA | K7 | P1 | Abstenção e perfil |
| 5 | 7, 10 | FATO_DETALHE_ZONA | K1, K6 | P1 | Abstenção e perfil |
| 6 | 8, 10 | FATO_DETALHE_SECAO, FATO_PERFIL_ELEITORADO_SECAO | K2b, K11 | P4 | Rejeição |
| 7 | 6, 9 | FATO_VOTACAO_CANDIDATO_ZONA | K4 | P2 | Disputa |
| 8 | 1 a 4, 5 | FATO_VOTACAO_SECAO_PARTIDO, FATO_VOTACAO_PARTIDO_ZONA | K5 | P3 | Bases consolidadas |
| 9 | 8, 10, 12 | FATO_DETALHE_SECAO, DIM_SECAO | K1, K10 | P1 | Logística de seções |
| 10 | 7, 8 | FATO_DETALHE_ZONA, FATO_DETALHE_SECAO | K8, K9 | P3 | Visão executiva |

## 6. Catálogo de KPIs

| Nº | KPI | Definição / Fórmula | Fonte e grão | Perguntas |
| --- | --- | --- | --- | --- |
| K1 | Taxa de Abstenção Segmentada (TAS) | (Abstenções do perfil X ÷ Eleitores aptos do perfil X) × 100, usando a abstenção informada pelo TSE (aptos − comparecimento inclui seções não instaladas). Sem perfil, vale para o total da zona ou da seção | Base 11 (zona × perfil), 2022; bases 7 e 8 para o total | 1, 4, 5, 9 |
| K2 | Volume de Votos Desperdiçados (VVD) | Σ (votos brancos + votos nulos) por seção ou zona | Bases 7 e 8 | 2, 6 |
| K2b | Taxa de brancos e nulos | VVD ÷ comparecimento × 100 | Bases 7 e 8 | 2, 6 |
| K3 | Proporção de Eleitorado Feminino Ativo | (Mulheres que compareceram ÷ total de eleitores que compareceram na zona) × 100 | Base 11 (zona) | 3 |
| K4 | Margem de Competitividade Regional | |% votos do 1º colocado − % votos do 2º colocado| em pontos percentuais, sobre os votos válidos do 2º turno presidencial na zona. Quanto menor, mais acirrada | Base 6 (zona × candidato) | 7 |
| K5 | Índice de Voto Ideológico (Legenda) | (Votos de legenda do partido ÷ votos válidos do partido) × 100, em que votos válidos do partido = nominais + legenda. Seção: partido derivado dos 2 primeiros dígitos do número votável. Zona: base 5 | Bases 1 a 4 e 5 | 8 (e 3) |
| K6 | Densidade de Ociosidade Eleitoral | Abstenções em número absoluto por zona, com ranking | Base 7 | 1, 5 |
| K7 | Taxa de Comparecimento 60+ | (Eleitores 60+ que votaram ÷ aptos 60+) × 100, com cortes 60–69 e 70+ | Base 11 | 4 |
| K8 | Engajamento Global da Capital | (Total de votos válidos ÷ eleitores aptos da capital) × 100 | Bases 7 e 8 | 10 |
| K9 | Razão Válidos/Abstenção (novo) | Votos válidos ÷ abstenções, por capital | Bases 7 e 8 | 10 |
| K10 | Abstenção por tamanho de seção (novo) | Taxa de abstenção por quartil de QT_APTOS da seção, dentro de cada capital | Bases 8, 10 e 12 | 9 |
| K11 | Perfil de escolaridade da seção (novo) | K11a: % de aptos sem Ensino Médio completo. K11b: % de aptos com superior completo | Base 10 | 2, 6 |
| K12 | MAE da previsão de abstenção | Média de |abstenção real − prevista| por zona, em p.p. | Modelo P1 | P1 |
| K13 | AUC e precisão nas 20 primeiras zonas | AUC da classificação de zonas de disputa e proporção de acertos entre as 20 zonas de maior risco | Modelo P2 | P2 |
| K14 | Silhueta dos grupos | Coeficiente de silhueta médio da segmentação | Modelo P3 | P3 |
|  |  |  |  |  |

### 6.1 Regras de cálculo

- Sempre explicitar o denominador (aptos, comparecimento ou votos válidos).
- Votos válidos = nominais + legenda. Brancos e nulos ficam fora.
- Excluir das taxas seções com zero aptos e seções não instaladas, registrando a exclusão.
- Taxas são comparadas em pontos percentuais (p.p.). Volumes, em variação percentual.
- Variações 2022 → 2026 só valem entre zonas marcadas como comparáveis na tabela-ponte de zonas.
- Comparecimento e abstenção usam o 1º turno por padrão; o 2º turno entra quando o arquivo for atualizado.

## 8. Modelo dimensional (star schema)

### Decisões de modelagem

- **Grãos:** `FATO_*_SECAO` para análises descritivas e `FATO_*_ZONA` para previsões.
- **Zona estável:** `DIM_ZONA` tem uma linha por ano, e `sk_zona_estavel` liga a mesma zona entre anos. A tabela-ponte `dw.BRIDGE_ZONA` guarda o percentual de locais de votação em comum entre 2022 e 2026. Zona com 80% ou mais de locais em comum é tratada como comparável.
- **Chaves:** surrogate keys inteiras nas dimensões e chaves naturais únicas para garantir a idempotência.
- **Partido do voto:** nas eleições proporcionais, o número do candidato começa com o número do partido. O partido é derivado dos 2 primeiros dígitos de `NR_VOTAVEL`; voto de legenda é o voto com número de 2 dígitos. Validar essa regra no leiaute.
- **Histórico:** `DIM_AGREMIACAO` usa SCD tipo 2 (números de partido e federações mudam entre eleições). As demais dimensões usam SCD tipo 1 por ano.
- **Dado sensível:** não carregar CPF nem contatos de candidatos.

### Diagrama estrela

```
                    DIM_ELEICAO        DIM_CARGO
                          \               /
   DIM_PERFIL ─────  FATO_DETALHE_SECAO ───── DIM_SECAO ── DIM_ZONA ── DIM_MUNICIPIO
                          /               \                    │
          DIM_AGREMIACAO ── FATO_VOTACAO_SECAO_PARTIDO          └── BRIDGE_ZONA (2022)

   Fatos de zona (mesmas dimensões): FATO_DETALHE_ZONA · FATO_VOTACAO_PARTIDO_ZONA
   · FATO_VOTACAO_CANDIDATO_ZONA (+ DIM_CANDIDATO) · FATO_PERFIL_COMPARECIMENTO_ZONA (+ DIM_PERFIL)
   Fato de perfil por seção: FATO_PERFIL_ELEITORADO_SECAO (+ DIM_PERFIL)
 
```

### Dimensões

| Dimensão | Chave | Atributos principais | Observações |
| --- | --- | --- | --- |
| `DIM_ELEICAO` | sk_eleicao | ano, turno, data, tipo | 4 linhas iniciais: 2022 , 1º e 2º turnos |
| `DIM_CARGO` | sk_cargo | código, descrição, flags majoritário e proporcional | 5 cargos |
| `DIM_MUNICIPIO` | sk_municipio | código TSE, código IBGE, nome, UF, flag de capital | 4 linhas |
| `DIM_ZONA` | sk_zona | ano, município, número da zona, `sk_zona_estavel`, distância ao centro (km), flag de zona periférica | Uma linha por ano |
| `DIM_SECAO` | sk_secao | zona, número da seção, local de votação, endereço, latitude e longitude (se existirem) | Uma linha por ano |
| `DIM_PERFIL` | sk_perfil | gênero, faixa etária, escolaridade e flags: jovem 18–24, 60–69, 70+, voto facultativo, sem médio completo, superior completo | Combinação gênero × faixa × escolaridade (cerca de algumas centenas de linhas) |
| `DIM_AGREMIACAO` | sk_agremiacao | número, sigla, nome, federação, `fl_cliente`, vigência | SCD tipo 2 |
| `DIM_CANDIDATO` | sk_candidato | `SQ_CANDIDATO`, número, nome de urna, partido, cargo, situação | Sem CPF |
| `DIM_TIPO_VOTO` | sk_tipo_voto | nominal, legenda, branco, nulo | Apoio ao detalhamento |

### Fatos

| Fato | Grão | Medidas | Fonte | KPIs |
| --- | --- | --- | --- | --- |
| `FATO_DETALHE_SECAO` | seção × eleição × cargo | aptos, comparecimento, abstenções, votos nominais, legenda, brancos, nulos | Base 8 | K1, K2, K2b, K8, K9, K10 |
| `FATO_DETALHE_ZONA` | zona × eleição × cargo | as mesmas medidas | Base 7 | K1, K6, K8, K9 |
| `FATO_VOTACAO_SECAO_PARTIDO` | seção × eleição × cargo × agremiação × tipo de voto | votos | Bases 1 a 4 e 9 | K5 |
| `FATO_VOTACAO_PARTIDO_ZONA` | zona × eleição × cargo × agremiação | votos nominais, votos de legenda | Base 5 | K5 |
| `FATO_VOTACAO_CANDIDATO_ZONA` | zona × eleição × cargo × candidato | votos nominais, situação | Base 6 | K4 |
| `FATO_PERFIL_ELEITORADO_SECAO` | seção × eleição × perfil | eleitores do perfil, com biometria, com deficiência | Base 10 | K10, K11 |
| `FATO_PERFIL_COMPARECIMENTO_ZONA` | zona × eleição × turno × perfil | eleitores do perfil, comparecimento, abstenção | Base 11 | K1, K3, K7 |
| `FATO_APURACAO_SNAPSHOT` (opcional) | abrangência × cargo × candidato × instante | votos, % de seções apuradas | Base 15 | qualidade speed × batch |

### Matriz de barramento

| Fato | Eleição | Cargo | Município | Zona | Seção | Perfil | Agremiação | Candidato |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FATO_DETALHE_SECAO | X | X | X | X | X |  |  |  |
| FATO_DETALHE_ZONA | X | X | X | X |  |  |  |  |
| FATO_VOTACAO_SECAO_PARTIDO | X | X | X | X | X |  | X |  |
| FATO_VOTACAO_PARTIDO_ZONA | X | X | X | X |  |  | X |  |
| FATO_VOTACAO_CANDIDATO_ZONA | X | X | X | X |  |  | X | X |
| FATO_PERFIL_ELEITORADO_SECAO | X |  | X | X | X | X |  |  |
| FATO_PERFIL_COMPARECIMENTO_ZONA | X |  | X | X |  | X |  |  |

# Explicação do Modelo Dimensional

Projeto TSE 2022: capitais do Sudeste (São Paulo, Rio de Janeiro, Belo Horizonte e Vitória)

## 1. Visão geral

O modelo é um *star schema* (esquema estrela): tabelas fato no centro, com os números a analisar, e dimensões ao redor, com os critérios pelos quais o cliente quer cortar esses números (onde, quando, qual cargo, qual perfil de eleitor, qual partido). Escolhemos a estrela porque as 10 perguntas do cliente são todas do mesmo tipo: "quanto de X, por Y, em quais zonas ou seções". Esse formato torna as consultas simples, rápidas e fáceis de ligar ao dashboard.

O modelo tem sete tabelas fato. Isso não é excesso: as fontes do TSE têm grãos diferentes (seção, zona, perfil, candidato) e misturar grãos numa única tabela geraria somas duplicadas. As fatos compartilham as mesmas dimensões (dimensões conformadas), o que permite comparar resultados entre elas. A fato âncora do projeto é a **FATO_DETALHE_SECAO**, porque é a que sustenta os KPIs centrais de abstenção, rejeição e engajamento (K1, K2, K2b, K8, K9, K10) no menor grão disponível.

## 2. Grão das tabelas fato e por que foi escolhido

O grão define o que representa uma linha. Em todas as fatos, escolhemos o **menor nível de detalhe que a fonte oferece e que as perguntas exigem**. É sempre possível somar para cima (seção para zona, zona para município, município para capital), mas é impossível desagregar para baixo. Por isso não pré-agregamos nada.

| Fato                            | Grão (uma linha = ...)                              | Por que esse grão                                                                                                                                                                                                |
| ------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FATO_DETALHE_SECAO (âncora)     | seção × eleição × cargo                             | É o menor grão da apuração (base 8). Responde às perguntas 2, 6, 9 e 10, que dependem de características da seção (escolaridade, tamanho). A soma por zona ou capital é feita no BI.                             |
| FATO_DETALHE_ZONA               | zona × eleição × cargo                              | Base 7, publicada por zona. Atende às perguntas 1, 5 e 10 e serve de entrada para as previsões, que operam por zona. Também serve de conferência: sua soma por zona deve bater com a soma de FATO_DETALHE_SECAO. |
| FATO_VOTACAO_SECAO_PARTIDO      | seção × eleição × cargo × agremiação × tipo de voto | Bases 1 a 4 e 9. É preciso chegar ao partido e ao tipo de voto (nominal ou legenda) para calcular o índice de legenda por seção (pergunta 8). O partido é derivado dos 2 primeiros dígitos do número votável.    |
| FATO_VOTACAO_PARTIDO_ZONA       | zona × eleição × cargo × agremiação                 | Base 5. Dá a visão do partido por zona (perguntas 3 e 8) sem precisar processar milhões de linhas de seção.                                                                                                      |
| FATO_VOTACAO_CANDIDATO_ZONA     | zona × eleição × cargo × candidato                  | Base 6. A margem entre os dois candidatos do 2º turno (pergunta 7) exige votos por candidato em cada zona.                                                                                                       |
| FATO_PERFIL_ELEITORADO_SECAO    | seção × eleição × perfil                            | Base 10. Dá a composição do eleitorado de cada seção (escolaridade, gênero, idade), usada para definir seções de baixa e alta escolaridade (perguntas 2 e 6).                                                    |
| FATO_PERFIL_COMPARECIMENTO_ZONA | zona × eleição × turno × perfil                     | Base 11. Só existe por zona e perfil, e é isso que permite medir abstenção de jovens e comparecimento de idosos (perguntas 1, 3 e 4).                                                                            |

**Por que dois grãos geográficos (seção e zona)?** A seção serve à análise descritiva e à logística (perguntas 2, 6, 8 e 9). A zona serve às previsões e ao BI executivo: é o nível em que as decisões de campanha são tomadas e em que os dados são estáveis entre eleições (ver `sk_zona_estavel`). Manter os dois evita forçar uma análise de zona a recalcular tudo a partir da seção, e evita também inventar um detalhe de seção que a fonte não tem (a base 11, por exemplo, não existe por seção).

**Por que as fatos de perfil não têm cargo?** O perfil do eleitorado e o perfil de comparecimento descrevem pessoas, não votos em um cargo. Por isso a matriz de barramento não os liga a DIM_CARGO.

**Regra de unicidade do grão.** Em cada fato, a chave natural (as colunas do grão) é única, o que garante que a carga possa ser repetida sem duplicar dados. Atributos do arquivo de origem que não fazem parte do grão (por exemplo, estado civil, cor/raça e idioma indígena na base 11, ou a coluna `ST_VOTO_EM_TRANSITO`) são somados antes de gravar a fato, e a decisão é documentada. Sem isso, o grão declarado deixaria de ser único.

## 3. Métricas e dimensões

### 3.1 O que fica na fato

Nas fatos ficam **apenas medidas aditivas**, isto é, contagens que podem ser somadas por qualquer dimensão sem perder sentido:

- Detalhe da apuração (seção e zona): aptos, comparecimento, abstenções, votos nominais, votos de legenda, brancos e nulos.
- Votação por partido ou candidato: votos nominais, votos de legenda, votos por tipo de voto.
- Perfil do eleitorado: eleitores do perfil, com biometria, com deficiência.
- Perfil do comparecimento: eleitores do perfil, comparecimento e abstenção.

**As taxas (K1, K2b, K3, K4, K5, K7, K8) não são gravadas na fato.** Uma taxa é uma razão, e a média de taxas de seções diferentes não é a taxa da zona (o erro conhecido como "média de médias"). A taxa correta é a razão das somas: por exemplo, abstenção da zona = soma das abstenções ÷ soma dos aptos. Calculando a taxa no BI, sobre as somas, o resultado fica correto em qualquer nível de agregação (seção, zona, capital) e o denominador fica explícito, como exige a regra 6.1 do catálogo de KPIs.

### 3.2 Dimensões

| Dimensão       | Papel no modelo                                                                                                                              |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| DIM_ELEICAO    | Quando: ano e turno. Hoje tem 2 linhas (2022, 1º e 2º turnos) e cresce quando entrarem outras eleições.                                      |
| DIM_CARGO      | Qual disputa: Presidente, Governador, Senador, Deputado Federal e Deputado Estadual (5 linhas), com marcação de majoritário ou proporcional. |
| DIM_MUNICIPIO  | Em qual capital (4 linhas), com a ponte entre o código TSE e o código IBGE.                                                                  |
| DIM_ZONA       | Em qual zona eleitoral, com a chave estável entre anos e a classificação de periferia.                                                       |
| DIM_SECAO      | Em qual seção e local de votação, com endereço e coordenadas.                                                                                |
| DIM_PERFIL     | Quem é o eleitor: gênero, faixa etária e escolaridade, com flags prontas para as definições do cliente.                                      |
| DIM_AGREMIACAO | Qual partido ou federação, com histórico de mudanças.                                                                                        |
| DIM_CANDIDATO  | Qual candidato (sem CPF nem contatos).                                                                                                       |
| DIM_TIPO_VOTO  | Que tipo de voto: nominal, legenda, branco ou nulo.                                                                                          |

A hierarquia geográfica (município, zona, seção) é mantida em dimensões separadas e encadeadas, o que permite subir e descer de nível (*drill-down*) no dashboard.

## 4. Por que cada atributo ficou em cada dimensão

A regra usada foi: **um atributo fica na dimensão cujo nível ele descreve**, isto é, no nível mais alto em que o valor deixa de variar. Isso evita repetir o mesmo dado milhões de vezes na fato e evita inconsistências (o mesmo local de votação com dois endereços diferentes).

### DIM_MUNICIPIO

Código TSE, código IBGE, nome, UF e flag de capital descrevem o município inteiro e não mudam por zona ou seção. O código IBGE fica aqui porque a ponte TSE ↔ IBGE é uma propriedade do município e é usada para mapas e dados externos. O código TSE é a chave de filtro das 4 capitais.

### DIM_ZONA

O número da zona só é único dentro do município, por isso a dimensão carrega o município junto. Dois atributos pertencem à zona, não à seção:

- **Distância ao centro e flag de zona periférica.** A periferia é definida para a zona (média das coordenadas dos seus locais de votação, quartil mais distante do centro). Colocá-la na seção misturaria seções de uma mesma zona em categorias diferentes, o que contraria a definição da pergunta 9.
- **`sk_zona_estavel`.** Zonas são criadas, divididas e renumeradas entre eleições. Por isso a dimensão tem uma linha por ano, e a chave estável liga a mesma zona entre 2022 e 2026. O percentual de locais de votação em comum fica na BRIDGE_ZONA, e não em DIM_ZONA, porque é uma relação *entre* duas zonas de anos diferentes, não um atributo de uma delas.

### DIM_SECAO

Número da seção, local de votação, endereço e coordenadas (quando existirem) descrevem a seção física. A latitude e a longitude ficam aqui, e não em DIM_ZONA, porque pertencem ao local de votação; a zona usa essas coordenadas para calcular sua própria distância ao centro. Esta dimensão também é o ponto de ligação com a base 12 (eleitorado por local de votação). O tamanho da seção (aptos) não fica na dimensão: é uma medida que varia por eleição e vem da fato, e o quartil de tamanho (K10) é calculado no BI.

### DIM_PERFIL

Gênero, faixa etária e escolaridade formam o perfil do eleitor, e é a combinação deles que as fatos de perfil registram. As flags (jovem 18–24, 60–69, 70+, voto facultativo, sem médio completo, superior completo) ficam aqui por dois motivos: (1) são **derivadas** exclusivamente desses três atributos, então pertencem ao mesmo lugar; (2) deixam as definições operacionais do cliente em **um só ponto**. Se a definição de "jovem" mudar, altera-se a dimensão, sem reescrever consultas. A escolaridade fica em DIM_PERFIL (e não na seção) porque um mesmo local tem eleitores de escolaridades diferentes: o que existe é a composição da seção, obtida na FATO_PERFIL_ELEITORADO_SECAO, e a classificação "seção de baixa escolaridade" (P75) é calculada sobre essa composição.

Atributos do arquivo de origem que não respondem a nenhuma pergunta (estado civil, cor/raça, quilombola, intérprete de Libras, identidade de gênero, idioma e grupo indígena) ficam fora da dimensão, para manter o grão único e a dimensão pequena (algumas centenas de linhas). Se o cliente passar a precisar deles, a dimensão pode ser estendida.

### DIM_AGREMIACAO

Número, sigla, nome e federação descrevem o partido. A dimensão usa SCD tipo 2 (guarda histórico com vigência) porque números, siglas e federações mudam entre eleições, e é preciso saber a qual partido um número se referia em cada ano. A flag `fl_cliente` fica aqui porque o partido-alvo é um atributo de agremiação e é configurável por linha, sem alterar código.

### DIM_CANDIDATO

Identifica o candidato (`SQ_CANDIDATO`, número, nome de urna, cargo, situação). O partido do candidato aparece aqui como atributo descritivo, mas a análise de partido usa DIM_AGREMIACAO, ligada diretamente à fato. Assim, o partido de um voto é o do momento do voto, e não depende do cadastro do candidato. CPF e contatos não são carregados, por serem dados pessoais sem utilidade para as perguntas.

### DIM_ELEICAO, DIM_CARGO e DIM_TIPO_VOTO

São dimensões pequenas e estáveis. A separação do cargo permite filtrar por majoritário ou proporcional (a regra de legenda só vale para proporcionais). DIM_TIPO_VOTO existe porque nominal, legenda, branco e nulo têm tratamento distinto nos KPIs (válidos = nominais + legenda; desperdiçados = brancos + nulos).

## 5. Como o modelo atende às perguntas de negócio

| Nº | Pergunta (resumo) | Fato principal | KPI | Como o modelo responde |
| --- | --- | --- | --- | --- |
| 1 | Zonas com maior abstenção entre jovens de 18 a 24 anos | FATO_PERFIL_COMPARECIMENTO_ZONA | K1, K6 | Filtra DIM_PERFIL pela flag "jovem", soma abstenção e aptos por zona e calcula a razão. |
| 2 | Seções de baixa escolaridade com mais brancos e nulos | FATO_DETALHE_SECAO + FATO_PERFIL_ELEITORADO_SECAO | K2, K2b, K11 | A perfil por seção define as seções acima do P75 de baixa escolaridade; a detalhe fornece brancos, nulos e comparecimento. |
| 3 | Zonas com muitas mulheres comparecendo e partido-alvo fraco | FATO_PERFIL_COMPARECIMENTO_ZONA + FATO_VOTACAO_PARTIDO_ZONA | K3, K5 | K3 vem do perfil; o desempenho do partido-alvo vem de DIM_AGREMIACAO (`fl_cliente`). |
| 4 | Menor comparecimento de 60–69 e 70+ | FATO_PERFIL_COMPARECIMENTO_ZONA | K7 | Flags 60–69 e 70+ de DIM_PERFIL. |
| 5 | 20 zonas com mais aptos e abstenção acima de 20% | FATO_DETALHE_ZONA | K1, K6 | Soma de aptos e abstenções por zona e ranking. |
| 6 | Capital com maior rejeição nas seções de alta escolaridade | FATO_DETALHE_SECAO + FATO_PERFIL_ELEITORADO_SECAO | K2b, K11 | Mesma lógica da pergunta 2, com a flag de superior completo e agrupamento por capital. |
| 7 | Zonas com menor diferença no 2º turno presidencial | FATO_VOTACAO_CANDIDATO_ZONA | K4 | Votos dos dois candidatos por zona; margem em p.p. e corte de 5 p.p. |
| 8 | Seções com maior proporção de voto de legenda | FATO_VOTACAO_SECAO_PARTIDO + FATO_VOTACAO_PARTIDO_ZONA | K5 | Votos de legenda ÷ votos válidos, por seção ou por zona. |
| 9 | Tamanho da seção versus abstenção em zonas periféricas de SP e RJ | FATO_DETALHE_SECAO + DIM_SECAO / DIM_ZONA | K1, K10 | Quartil de aptos da seção, abstenção por quartil e filtro pela flag de periferia da zona. |
| 10 | Capital com melhor relação válidos/abstenção | FATO_DETALHE_ZONA / FATO_DETALHE_SECAO | K8, K9 | Soma por capital, subindo pela hierarquia município–zona–seção. |

O modelo também prepara as perguntas preditivas: as fatos por zona alimentam P1 e P2; as dimensões de perfil, agremiação e zona alimentam P3 e P4; e a chave estável de zona permite comparar 2022 e 2026 apenas onde as zonas são comparáveis (80% ou mais de locais em comum).

## 6. Premissas e pontos a validar

- **Voto em trânsito.** As bases 5 e 7 trazem `ST_VOTO_EM_TRANSITO`. Conferir se há linhas separadas por essa condição e, se houver, somá-las antes de gravar a fato para não contar `QT_APTOS` duas vezes.
- **Regra de legenda.** O voto de legenda é o de número com 2 dígitos apenas nos cargos proporcionais. Os códigos de branco e nulo também têm poucos dígitos nos arquivos de seção e devem ser excluídos da regra, conferindo os valores no leiaute do TSE.
- **Coordenadas.** A flag de zona periférica (pergunta 9) depende de latitude e longitude da base 12. Se o arquivo não as trouxer, será usada a definição alternativa por bairros, a validar com o professor.
- **Partido-alvo.** Definido na Sprint 0 e gravado em `DIM_AGREMIACAO.fl_cliente`. A pergunta 3 usa a participação do partido-alvo nos votos válidos da zona, que deve constar do catálogo de KPIs.
- **Seções não instaladas e com zero aptos.** São excluídas das taxas, com registro da exclusão, conforme a regra 6.1.