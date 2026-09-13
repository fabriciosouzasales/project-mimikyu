/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2185 - Widen Catalog Admin Action Log for Printing Mapping
Versão......: 1.3
Status......: MIGRATION — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2185_widen_catalog_admin_action_log_for_printing_mapping.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-REVISION-01 (R4)
               + STAGING-CORRECTION-04 (§13, finding F-10)
               + STAGING-CORRECTION-05 (§3, BLOCKER B-10)
               + STAGING-CORRECTION-06 (§1–§3, BLOCKER B-11)

-------------------------------------------------------------------------------
Alterações da versão 1.3 (STAGING-CORRECTION-06, BLOCKER B-11)
-------------------------------------------------------------------------------
A v1.2 provava a terceira CHECK contando ocorrências de literais no TEXTO
de action_entity_match, exigindo exatamente 1 por nome conhecido. A
premissa é FALSA contra o próprio baseline legítimo:

    entity_type = 'CATALOG_IMPORT_JOB'
      AND action IN ('CATALOG_IMPORT_JOB',
                     'CATALOG_IMPORT_CONFIRMED',
                     'CATALOG_IMPORT_ROWS_REVALIDATED')

'CATALOG_IMPORT_JOB' é ao mesmo tempo um entity_type e uma action. Ele
aparece DUAS vezes, em papéis sintáticos distintos — e a v1.2 abortaria
contra o contrato CORRETO, impedindo a própria migration de rodar.

A correção NÃO é um caso especial `expected := 2`: isso codificaria a
colisão lexical de hoje e manteria a prova presa à representação textual.
A técnica é que estava errada.

v1.3 avalia SEMANTICAMENTE a expressão real da CHECK, obtida por
pg_get_expr(conbin, conrelid), contra a matriz explícita dos 29 pares do
baseline da Query 2159, dentro do cross-product 11 entity_types ×
29 actions = 319 pares. Quem decide se um par é permitido é o próprio
Postgres executando o predicado real — não há parsing, não há contagem,
e papel sintático deixa de importar.

Provas acrescentadas:
  A. os 29 pares esperados são TODOS aceitos;
  B. nenhum dos 290 pares restantes do cross-product é aceito;
  C. action_valid não aceita nenhuma action desconhecida (igualdade de
     conjunto, não só inclusão);
  D. entity_type_valid não aceita nenhum entity_type desconhecido;
  E. nenhum literal desconhecido no texto da terceira CHECK;
  + regressão nominal: (CATALOG_IMPORT_JOB, CATALOG_IMPORT_JOB) precisa
    ser ACEITO — é o par que derrubou a v1.2;
  + contraprova: (GAME, CARD_CREATED) precisa ser RECUSADO.

Continua fail-closed: qualquer drift real aborta ANTES do primeiro
DROP CONSTRAINT. Os três ADD CONSTRAINT seguem inalterados.

Alterações da versão 1.2 (STAGING-CORRECTION-05, BLOCKER B-10):
- O GUARD anti-drift passa a cobrir as TRÊS CHECKs. Até a v1.1 ele lia e
  protegia apenas `action_valid` e `entity_type_valid`; a terceira —
  `ck_catalog_admin_action_log_action_entity_match` — era DROPADA e
  recriada sem nenhuma prova prévia do seu conteúdo.
  A janela de drift era real e específica: outra frente podia ter
  PERMITIDO um par action × entity_type novo sem que nenhuma linha o
  tivesse usado ainda. A prova "existem rows fora do contrato?" não
  detecta esse caso — permissão não exercida também é contrato, e o
  DROP + ADD a destruiria em silêncio.
  A v1.2 aborta se a CHECK não existir e prova, por três invariantes
  estruturais independentes, que o contrato de pares vigente é
  exatamente o baseline conhecido. Ver o bloco B-10 no guard.
- Nenhuma mudança nos três ADD CONSTRAINT. O contrato final continua
  30 actions / 12 entity_types / 12 ramos, literal e aditivo.

Alterações da versão 1.1 (STAGING-CORRECTION-04, F-10):
- GUARD anti-drift passa a casar o LITERAL QUOTED COMPLETO ('VALOR') em
  vez de substring nua. Com substring, 'CARD_VARIANT_TYPE' era dado como
  presente apenas porque 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' aparecia na
  definição — falso negativo exatamente na deteção de drift, que é a
  única razão de o guard existir. Vale para os três checks: actions,
  entity_types e a prova contra as linhas já gravadas.
- MUDANÇA APENAS NO GUARD. Os três ADD CONSTRAINT continuam literais,
  aditivos e byte-a-byte idênticos aos da v1.0.
Fase........: PHASE B do rollout — aplicar ANTES da Query 2181
Precedentes.: 2146, 2151, 2153, 2159 (mesma técnica, mesma disciplina aditiva)

Descrição resumida:
Cria contrato próprio de auditoria para o mapeamento externo de Impressão:
+1 action, +1 entity_type, +1 ramo de action_entity_match.

-------------------------------------------------------------------------------
POR QUE ISTO EXISTE — BLOCKER R4
-------------------------------------------------------------------------------
A Query 2181 v1.0 reusava:

    action      = CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED
    entity_type = CARD_VARIANT_TYPE_EXTERNAL_MAPPING
    metadata.domain = 'PRINTING'

NÃO APROVADO, e com razão. catalog_admin_action_log tem três domínios
FECHADOS — action, entity_type e o casamento action × entity_type. O par
reusado está semanticamente ligado à tabela
card_variant_type_external_mapping. Printing Mapping é OUTRA entidade,
com outra tabela, outro ciclo de vida e outro eixo do modelo.

Distinguir por metadata seria: guardar a identidade da entidade fora da
coluna que existe para guardar a identidade da entidade. Toda consulta
por entity_type passaria a precisar ler JSON para não misturar dois
domínios — e qualquer consulta que esquecesse disso devolveria resultado
errado sem erro nenhum.

-------------------------------------------------------------------------------
DECISÃO A vs B — ESCOLHIDO: A (MENOR CONTRATO SEMANTICAMENTE CORRETO)
-------------------------------------------------------------------------------
A. Uma única action CARD_PRINTING_EXTERNAL_MAPPING_CREATED, carregando em
   metadata: supersedes_mapping_id, rows_revalidated, rows_still_pending,
   jobs_affected, trait_ids, raw_field, tokens e origin_row_id.

B. A mesma, MAIS CARD_PRINTING_EXTERNAL_MAPPING_SUPERSEDED.

Escolhido A. Razão:

A substituição NÃO é um evento independente. Criação do sucessor,
desativação do predecessor e propagação acontecem na MESMA transação,
atomicamente (Query 2181, passos 1–5). Registrar dois eventos para um
único ato atômico cria duas linhas que podem divergir — e nenhuma delas
seria a verdade sozinha.

Teste de suficiência auditável aplicado:

  "Quando o token X deixou de usar o mapping M1?"
      -> a linha CREATED cujo metadata.supersedes_mapping_id = M1;
         created_at dessa linha é o instante exato.

  "Qual a cadeia histórica do token X?"
      -> card_printing_external_mapping.supersedes_mapping_id encadeia
         M3 -> M2 -> M1; o log espelha cada elo.

  "Quantas linhas foram revalidadas naquela substituição?"
      -> metadata.rows_revalidated / rows_still_pending / jobs_affected.

Nenhuma pergunta de auditoria fica sem resposta. B seria redundância,
não cobertura. Se um dia a desativação passar a poder ocorrer SEM um
sucessor na mesma transação, B volta à mesa — hoje isso é impossível
por construção (Query 2174, guard B: reativação proibida; e não existe
caminho editorial que apenas desative).

-------------------------------------------------------------------------------
BASELINE — E POR QUE ELE É VERIFICADO EM TEMPO DE EXECUÇÃO
-------------------------------------------------------------------------------
Baseline documental: estado final da Query 2159 (promovida em
database/schema/), 29 actions / 11 entity_types / 11 ramos.

A Query 2159 existe porque a v1.0 dela partiu de um baseline
DESATUALIZADO (o arquivo 2010) e teria removido 9 pares action/entity_type
em uso real por 223 linhas em produção. O erro foi pego no pre-flight.

Esta Query não repete isso. O GUARD abaixo NÃO confia no baseline
documental: ele lê pg_get_constraintdef() no instante da execução e
ABORTA se qualquer um dos 29 actions / 11 entity_types conhecidos não
estiver presente — ou seja, se outra frente tiver ampliado as CHECKs
desde 2159 e este arquivo, portanto, não for mais um superconjunto
estrito. Premissa envelhece; guard não.

Se o guard disparar: NÃO relaxar. Recapturar o estado real, reescrever
as três listas como superconjunto estrito do que existe, e só então
executar.

-------------------------------------------------------------------------------
ESTRITAMENTE ADITIVO
-------------------------------------------------------------------------------
Nenhum valor existente é removido, renomeado ou reordenado. As três
listas abaixo são os 29/11/11 da Query 2159, na mesma ordem, mais:

    action      + CARD_PRINTING_EXTERNAL_MAPPING_CREATED   = 30
    entity_type + CARD_PRINTING_EXTERNAL_MAPPING           = 12
    ramo        + CARD_PRINTING_EXTERNAL_MAPPING -> aquela action = 12

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table (criação original;
  NÃO reflete o estado atual das três CHECKs — ver 2159).
- Query 2159 - último widen conhecido (LIVE, promovido).
- Query 2172 - Card Printing External Mapping (entidade auditada).

Impacto no frontend: web/lib/catalogo/log-atualizacoes-labels.ts precisa
do rótulo do novo entity_type e da nova action — sem isso a tela
/catalogo/log-atualizacoes exibe o enum técnico cru, que foi exatamente
o incidente de 2026-08-16. Rótulos incluídos nesta rodada de staging.

-------------------------------------------------------------------------------
ESTADO FINAL (registro pós-rollout)
-------------------------------------------------------------------------------
Estado LIVE das três CHECKs depois desta migration:
30 actions / 12 entity_types / 12 ramos de action_entity_match.

Este arquivo é MIGRATION porque altera CHECKs já existentes, seguindo a
mesma disciplina dos precedentes 2146, 2151, 2153 e 2159. A forma
canônica de catalog_admin_action_log continua sendo a Query 2010, e o
último widen consolidado é a 2159.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-12).** Guard anti-drift por substring nua. |
| 1.1 | **Literal quoted completo no guard (2026-09-12).** Fecha F-10. |
| 1.2 | **Guard estendido à terceira CHECK (2026-09-12).** Fecha B-10. |
| 1.3 | **Prova semântica da matriz de pares (2026-09-12).** Fecha B-11:
        avalia pg_get_expr() contra o cross-product 11 × 29, em vez de
        contar literais. Esta é a versão executada e confirmada no banco
        físico na PHASE B da frente CARD-VARIANTS — PRINTING-ROUTING.
        Promovida de database/proposals/ para database/migrations/ em
        2026-09-13 (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável
        permanece idêntico ao artefato executado; só o cabeçalho registra
        o estado final. A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD — o estado real precisa ser subconjunto do que será escrito.
-- Fail-closed.
-- =========================================================================
DO $guard$
DECLARE
    v_action_def TEXT;
    v_entity_def TEXT;
    v_match_def TEXT;
    v_missing TEXT;
    v_extra TEXT;
    -- (B-11) prova semântica da matriz de pares.
    v_expr TEXT;
    v_sql TEXT;
    v_missing_pairs INTEGER;
    v_extra_pairs INTEGER;
    v_ok BOOLEAN;
BEGIN
    SELECT pg_get_constraintdef(c.oid) INTO v_action_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_valid';

    SELECT pg_get_constraintdef(c.oid) INTO v_entity_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_entity_type_valid';

    -- (B-10) A TERCEIRA CHECK tambem e carregada e protegida.
    SELECT pg_get_constraintdef(c.oid) INTO v_match_def
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_entity_match';

    IF v_action_def IS NULL OR v_entity_def IS NULL OR v_match_def IS NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_CHECKS_NOT_FOUND: uma das TRÊS CHECKs de catalog_admin_action_log não existe (action=%, entity=%, match=%). STOP — reauditar antes de qualquer DDL.',
            (v_action_def IS NOT NULL), (v_entity_def IS NOT NULL), (v_match_def IS NOT NULL);
    END IF;

    -- Todos os 29 actions conhecidos precisam estar na definição real.
    --
    -- (F-10, STAGING-CORRECTION-04 §13) O casamento é do LITERAL QUOTED
    -- COMPLETO, não de substring. Com `position(a IN def)` o guard era
    -- ambíguo: 'CARD_VARIANT_TYPE' é prefixo de
    -- 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', então o valor curto passaria
    -- mesmo tendo sido REMOVIDO da CHECK real — falso negativo justamente
    -- na deteção de drift, que é a única razão de o guard existir.
    -- pg_get_constraintdef() sempre emite os valores entre apóstrofos
    -- simples, então procurar ''VALOR'' é exato e não ambíguo.
    SELECT string_agg(a, ', ' ORDER BY a) INTO v_missing
      FROM (VALUES
            ('GAME_CREATED'),('GAME_UPDATED'),('GAME_DELETED'),
            ('EXPANSION_CREATED'),('EXPANSION_UPDATED'),('EXPANSION_DELETED'),
            ('CARD_SET_CREATED'),('CARD_SET_UPDATED'),('CARD_SET_DELETED'),
            ('CARD_CREATED'),('CARD_UPDATED'),('CARD_DEACTIVATED'),('CARD_REACTIVATED'),
            ('CATALOG_IMPORT_JOB'),('CATALOG_IMPORT_CONFIRMED'),('CATALOG_IMPORT_ROWS_REVALIDATED'),
            ('RARITY_CREATED'),('RARITY_UPDATED'),
            ('RARITY_EXTERNAL_MAPPING_CREATED'),('RARITY_EXTERNAL_MAPPING_UPDATED'),
            ('CARD_ASSET_MANUAL_IMPORT_COMPLETED'),('CARD_VARIANT_IMPORT_CONFIRMED'),
            ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
            ('CARD_VARIANT_TYPE_CREATED'),('CARD_VARIANT_TYPE_UPDATED'),
            ('CARD_VARIANT_TYPE_DEACTIVATED'),('CARD_VARIANT_TYPE_REACTIVATED'),
            ('CARD_PRIMARY_SPECIES_RESOLVED'),('CARD_PRIMARY_SPECIES_CORRECTED')
      ) AS known(a)
     WHERE position('''' || a || '''' IN v_action_def) = 0;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_BASELINE_DRIFT: a CHECK real de action não contém: %. Esta Query deixaria de ser aditiva. STOP — recapturar pg_get_constraintdef() e reescrever as listas como superconjunto estrito.', v_missing;
    END IF;

    SELECT string_agg(e, ', ' ORDER BY e) INTO v_missing
      FROM (VALUES
            ('GAME'),('EXPANSION'),('CARD_SET'),('CARD'),('CATALOG_IMPORT_JOB'),
            ('RARITY'),('RARITY_EXTERNAL_MAPPING'),('CATALOG_VARIANT_IMPORT_JOB'),
            ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING'),('CARD_VARIANT_TYPE'),
            ('CARD_PRIMARY_SPECIES')
      ) AS known(e)
     -- (F-10) Literal quoted completo. 'CARD_VARIANT_TYPE' NAO pode ser
     -- dado como presente so porque 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING'
     -- esta na definicao.
     WHERE position('''' || e || '''' IN v_entity_def) = 0;

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_BASELINE_DRIFT: a CHECK real de entity_type não contém: %. STOP — mesma instrução acima.', v_missing;
    END IF;

    -- =====================================================================
    -- (C) e (D) — IGUALDADE DE CONJUNTO, não apenas inclusão.
    --
    -- Os dois checks acima provam que nada FALTA. Faltava o outro sentido:
    -- um valor NOVO acrescentado por outra frente passaria despercebido e
    -- seria apagado pelo DROP + ADD.
    --
    -- Aqui a extração textual é legítima e exata: `action_valid` e
    -- `entity_type_valid` são listas PLANAS de uma única coluna — não
    -- existe papel sintático a confundir, que é precisamente o defeito
    -- (B-11) que impede usar esta técnica na terceira CHECK.
    -- =====================================================================
    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_action_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
            'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
            'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
            'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
            'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
            'CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED','RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED');

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_ACTION_UNKNOWN: a CHECK real de action aceita valor(es) que este staging desconhece: %. Sobrescrevê-la removeria esse contrato. STOP — incorporar antes de executar.', v_extra;
    END IF;

    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_entity_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
            'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
            'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES');

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_ENTITY_UNKNOWN: a CHECK real de entity_type aceita valor(es) que este staging desconhece: %. STOP — mesma instrução acima.', v_extra;
    END IF;

    -- Prova direta e independente: nenhum par já gravado pode ficar de fora.
    IF EXISTS (
        SELECT 1 FROM public.catalog_admin_action_log l
         WHERE position('''' || l.action || '''' IN v_action_def) = 0
            OR position('''' || l.entity_type || '''' IN v_entity_def) = 0
    ) THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_EXISTING_ROWS_UNCOVERED: existem linhas gravadas cujo action/entity_type não aparece na CHECK atual. Estado inconsistente. STOP.';
    END IF;

    -- =====================================================================
    -- (B-10 / B-11) ANTI-DRIFT DA TERCEIRA CHECK — PROVA SEMÂNTICA
    --
    -- O guard acima prova o que JÁ FOI GRAVADO. Isso não basta: outra
    -- frente pode ter PERMITIDO um par novo sem que nenhuma linha o tenha
    -- usado ainda. Permissão não exercida também é contrato — e o
    -- DROP + ADD abaixo a destruiria silenciosamente.
    --
    -- POR QUE NÃO CONTAR LITERAIS (B-11). A v1.2 exigia que cada nome
    -- conhecido aparecesse exatamente 1x no texto de action_entity_match.
    -- A premissa é FALSA no próprio baseline legítimo:
    --
    --     entity_type = 'CATALOG_IMPORT_JOB'
    --       AND action IN ('CATALOG_IMPORT_JOB', ...)
    --
    -- 'CATALOG_IMPORT_JOB' é, ao mesmo tempo, um entity_type e uma action.
    -- Ele aparece DUAS vezes, em papéis sintáticos diferentes, e a v1.2
    -- teria abortado contra o contrato CORRETO. Contagem global de
    -- literal não distingue papel — é a técnica que está errada, não o
    -- limite. Tratar 'CATALOG_IMPORT_JOB' como caso especial de 2
    -- apenas codificaria a colisão lexical de hoje e manteria a prova
    -- presa à representação textual.
    --
    -- TÉCNICA v1.3 — AVALIAÇÃO SEMÂNTICA DA EXPRESSÃO REAL.
    -- pg_get_expr(conbin, conrelid) devolve a expressão da CHECK com as
    -- colunas `entity_type` e `action` NÃO qualificadas. Ela é então
    -- avaliada, via EXECUTE, contra um cross-product construído com
    -- exatamente esses nomes de coluna. Não há parsing: quem decide se um
    -- par é permitido é o próprio Postgres, executando o predicado real.
    --
    -- Universo do teste: 11 entity_types × 29 actions = 319 pares, dos
    -- quais 29 são a matriz baseline da Query 2159. As duas contagens
    -- abaixo fecham o contrato nos dois sentidos:
    --
    --   A. nenhum par ESPERADO pode ser recusado  (v_missing_pairs = 0)
    --   B. nenhum par NÃO esperado pode ser aceito (v_extra_pairs   = 0)
    --
    -- Papel sintático deixa de importar: o par
    -- (CATALOG_IMPORT_JOB, CATALOG_IMPORT_JOB) é apenas mais uma linha
    -- da matriz esperada, e é provado nominalmente logo abaixo.
    -- =====================================================================
    SELECT pg_get_expr(c.conbin, c.conrelid) INTO v_expr
      FROM pg_catalog.pg_constraint c
     WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
       AND c.conname = 'ck_catalog_admin_action_log_action_entity_match';

    IF v_expr IS NULL OR btrim(v_expr) = '' THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_EXPR_UNREADABLE: não foi possível renderizar a expressão de ck_catalog_admin_action_log_action_entity_match. STOP.';
    END IF;

    v_sql := format($q$
        SELECT
            count(*) FILTER (WHERE x.expected     AND NOT (%1$s)),
            count(*) FILTER (WHERE NOT x.expected AND     (%1$s))
          FROM (
              SELECT e.v AS entity_type,
                     a.v AS action,
                     (e.v, a.v) IN (
                         VALUES
                           ('GAME','GAME_CREATED'),
                           ('GAME','GAME_UPDATED'),
                           ('GAME','GAME_DELETED'),
                           ('EXPANSION','EXPANSION_CREATED'),
                           ('EXPANSION','EXPANSION_UPDATED'),
                           ('EXPANSION','EXPANSION_DELETED'),
                           ('CARD_SET','CARD_SET_CREATED'),
                           ('CARD_SET','CARD_SET_UPDATED'),
                           ('CARD_SET','CARD_SET_DELETED'),
                           ('CARD_SET','CARD_ASSET_MANUAL_IMPORT_COMPLETED'),
                           ('CARD','CARD_CREATED'),
                           ('CARD','CARD_UPDATED'),
                           ('CARD','CARD_DEACTIVATED'),
                           ('CARD','CARD_REACTIVATED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_JOB'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED'),
                           ('CATALOG_IMPORT_JOB','CATALOG_IMPORT_ROWS_REVALIDATED'),
                           ('RARITY','RARITY_CREATED'),
                           ('RARITY','RARITY_UPDATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_CREATED'),
                           ('RARITY_EXTERNAL_MAPPING','RARITY_EXTERNAL_MAPPING_UPDATED'),
                           ('CATALOG_VARIANT_IMPORT_JOB','CARD_VARIANT_IMPORT_CONFIRMED'),
                           ('CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_CREATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_UPDATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_DEACTIVATED'),
                           ('CARD_VARIANT_TYPE','CARD_VARIANT_TYPE_REACTIVATED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_RESOLVED'),
                           ('CARD_PRIMARY_SPECIES','CARD_PRIMARY_SPECIES_CORRECTED')
                     ) AS expected
                FROM unnest(ARRAY[
                         'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
                         'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
                         'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
                         'CARD_PRIMARY_SPECIES']::text[]) AS e(v)
                CROSS JOIN unnest(ARRAY[
                         'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
                         'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
                         'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
                         'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
                         'CATALOG_IMPORT_JOB','CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
                         'RARITY_CREATED','RARITY_UPDATED',
                         'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
                         'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
                         'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
                         'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
                         'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
                         'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED']::text[]) AS a(v)
          ) x
    $q$, v_expr);

    EXECUTE v_sql INTO v_missing_pairs, v_extra_pairs;

    IF v_missing_pairs <> 0 THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_PAIR_MISSING: % par(es) da matriz baseline da Query 2159 NÃO são aceitos pela CHECK real. O contrato encolheu. STOP — recapturar pg_get_expr() e reescrever o ADD CONSTRAINT como superconjunto estrito.', v_missing_pairs;
    END IF;

    IF v_extra_pairs <> 0 THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_PAIR_EXTRA: % par(es) FORA da matriz baseline são aceitos pela CHECK real — permissão que este staging desconhece, inclusive uma que nenhuma linha usou ainda. A CHECK está À FRENTE do baseline. STOP — recapturar e incorporar antes de executar.', v_extra_pairs;
    END IF;

    -- -------------------------------------------------------------------
    -- REGRESSÃO NOMINAL DO B-11. O par legítimo em que entity_type e
    -- action são o MESMO literal precisa passar. Se esta prova falhar, a
    -- técnica voltou a confundir papel sintático com ocorrência textual.
    -- -------------------------------------------------------------------
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_JOB') INTO v_ok;

    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_REGRESSION_B11: o par LEGÍTIMO (CATALOG_IMPORT_JOB, CATALOG_IMPORT_JOB) foi recusado pela CHECK real. Ou a CHECK regrediu, ou a prova voltou a depender de contagem textual. STOP.';
    END IF;

    -- Contraprova: um par do cross-product que NUNCA foi permitido.
    EXECUTE format(
        'SELECT (%s) FROM (SELECT %L::text AS entity_type, %L::text AS action) t',
        v_expr, 'GAME', 'CARD_CREATED') INTO v_ok;

    IF v_ok IS NOT FALSE THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_OVERPERMISSIVE: o par ILEGÍTIMO (GAME, CARD_CREATED) é aceito pela CHECK real. O contrato de pares não é o conhecido. STOP.';
    END IF;

    -- (E) Nenhum literal desconhecido no texto da terceira CHECK. Aqui a
    -- extração textual é legítima: ela não infere papel nem cardinalidade,
    -- apenas confirma que o vocabulário é o ratificado. Um nome NOVO
    -- (que o cross-product acima não cobriria) aparece aqui.
    SELECT string_agg(DISTINCT t, ', ' ORDER BY t) INTO v_extra
      FROM (SELECT (regexp_matches(v_match_def, '''([A-Z][A-Z_]*)''', 'g'))[1] AS t) AS found
     WHERE t NOT IN (
            'GAME','EXPANSION','CARD_SET','CARD','CATALOG_IMPORT_JOB',
            'RARITY','RARITY_EXTERNAL_MAPPING','CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING','CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES',
            'GAME_CREATED','GAME_UPDATED','GAME_DELETED',
            'EXPANSION_CREATED','EXPANSION_UPDATED','EXPANSION_DELETED',
            'CARD_SET_CREATED','CARD_SET_UPDATED','CARD_SET_DELETED',
            'CARD_CREATED','CARD_UPDATED','CARD_DEACTIVATED','CARD_REACTIVATED',
            'CATALOG_IMPORT_CONFIRMED','CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED','RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED','RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED','CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED','CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED','CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED','CARD_PRIMARY_SPECIES_CORRECTED'
     );

    IF v_extra IS NOT NULL THEN
        RAISE EXCEPTION 'WIDEN_ACTION_LOG_MATCH_DRIFT_UNKNOWN: a CHECK action_entity_match cita valor(es) que este staging desconhece: %. A CHECK real está À FRENTE do baseline conhecido — sobrescrevê-la removeria esse contrato. STOP — recapturar e incorporar antes de executar.', v_extra;
    END IF;
END;
$guard$;

-- =========================================================================
-- ACTION — 29 preservados + 1.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_valid
    CHECK (
        action IN (
            'GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED',
            'EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED',
            'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED',
            'CARD_CREATED', 'CARD_UPDATED',
            'CARD_DEACTIVATED', 'CARD_REACTIVATED',
            'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED',
            'RARITY_CREATED', 'RARITY_UPDATED',
            'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED',
            'CARD_ASSET_MANUAL_IMPORT_COMPLETED',
            'CARD_VARIANT_IMPORT_CONFIRMED',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED',
            'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
            'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED',
            'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED',
            'CARD_PRINTING_EXTERNAL_MAPPING_CREATED'
        )
    );

-- =========================================================================
-- ENTITY_TYPE — 11 preservados + 1.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_entity_type_valid;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_entity_type_valid
    CHECK (
        entity_type IN (
            'GAME', 'EXPANSION', 'CARD_SET', 'CARD', 'CATALOG_IMPORT_JOB',
            'RARITY', 'RARITY_EXTERNAL_MAPPING', 'CATALOG_VARIANT_IMPORT_JOB',
            'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', 'CARD_VARIANT_TYPE',
            'CARD_PRIMARY_SPECIES',
            'CARD_PRINTING_EXTERNAL_MAPPING'
        )
    );

-- =========================================================================
-- ACTION × ENTITY_TYPE — 11 ramos preservados + 1.
-- =========================================================================
ALTER TABLE public.catalog_admin_action_log
    DROP CONSTRAINT ck_catalog_admin_action_log_action_entity_match;

ALTER TABLE public.catalog_admin_action_log
    ADD CONSTRAINT ck_catalog_admin_action_log_action_entity_match
    CHECK (
        (entity_type = 'GAME' AND action IN ('GAME_CREATED', 'GAME_UPDATED', 'GAME_DELETED'))
        OR (entity_type = 'EXPANSION' AND action IN ('EXPANSION_CREATED', 'EXPANSION_UPDATED', 'EXPANSION_DELETED'))
        OR (entity_type = 'CARD_SET' AND action IN (
                'CARD_SET_CREATED', 'CARD_SET_UPDATED', 'CARD_SET_DELETED', 'CARD_ASSET_MANUAL_IMPORT_COMPLETED'
            ))
        OR (entity_type = 'CARD' AND action IN (
                'CARD_CREATED', 'CARD_UPDATED', 'CARD_DEACTIVATED', 'CARD_REACTIVATED'
            ))
        OR (entity_type = 'CATALOG_IMPORT_JOB' AND action IN (
                'CATALOG_IMPORT_JOB', 'CATALOG_IMPORT_CONFIRMED', 'CATALOG_IMPORT_ROWS_REVALIDATED'
            ))
        OR (entity_type = 'RARITY' AND action IN ('RARITY_CREATED', 'RARITY_UPDATED'))
        OR (entity_type = 'RARITY_EXTERNAL_MAPPING' AND action IN (
                'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING_UPDATED'
            ))
        OR (entity_type = 'CATALOG_VARIANT_IMPORT_JOB' AND action = 'CARD_VARIANT_IMPORT_CONFIRMED')
        OR (entity_type = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING' AND action = 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED')
        OR (entity_type = 'CARD_VARIANT_TYPE' AND action IN (
                'CARD_VARIANT_TYPE_CREATED', 'CARD_VARIANT_TYPE_UPDATED',
                'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE_REACTIVATED'
            ))
        OR (entity_type = 'CARD_PRIMARY_SPECIES' AND action IN (
                'CARD_PRIMARY_SPECIES_RESOLVED', 'CARD_PRIMARY_SPECIES_CORRECTED'
            ))
        OR (entity_type = 'CARD_PRINTING_EXTERNAL_MAPPING' AND action = 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED')
    );

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   3 DROP + 3 ADD CONSTRAINT. Estado final:
--     30 actions / 12 entity_types / 12 ramos de action_entity_match.
--   Nenhuma linha existente invalidada (o guard já provou isso antes).
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Seção S19 (BLOCO I / GATE-A).
-- ============================================================================
