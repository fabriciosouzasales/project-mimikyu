-- ===========================================================================
-- Query 2834 — RUNNER SQL DOS VETORES COMPARTILHADOS DO EIXO 3
--              v2.2 — SCAFFOLD `type` NO RAW EXTERNO
--                     (MISSING-TYPE-CORRECTION-01)
-- ===========================================================================
-- STATUS: PROPOSTA — NÃO EXECUTADA. Pacote EDITION-CONTEXT-AXIS.
--
-- Este runner prova o contrato do eixo 3 contra a MESMA fixture que o runner
-- TS consome (test-vectors/edition-context-axis-vectors.json). Duas suítes
-- independentes lendo um arquivo único é o que transforma "as duas passaram"
-- em paridade verificada, e não em duas opiniões que coincidiram.
--
-- ---------------------------------------------------------------------------
-- O QUE MUDOU NA v2.0 — e por quê
-- ---------------------------------------------------------------------------
-- A v1.0 executava 14 dos 17 vetores. E3, E16 e E17 eram marcados SKIP porque
-- exigem estado de IMPRESSÃO que o runner não montava. Três defeitos somados:
--
--   (a) o cabeçalho da v1.0 AFIRMAVA que a fixture de Printing era criada
--       ("o runner a cria explicitamente"); o corpo não a criava. A única
--       referência a `card_printing_*` era a sentinela — que faz o oposto;
--   (b) os três vetores viravam SKIP, nunca PASS e nunca FAIL;
--   (c) o gate final só levantava exceção para FAIL > 0. Logo
--       14 PASS / 0 FAIL / 3 SKIP encerrava SEM exceção, e o rollout podia
--       ler isso como "verde".
--
-- O custo real de (b) não é "3 vetores a menos". Dois dos oito estados do
-- vocabulário têm UM ÚNICO vetor cada:
--
--       NOT_EVALUATED              -> somente E16
--       NEEDS_REVIEW_NO_EC_PROFILE -> somente E3
--
-- Com os SKIPs, 2/8 estados do contrato não eram provados do lado SQL. A
-- cobertura não caía 18%: caía 25% do vocabulário, e justamente nos dois
-- estados que governam "o eixo 3 nem roda" e "a composição não tem perfil".
--
-- v2.0: o runner MONTA a fixture de Impressão, por vetor, dentro da mesma
-- transação com ROLLBACK, e executa os 17 vetores / 18 casos.
--
-- ---------------------------------------------------------------------------
-- 17 VETORES != 17 LINHAS DE RESULTADO
-- ---------------------------------------------------------------------------
-- A fixture tem 17 `vector_id` e 18 CASOS: 16 vetores com `expected` direto e
-- E15, que não tem `expected` próprio e sim DOIS `sub_cases` (E15a, E15b).
-- O gate final NÃO pode conferir contra o literal 17 nem contra o literal 18:
-- conta os casos DERIVADOS da fixture e compara com o que executou. Se alguém
-- acrescentar um sub-caso amanhã, o gate acompanha sozinho; se alguém remover
-- um, o gate quebra — que é o comportamento desejado.
--
-- ---------------------------------------------------------------------------
-- A ENTRADA DE PRINTING É MEDIDA, NUNCA PRESUMIDA
-- ---------------------------------------------------------------------------
-- Cada vetor DECLARA o estado de Printing como entrada — o objeto sob teste é
-- o eixo 3, não o eixo 1. O runner monta um `raw_data` que deve produzir
-- aquele estado e então MEDE, com internal.compute_variant_residual_signature()
-- (contrato de Impressão, 3 argumentos), ANTES de chamar o contrato de três
-- eixos. Só depois de o estado medido bater com o declarado — e de o residual
-- pós-Impressão bater com `residual_after_printing` da fixture — é que o eixo
-- 3 é avaliado. Divergência é FAIL com `PRINTING_FIXTURE_MISMATCH`, jamais
-- PASS por acidente.
--
-- Essa medição prévia é o que dá sentido a E17: ela prova, como PREDICADO
-- EXPLÍCITO e não como efeito colateral, que o token de Impressão foi
-- consumido pelo eixo 1 e não realimentou o eixo 3.
--
-- ---------------------------------------------------------------------------
-- READ-ONLY POR EFEITO, NÃO POR AUSÊNCIA DE DML
-- ---------------------------------------------------------------------------
-- O runner escreve: cria traits, profiles e mappings sintéticos de Edition
-- Context E de Impressão. Todos prefixados `VEC2834`. A transação inteira
-- termina em ROLLBACK, e cada vetor desfaz a própria fixture antes do vetor
-- seguinte — de modo que nenhum vetor herda estado do anterior nem depende do
-- ROLLBACK final para isolamento.
--
-- ---------------------------------------------------------------------------
-- O QUE MUDOU NA v2.1 — POR QUE O ISOLAMENTO NÃO PODE SER `DELETE`
-- ---------------------------------------------------------------------------
-- A v2.0 isolava os vetores apagando a fixture (blocos 2.0 e 2.3). Isso é
-- IMPOSSÍVEL, e a impossibilidade é uma propriedade desejada do schema, não um
-- defeito a contornar. Os dois Perfis sintéticos — Impressão e Edition
-- Context — precisam estar SELADOS antes da medição, porque tanto
-- compute_variant_residual_signature() quanto 2211 casam o Perfil por
-- IGUALDADE EXATA de `traits_signature`. E, uma vez selado, o Perfil não sai:
--
--   · filha primeiro  -> card_printing_profile_trait / ..._context_profile_trait
--                        têm guard BEFORE DELETE que levanta
--                        CARD_PRINTING_PROFILE_COMPOSITION_SEALED /
--                        EDITION_CONTEXT_COMPOSITION_IMMUTABLE quando o pai
--                        existe e já tem assinatura;
--   · pai primeiro    -> as FKs dessas filhas para o Perfil são ON DELETE
--                        RESTRICT.
--
-- Não existe ordem válida. O ramo "Profile sendo removido na mesma transação"
-- dos guards só se abriria com ON DELETE CASCADE, que não é o caso aqui.
--
-- A v2.1 troca o mecanismo: cada vetor roda dentro de uma SUBTRANSAÇÃO
-- PL/pgSQL (bloco `BEGIN ... EXCEPTION ... END`), encerrada por um
-- `RAISE EXCEPTION` DELIBERADO com SQLSTATE exclusivo `P2834`. O handler
-- captura SOMENTE esse SQLSTATE; qualquer outra exceção propaga e aborta o
-- runner inteiro. Não há `WHEN OTHERS` em lugar nenhum deste arquivo.
--
-- IDENTIDADE DO SENTINEL (v2.1, reforçada). SQLSTATE sozinho não basta: nada
-- impede que uma exceção interna FUTURA reutilize `P2834` e seja engolida como
-- se fosse o sentinel. Por isso a mensagem é DETERMINÍSTICA e específica do
-- vetor — `VEC2834_VECTOR_ROLLBACK:<vector_id>` — calculada ANTES de abrir a
-- subtransação e comparada por IGUALDADE EXATA (`IS DISTINCT FROM`) contra
-- `SQLERRM` no handler. Qualquer divergência executa `RAISE;`, que re-levanta
-- a exceção ORIGINAL intacta. Fail-closed: só o sentinel daquele vetor, com
-- aquela mensagem, é absorvido.
--
-- O que torna isso correto é uma garantia documentada do PL/pgSQL: ao capturar
-- um erro, "as variáveis locais permanecem como estavam quando o erro
-- ocorreu, mas todo o estado de banco persistente dentro do bloco é desfeito".
-- Logo: as linhas físicas do vetor somem — sem DELETE, sem tocar em selo,
-- guard ou FK — e os resultados já medidos, acumulados em `v_acc` (JSONB em
-- memória), sobrevivem. Só DEPOIS do handler eles são materializados em
-- `_res2834`, que é criada FORA da subtransação e por isso não é desfeita.
--
-- Consequências normativas:
--
--   · o sentinel NÃO é um mecanismo de tratamento de erro. Ele roda depois de
--     TODOS os casos do vetor terem sido medidos, e sua única função é desfazer
--     a fixture física. Nenhum FAIL vira exceção: FAIL continua sendo resultado
--     de caso, entra em `v_acc` e chega à Seção 3;
--   · os blocos 2.0 e 2.3 deixam de apagar qualquer coisa e passam a ser GATES
--     DE ZERO RESÍDUO sobre as dez tabelas sintéticas — na entrada e na saída
--     de cada vetor. Eles agora PROVAM o isolamento em vez de tentarem produzi-lo;
--   · selos, guards, FKs e imutabilidade permanecem exatamente como estão. O
--     runner passou a caber no schema; o schema não foi afrouxado para caber no
--     runner.
--
-- NOTA DE LEITURA: o corpo da subtransação NÃO foi reindentado. A mudança é
-- estrutural (abre `BEGIN`, fecha com sentinel + `EXCEPTION ... END`) e manter
-- a indentação original faz o diff mostrar exatamente o que mudou de semântica.
-- Os limites do bloco estão marcados com faixas `######` para leitura.
--
-- ---------------------------------------------------------------------------
-- O QUE MUDOU NA v2.2 — O SCAFFOLD `type` DO RAW EXTERNO
-- ---------------------------------------------------------------------------
-- REGISTRO DE INCIDENTE — `BATCH7-2834-LIVE-EXECUTION-01` → **STOP**.
--
--   Erro: `COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_TYPE: raw_data.type
--   ausente.`
--
--   Causa: a v2.1 montava `v_raw` com `size`, `subtype` e `stamp`, mas sem
--   `type`. O contrato de Impressão — internal.compute_variant_residual_
--   signature() — normaliza `raw_data.type` como PRIMEIRA operação e levanta
--   exceção se vier NULL ou vazio. O defeito não existia na v1.0: foi o gate
--   de medição prévia da v2.0 que passou a chamar essa função.
--
--   Impacto: ZERO persistente, comprovado por postcheck read-only — zero
--   resíduo `VEC2834*` nas dez tabelas, baseline operacional 1642 com
--   Edition Context 1092/550/0 intacto, CANCELLED 847/415 intacto, catálogos
--   intactos, `2214` ainda fora do ledger. O erro ocorreu dentro do
--   `BEGIN … ROLLBACK`, no primeiro vetor.
--
-- Correção: `v_raw` passa a incluir `'type', 'normal'`, precedente canônico
-- dos harnesses de Impressão (`2824`, `2827`). `size` permanece `'STANDARD'`
-- — `normalize_external_catalog_value()` aplica upper(), logo já é
-- equivalente ao `standard` daqueles precedentes, e mexer nele seria mudança
-- sem causa.
--
-- `type` É SCAFFOLD, NÃO DIMENSÃO. Ele pertence ao raw externo que o eixo 1
-- exige; não pertence ao contrato compartilhado do eixo 3. Por isso a fixture
-- JSON NÃO foi tocada: acrescentar `type` a ela faria o runner TS e o runner
-- SQL passarem a negociar um campo que o eixo 3 não modela.
--
-- Todo campo técnico acrescentado ao raw cria a obrigação de provar que ele
-- ficou inerte. Daí o gate (0) da Seção 2.2: `residual_type` tem de voltar
-- exatamente `'NORMAL'`. Se algum dia um mapping passar a consumir esse
-- token, o vetor vira FAIL com `PRINTING_TYPE_SCAFFOLD_MISMATCH` em vez de
-- deslocar o residual em silêncio. Medido antes desta correção: nenhum
-- mapping de Impressão ou de Edition Context usa `raw_field='type'`, e
-- nenhum usa `normalized_token='NORMAL'` — os `raw_field` existentes nos dois
-- catálogos são apenas `stamp` e `subtype`.
-- ===========================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- PRECONDIÇÃO — contratos e tabelas dos DOIS eixos precisam existir.
-- O eixo 1 entra aqui porque a v2.0 passa a medi-lo explicitamente.
-- ---------------------------------------------------------------------------
DO $pre$
DECLARE
    v_missing TEXT := '';
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='resolve_variant_row_axes')
    THEN v_missing := v_missing || ' internal.resolve_variant_row_axes'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='internal' AND p.proname='compute_variant_residual_signature')
    THEN v_missing := v_missing || ' internal.compute_variant_residual_signature'; END IF;

    IF to_regclass('public.card_edition_context_trait') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_trait'; END IF;
    IF to_regclass('public.card_edition_context_profile') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_profile'; END IF;
    IF to_regclass('public.card_edition_context_external_mapping') IS NULL
    THEN v_missing := v_missing || ' card_edition_context_external_mapping'; END IF;

    -- v2.0 — a fixture de Impressão exige estas cinco.
    IF to_regclass('public.card_printing_trait') IS NULL
    THEN v_missing := v_missing || ' card_printing_trait'; END IF;
    IF to_regclass('public.card_printing_profile') IS NULL
    THEN v_missing := v_missing || ' card_printing_profile'; END IF;
    IF to_regclass('public.card_printing_profile_trait') IS NULL
    THEN v_missing := v_missing || ' card_printing_profile_trait'; END IF;
    IF to_regclass('public.card_printing_external_mapping') IS NULL
    THEN v_missing := v_missing || ' card_printing_external_mapping'; END IF;
    IF to_regclass('public.card_printing_external_mapping_trait') IS NULL
    THEN v_missing := v_missing || ' card_printing_external_mapping_trait'; END IF;

    IF v_missing <> '' THEN
        RAISE EXCEPTION 'PRECONDITION_FAILED_2834: objetos ausentes —%. Executar 2203-2207 e 2211 antes.', v_missing;
    END IF;
END
$pre$;


-- ===========================================================================
-- SEÇÃO 0 — PAYLOAD + GATES DE INTEGRIDADE DA FIXTURE
-- ===========================================================================
CREATE TEMP TABLE _vec2834 (payload JSONB) ON COMMIT DROP;

-- Contrato derivado da fixture. Calculado, nunca hardcodado — ver a nota
-- "17 VETORES != 17 LINHAS DE RESULTADO" no cabeçalho.
CREATE TEMP TABLE _expect2834 (
    n_vectors INTEGER,
    n_cases   INTEGER,
    n_vocab   INTEGER
) ON COMMIT DROP;

-- >>> SUBSTITUIR O LITERAL ABAIXO PELO CONTEÚDO DO JSON <<<
INSERT INTO _vec2834 (payload) VALUES ('{"vectors":[]}'::JSONB);

DO $s0$
DECLARE
    p        JSONB;
    v_n      INTEGER;
    v_cases  INTEGER;
    v_vocab  INTEGER;
    v_roster TEXT;
    v_decl   TEXT;
    v_bad    TEXT;
BEGIN
    SELECT payload INTO p FROM _vec2834;

    v_n := jsonb_array_length(COALESCE(p->'vectors','[]'::JSONB));
    IF v_n = 0 THEN
        RAISE EXCEPTION 'S0 ABORT: payload de vetores vazio. Substitua o literal do bloco PAYLOAD pelo conteudo de test-vectors/edition-context-axis-vectors.json antes de executar. NAO registrar nenhum vetor como PASS nem como FAIL — o runner nao roda sem a fixture.';
    END IF;

    -- G1 — o roster declarado tem de bater com os vetores presentes. Um vetor
    -- que some do arquivo tem de quebrar o runner, não reduzir a cobertura
    -- em silêncio.
    SELECT string_agg(x, ',') INTO v_decl
      FROM jsonb_array_elements_text(p->'roster') x;
    SELECT string_agg(v->>'id', ',' ORDER BY ord) INTO v_roster
      FROM jsonb_array_elements(p->'vectors') WITH ORDINALITY AS t(v, ord);

    IF v_roster IS DISTINCT FROM v_decl THEN
        RAISE EXCEPTION 'S0 ABORT: roster divergente. Declarado: %. Presente: %.', v_decl, v_roster;
    END IF;

    -- G2 — bindings obrigatórios. Sem eles o runner inventaria a própria
    -- ligação símbolo -> objeto físico, e a paridade viraria coincidência.
    IF p->'bindings'->'tokens' IS NULL
       OR p->'bindings'->'scope' IS NULL
       OR p->'bindings'->>'game' IS NULL
       OR p->'bindings'->>'asset_source' IS NULL THEN
        RAISE EXCEPTION 'S0 ABORT: bloco bindings incompleto (esperado game, asset_source, tokens, scope).';
    END IF;

    -- G3 — todo estado citado em algum expected tem de estar no vocabulário.
    SELECT string_agg(DISTINCT e, ',') INTO v_bad
      FROM (
        SELECT v->'expected'->>'edition_context_state' AS e
          FROM jsonb_array_elements(p->'vectors') v
         WHERE v ? 'expected'
        UNION ALL
        SELECT sc->'expected'->>'edition_context_state'
          FROM jsonb_array_elements(p->'vectors') v,
               LATERAL jsonb_array_elements(COALESCE(v->'sub_cases','[]'::JSONB)) sc
      ) q
     WHERE e IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(p->'vocabulary') w WHERE w = e);

    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'S0 ABORT: estados fora do vocabulario declarado: %.', v_bad;
    END IF;

    -- G4 (v2.0) — CONTRATO DE CONTAGEM, derivado.
    -- Um caso = um `expected`. O vetor contribui com 1 se tiver `expected`
    -- próprio, mais 1 por sub-caso. E15 não tem `expected` próprio: contribui
    -- com 2. Hoje isso dá 18; o número não aparece escrito em lugar nenhum.
    SELECT count(*) INTO v_cases FROM (
        SELECT 1 FROM jsonb_array_elements(p->'vectors') v WHERE v ? 'expected'
        UNION ALL
        SELECT 1 FROM jsonb_array_elements(p->'vectors') v,
                      LATERAL jsonb_array_elements(COALESCE(v->'sub_cases','[]'::JSONB)) sc
    ) q;

    v_vocab := jsonb_array_length(COALESCE(p->'vocabulary','[]'::JSONB));

    IF v_cases < v_n THEN
        RAISE EXCEPTION 'S0 ABORT: % caso(s) derivado(s) para % vetor(es). Algum vetor nao tem expected nem sub_cases — ele nao mede nada.', v_cases, v_n;
    END IF;

    -- Todo vetor precisa render pelo menos um caso.
    SELECT string_agg(v->>'id', ',') INTO v_bad
      FROM jsonb_array_elements(p->'vectors') v
     WHERE NOT (v ? 'expected')
       AND jsonb_array_length(COALESCE(v->'sub_cases','[]'::JSONB)) = 0;

    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'S0 ABORT: vetor(es) sem expected e sem sub_cases: %.', v_bad;
    END IF;

    INSERT INTO _expect2834 VALUES (v_n, v_cases, v_vocab);

    RAISE NOTICE 'S0 OK — % vetores, % casos derivados, % estados no vocabulario, roster conferido.',
        v_n, v_cases, v_vocab;
END
$s0$;


-- ===========================================================================
-- SEÇÃO 1 — SENTINELA: o corpus real não pode conter os tokens de fixture
-- ===========================================================================
-- Se um token VEC2834* já existir no catálogo, o vetor mediria o dado de
-- produção e "passaria" provando outra coisa. É o mesmo cuidado que o bloco
-- `$why_foil_substitution` do precedente 2826 documenta.
--
-- ORDEM É NORMATIVA (v2.0): esta seção roda ANTES de qualquer fixture
-- sintética desta execução. Ela significa exatamente "não existe resíduo
-- VEC2834* anterior à rodada". A fixture de Impressão da v2.0 nasce na
-- Seção 2, depois daqui — por isso a sentinela pode continuar exigindo
-- ausência total sem entrar em conflito com a própria fixture que o runner
-- cria. Mover qualquer criação de fixture para antes desta seção a
-- transformaria num autobloqueio.
--
-- As tabelas N:N (profile_trait, mapping_trait) não recebem marcador próprio:
-- não têm coluna de código, e não podem existir órfãs dos pais verificados
-- abaixo. Provar os pais inexistentes prova as filhas inexistentes.
-- ===========================================================================
DO $s1$
DECLARE
    v_game UUID;
    v_src  UUID;
    v_hits INTEGER;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = (SELECT payload->'bindings'->>'game' FROM _vec2834);
    SELECT id INTO v_src  FROM public.asset_source WHERE code = (SELECT payload->'bindings'->>'asset_source' FROM _vec2834);

    IF v_game IS NULL OR v_src IS NULL THEN
        RAISE EXCEPTION 'S1 ABORT: game ou asset_source dos bindings nao existe no LIVE.';
    END IF;

    -- ---- eixo 3 ----------------------------------------------------------
    SELECT count(*) INTO v_hits
      FROM public.card_edition_context_external_mapping m
     WHERE m.game_id = v_game AND m.normalized_token LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % mapping(s) de Edition Context com token VEC2834* ja existem no catalogo. A sentinela esta suja — os vetores mediriam dado real. Limpar antes.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % trait(s) de Edition Context VEC2834* ja existem.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % profile(s) de Edition Context VEC2834* ja existem.', v_hits;
    END IF;

    -- ---- eixo 1 (v2.0) ---------------------------------------------------
    -- A v1.0 já checava o mapping. Faltavam trait e profile: um Perfil de
    -- Impressão VEC2834* remanescente mudaria o estado medido de E3/E17 sem
    -- que nada no runner acusasse.
    SELECT count(*) INTO v_hits
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game AND m.asset_source_id = v_src
       AND m.normalized_token LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % mapping(s) de IMPRESSAO com token VEC2834* existem. O estado de Printing dos vetores deixaria de ser o declarado.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_printing_trait WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % trait(s) de IMPRESSAO VEC2834* ja existem.', v_hits;
    END IF;

    SELECT count(*) INTO v_hits FROM public.card_printing_profile WHERE code LIKE 'VEC2834%';
    IF v_hits > 0 THEN
        RAISE EXCEPTION 'S1 ABORT: % profile(s) de IMPRESSAO VEC2834* ja existem.', v_hits;
    END IF;

    RAISE NOTICE 'S1 OK — sentinela limpa nos SEIS catalogos (3 de Edition Context, 3 de Impressao).';
END
$s1$;


-- ===========================================================================
-- SEÇÃO 2 — RUNNER
-- ===========================================================================
-- Criada FORA da subtransação de vetor e escrita SOMENTE depois que o handler
-- do sentinel devolve o controle. É por isso que ela não é desfeita junto com
-- a fixture física: nenhum INSERT nesta tabela acontece dentro do bloco
-- `BEGIN ... EXCEPTION ... END` de vetor algum.
CREATE TEMP TABLE _res2834 (
    vector_id   TEXT,
    label       TEXT,
    status      TEXT,          -- PASS | FAIL   (SKIP é proibido desde a v2.0)
    detail      TEXT
) ON COMMIT DROP;

DO $s2$
DECLARE
    -- Token técnico de Impressão do próprio runner. NÃO é símbolo da fixture:
    -- é o veículo mínimo para produzir estado de Impressão em E3 e E16, cujos
    -- `residual_after_printing` não trazem token de Impressão algum. E17 é
    -- diferente — lá o token vem da fixture (TOK_PRINTING), porque o vetor
    -- existe justamente para provar o que acontece com ele.
    c_pr_fix_token CONSTANT TEXT := 'VEC2834PRINTFIX';

    p          JSONB;
    v_game     UUID;
    v_src      UUID;

    v_vec      JSONB;
    v_case     JSONB;
    v_exp      JSONB;
    v_label    TEXT;

    v_trait    JSONB;
    v_prof     JSONB;
    v_map      JSONB;

    v_trait_id UUID;
    v_prof_id  UUID;
    v_map_id   UUID;

    v_sym2uuid JSONB;          -- simbolo -> uuid (traits e profiles)
    v_uuid2sym JSONB;          -- uuid    -> simbolo
    v_sig      UUID[];
    v_unsealed INTEGER;        -- prova do selo de profile do eixo 3

    v_raw      JSONB;
    v_sub      TEXT;
    v_stamp    TEXT[];

    v_ax       RECORD;

    v_got_state   TEXT;
    v_got_profile TEXT;
    v_got_traits  TEXT[];
    v_got_sub     TEXT;
    v_got_stamp   TEXT[];
    v_got_emits   BOOLEAN;

    v_exp_traits  TEXT[];
    v_exp_stamp   TEXT[];
    v_exp_sub     TEXT;

    v_errs     TEXT;
    v_tok      TEXT;

    -- ---- v2.0: fixture e medição do eixo 1 -------------------------------
    v_pr_state    TEXT;         -- estado de Impressão DECLARADO pelo vetor
    v_pr_token    TEXT;         -- token físico que a Impressão deve consumir
    v_pr_trait_id UUID;
    v_pr_prof_id  UUID;
    v_pr_map_id   UUID;
    v_pr_sealed   UUID[];

    v_pre         RECORD;       -- retorno de compute_variant_residual_signature
    v_pre_sub     TEXT;         -- residual pós-Impressão ESPERADO (fixture)
    v_pre_stamp   TEXT[];
    v_got_pre_stamp TEXT[];
    v_raw_stamp   TEXT[];

    -- ---- v2.1: subtransação por vetor ------------------------------------
    -- `v_acc` é a estrutura de resultados EM MEMÓRIA do vetor. Declarada aqui,
    -- fora do bloco `BEGIN ... EXCEPTION ... END`, e preservada pelo PL/pgSQL
    -- quando a subtransação é desfeita — é esse par (variável sobrevive,
    -- linha física não) que torna o sentinel utilizável como mecanismo de
    -- isolamento.
    v_acc         JSONB;
    v_residue     TEXT;        -- gate de zero resíduo (entrada e saída)
    -- Mensagem EXATA do sentinel deste vetor. Calculada fora da subtransação,
    -- de modo que nada de dentro dela possa influenciar o valor contra o qual
    -- o handler compara.
    v_sent_expected TEXT;
    v_vec_ord     INTEGER := 0;   -- vetores iniciados
    v_sent_hits   INTEGER := 0;   -- sentinels deliberados capturados
BEGIN
    SELECT payload INTO p FROM _vec2834;
    SELECT id INTO v_game FROM public.game         WHERE code = p->'bindings'->>'game';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = p->'bindings'->>'asset_source';

    FOR v_vec IN SELECT v FROM jsonb_array_elements(p->'vectors') v LOOP

        v_vec_ord := v_vec_ord + 1;
        v_acc     := '[]'::JSONB;

        -- Identidade do sentinel deste vetor, fixada ANTES de abrir a
        -- subtransação. É o valor único que o handler aceita.
        v_sent_expected := 'VEC2834_VECTOR_ROLLBACK:' || (v_vec->>'id');

        -- ===============================================================
        -- 2.0 GATE DE ZERO RESÍDUO — ENTRADA DO VETOR
        -- ===============================================================
        -- A v2.0 tentava PRODUZIR isolamento aqui, apagando a fixture. Não é
        -- possível: os Perfis estão selados e o schema recusa tanto a filha
        -- (guard BEFORE DELETE) quanto o pai (FK ON DELETE RESTRICT) — ver a
        -- nota "O QUE MUDOU NA v2.1" no cabeçalho. Este bloco agora PROVA o
        -- isolamento em vez de tentar fabricá-lo.
        --
        -- Quem produz o isolamento é o rollback da subtransação de vetor,
        -- logo abaixo. Este gate é a verificação independente disso: se por
        -- qualquer motivo o rollback não tiver ocorrido, o vetor seguinte
        -- não começa.
        --
        -- Na primeira iteração é redundante com a Seção 1, que acabou de
        -- provar ausência total de VEC2834* — e redundância aqui é barata.
        --
        -- As duas tabelas N:N não têm coluna de código: são contadas pelos
        -- pais VEC2834*. Como as FKs para o pai são NOT NULL e RESTRICT,
        -- filha órfã é impossível — provar pai zerado prova filha zerada. É
        -- o mesmo argumento que a Seção 1 já usa.
        SELECT string_agg(t || '=' || c, ', ' ORDER BY t) INTO v_residue FROM (
            SELECT 'card_edition_context_trait' AS t, count(*) AS c
              FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_profile', count(*)
              FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_profile_trait', count(*)
              FROM public.card_edition_context_profile_trait pt
             WHERE EXISTS (SELECT 1 FROM public.card_edition_context_profile pp
                            WHERE pp.id = pt.profile_id AND pp.code LIKE 'VEC2834%')
            UNION ALL SELECT 'card_edition_context_external_mapping', count(*)
              FROM public.card_edition_context_external_mapping WHERE normalized_token LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_external_mapping_trait', count(*)
              FROM public.card_edition_context_external_mapping_trait mt
             WHERE EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping mm
                            WHERE mm.id = mt.mapping_id AND mm.normalized_token LIKE 'VEC2834%')
            UNION ALL SELECT 'card_printing_trait', count(*)
              FROM public.card_printing_trait WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_profile', count(*)
              FROM public.card_printing_profile WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_profile_trait', count(*)
              FROM public.card_printing_profile_trait pt
             WHERE EXISTS (SELECT 1 FROM public.card_printing_profile pp
                            WHERE pp.id = pt.profile_id AND pp.code LIKE 'VEC2834%')
            UNION ALL SELECT 'card_printing_external_mapping', count(*)
              FROM public.card_printing_external_mapping WHERE normalized_token LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_external_mapping_trait', count(*)
              FROM public.card_printing_external_mapping_trait mt
             WHERE EXISTS (SELECT 1 FROM public.card_printing_external_mapping mm
                            WHERE mm.id = mt.mapping_id AND mm.normalized_token LIKE 'VEC2834%')
        ) q WHERE c > 0;

        IF v_residue IS NOT NULL THEN
            RAISE EXCEPTION 'S2 ABORT (%): residuo VEC2834* presente ANTES de montar a fixture deste vetor — %. O rollback da subtransacao do vetor anterior nao ocorreu; avaliar este vetor mediria estado herdado.',
                v_vec->>'id', v_residue;
        END IF;

        -- ###############################################################
        -- ###  INÍCIO DA SUBTRANSAÇÃO DO VETOR                        ###
        -- ###############################################################
        -- Tudo o que cria fixture física, sela, mede e avalia vive daqui
        -- até o `RAISE` do sentinel. Nada dentro deste bloco escreve em
        -- `_res2834`: os resultados vão para `v_acc`, que sobrevive ao
        -- rollback do bloco. Corpo NÃO reindentado de propósito — ver a
        -- NOTA DE LEITURA do cabeçalho.
        BEGIN

        -- ===============================================================
        -- 2.1 MONTAGEM DO ESTADO DO VETOR
        -- ===============================================================
        v_sym2uuid := '{}'::JSONB;
        v_uuid2sym := '{}'::JSONB;

        -- traits declarados
        FOR v_trait IN SELECT t FROM jsonb_array_elements(COALESCE(v_vec->'ec_traits','[]'::JSONB)) t LOOP
            INSERT INTO public.card_edition_context_trait (game_id, code, name, display_order, is_active)
            VALUES (v_game, 'VEC2834_' || (v_trait->>'id'), 'fixture ' || (v_trait->>'id'),
                    1000 + (SELECT count(*)::INT FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'),
                    (v_trait->>'is_active')::BOOLEAN)
            RETURNING id INTO v_trait_id;
            v_sym2uuid := v_sym2uuid || jsonb_build_object(v_trait->>'id', v_trait_id::TEXT);
            v_uuid2sym := v_uuid2sym || jsonb_build_object(v_trait_id::TEXT, v_trait->>'id');
        END LOOP;

        -- traits citados só em mappings/profiles (nascem ATIVOS)
        FOR v_tok IN
            SELECT DISTINCT x FROM (
                SELECT jsonb_array_elements_text(m->'traits') AS x
                  FROM jsonb_array_elements(COALESCE(v_vec->'ec_mappings','[]'::JSONB)) m
                UNION ALL
                SELECT jsonb_array_elements_text(pr->'traits')
                  FROM jsonb_array_elements(COALESCE(v_vec->'ec_profiles','[]'::JSONB)) pr
            ) q
        LOOP
            IF NOT (v_sym2uuid ? v_tok) THEN
                INSERT INTO public.card_edition_context_trait (game_id, code, name, display_order, is_active)
                VALUES (v_game, 'VEC2834_' || v_tok, 'fixture ' || v_tok,
                        1000 + (SELECT count(*)::INT FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'),
                        TRUE)
                RETURNING id INTO v_trait_id;
                v_sym2uuid := v_sym2uuid || jsonb_build_object(v_tok, v_trait_id::TEXT);
                v_uuid2sym := v_uuid2sym || jsonb_build_object(v_trait_id::TEXT, v_tok);
            END IF;
        END LOOP;

        -- profiles
        FOR v_prof IN SELECT pr FROM jsonb_array_elements(COALESCE(v_vec->'ec_profiles','[]'::JSONB)) pr LOOP
            SELECT ARRAY(SELECT (v_sym2uuid->>x)::UUID
                           FROM jsonb_array_elements_text(v_prof->'traits') x
                          ORDER BY (v_sym2uuid->>x)::UUID)
              INTO v_sig;

            INSERT INTO public.card_edition_context_profile
                (game_id, code, name, display_order, is_active)
            VALUES (v_game, 'VEC2834_' || (v_prof->>'id'), 'fixture ' || (v_prof->>'id'),
                    1000 + (SELECT count(*)::INT FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%'),
                    (v_prof->>'is_active')::BOOLEAN)
            RETURNING id INTO v_prof_id;

            INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
            SELECT v_prof_id, t, v_game FROM unnest(v_sig) t;

            v_sym2uuid := v_sym2uuid || jsonb_build_object(v_prof->>'id', v_prof_id::TEXT);
            v_uuid2sym := v_uuid2sym || jsonb_build_object(v_prof_id::TEXT, v_prof->>'id');
        END LOOP;

        -- ---------------------------------------------------------------
        -- SELO DO PROFILE DE EDITION CONTEXT — ESCOPADO, JANELA MÍNIMA
        -- ---------------------------------------------------------------
        -- Por que forçar: 2211 casa o Perfil por IGUALDADE EXATA —
        -- `ecp.traits_signature = v_ec_sig` — SEM fallback para a N:N. Com o
        -- selo deferido, `traits_signature` ainda é NULL e todo vetor cairia
        -- em NEEDS_REVIEW_NO_EC_PROFILE.
        --
        -- Por que ESCOPADO e restaurado: `SET CONSTRAINTS ALL IMMEDIATE`
        -- mudaria o regime de TODOS os constraint triggers — inclusive os do
        -- eixo 1, que o bloco 2.1-B ainda vai montar DENTRO desta mesma
        -- subtransação, e cujo selo precisa continuar deferido até a N:N
        -- existir. O contrato canônico da 2189 é este: IMMEDIATE -> provar ->
        -- DEFERRED, por trigger NOMEADO.
        --
        -- O `DEFERRED` logo abaixo é, além disso, redundante entre vetores: o
        -- aborto da subtransação de 2.3 já reverte qualquer SET CONSTRAINTS
        -- feito aqui. Redundância barata, e a única que vale dentro do vetor.
        SET CONSTRAINTS public.trg_cecp_seal IMMEDIATE;

        -- Prova: nenhum profile de fixture pode ficar sem assinatura selada.
        SELECT count(*) INTO v_unsealed
          FROM public.card_edition_context_profile
         WHERE code LIKE 'VEC2834%' AND traits_signature IS NULL;

        IF v_unsealed > 0 THEN
            RAISE EXCEPTION 'S2 ABORT (%): % profile(s) de Edition Context sem traits_signature selada apos SET CONSTRAINTS IMMEDIATE. 2211 casa o Perfil por igualdade exata e sem fallback — avaliar o vetor aqui mediria ausencia de perfil, nao o contrato.',
                v_vec->>'id', v_unsealed;
        END IF;

        -- Restaura ANTES de qualquer outro vetor criar profile.
        SET CONSTRAINTS public.trg_cecp_seal DEFERRED;

        -- mappings
        FOR v_map IN SELECT m FROM jsonb_array_elements(COALESCE(v_vec->'ec_mappings','[]'::JSONB)) m LOOP
            v_tok := split_part(p->'bindings'->'tokens'->>(v_map->>'token'), ' ', 1);

            INSERT INTO public.card_edition_context_external_mapping
                (game_id, asset_source_id, external_set_id, raw_field,
                 normalized_token, external_token, is_active)
            VALUES (v_game, v_src,
                    CASE WHEN v_map->>'scope' IS NULL THEN NULL ELSE 'VEC2834A' END,
                    v_map->>'raw_field', v_tok, v_tok,
                    (v_map->>'is_active')::BOOLEAN)
            RETURNING id INTO v_map_id;

            INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
            SELECT v_map_id, (v_sym2uuid->>x)::UUID, v_game
              FROM jsonb_array_elements_text(v_map->'traits') x;
        END LOOP;

        -- SELO DO MAPPING: deliberadamente NÃO forçado.
        -- 2211 lê a composição do mapping como
        --     COALESCE(m.traits_signature, ARRAY(SELECT mt.trait_id FROM ..._trait mt ...))
        -- — a N:N é o fallback, e o próprio comentário canônico da 2176 diz:
        -- "A N:N sempre foi a fonte da verdade; traits_signature e
        -- materializacao, e ela so existe no COMMIT." Forçar o selo aqui
        -- seria mexer no regime de um trigger sem que nada dependesse disso.

        -- ===============================================================
        -- 2.1-B  FIXTURE DE IMPRESSÃO — NOVA NA v2.0
        -- ===============================================================
        -- Criada DEPOIS da sentinela (Seção 1) e ANTES da medição. Local ao
        -- vetor: montada aqui, desfeita pelo sentinel de 2.3 e conferida
        -- pelo gate de zero resíduo de 2.4.
        --
        -- Três classes, conforme o `printing.state` DECLARADO:
        --
        --   RESOLVED_NO_PRINTING  -> nada a montar. O token do vetor não tem
        --                            routing de Impressão, e é isso que faz o
        --                            estado nascer terminal-sem-perfil.
        --
        --   RESOLVED_WITH_PROFILE -> trait ativo + profile ativo com assinatura
        --                            selada + mapping ativo apontando o trait.
        --
        --   UNRESOLVED            -> trait ativo + mapping ativo, e NENHUM
        --                            profile com aquela assinatura exata.
        --                            (ver 2.2, gate de E16)
        --
        -- O token que a Impressão consome:
        --   · E17 declara `printing.consumed_tokens` — usa-se o símbolo da
        --     fixture, porque o vetor existe para provar o destino DELE;
        --   · E3/E16 não declaram token de Impressão; usa-se c_pr_fix_token,
        --     técnico do runner, acrescentado ao `stamp` do raw. Assim o
        --     `residual_after_printing` da fixture é preservado letra por
        --     letra: TOK_CTX_A continua sendo do eixo 3, nunca vira token de
        --     Impressão.
        -- ===============================================================
        v_pr_state    := COALESCE(v_vec->'printing'->>'state', 'RESOLVED_NO_PRINTING');
        v_pr_token    := NULL;
        v_pr_trait_id := NULL;
        v_pr_prof_id  := NULL;

        IF v_pr_state <> 'RESOLVED_NO_PRINTING' THEN

            v_pr_token := CASE
                WHEN jsonb_array_length(COALESCE(v_vec->'printing'->'consumed_tokens','[]'::JSONB)) > 0
                THEN split_part(p->'bindings'->'tokens'->>(v_vec->'printing'->'consumed_tokens'->>0), ' ', 1)
                ELSE c_pr_fix_token
            END;

            INSERT INTO public.card_printing_trait (game_id, code, name, display_order, is_active)
            VALUES (v_game, 'VEC2834_PT', 'fixture printing trait', 1000, TRUE)
            RETURNING id INTO v_pr_trait_id;

            IF v_pr_state = 'RESOLVED_WITH_PROFILE' THEN
                INSERT INTO public.card_printing_profile (game_id, code, name, display_order, is_active)
                VALUES (v_game, 'VEC2834_PP_X', 'fixture printing profile', 1000, TRUE)
                RETURNING id INTO v_pr_prof_id;

                INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
                VALUES (v_pr_prof_id, v_pr_trait_id, v_game);
            END IF;

            INSERT INTO public.card_printing_external_mapping
                (game_id, asset_source_id, raw_field, normalized_token, external_token, is_active)
            VALUES (v_game, v_src, 'stamp', v_pr_token, v_pr_token, TRUE)
            RETURNING id INTO v_pr_map_id;

            INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
            VALUES (v_pr_map_id, v_pr_trait_id, v_game);

            -- -----------------------------------------------------------
            -- SELO DO PERFIL DE IMPRESSÃO — ESCOPADO, JANELA MÍNIMA
            -- -----------------------------------------------------------
            -- Por que forçar: compute_variant_residual_signature() casa o
            -- Perfil por IGUALDADE EXATA — `p.traits_signature = v_sig` —
            -- SEM fallback para a N:N. Deferido, `traits_signature` é NULL e
            -- E3/E17 jamais atingiriam RESOLVED_WITH_PROFILE.
            --
            -- Por que NÃO `SET CONSTRAINTS ALL`: isso trocaria o regime de
            -- TODOS os constraint triggers, inclusive os de mapping — que
            -- este runner deixa deliberadamente deferidos porque lê a N:N
            -- como fallback — e os do eixo 3 já montados nesta mesma
            -- subtransação. Padrão canônico da 2189, por trigger NOMEADO:
            -- IMMEDIATE -> provar -> DEFERRED.
            --
            -- A janela entre IMMEDIATE e DEFERRED é retilínea: só há SELECT e
            -- um RAISE que aborta a transação inteira. Nenhum CONTINUE,
            -- nenhum laço, nenhuma saída antecipada.
            IF v_pr_prof_id IS NOT NULL THEN
                SET CONSTRAINTS public.trg_card_printing_profile_seal IMMEDIATE;

                -- PROVA ESTRUTURAL — não fabricar estado inválido para
                -- conseguir PASS. Se o selo não pegou, o vetor mediria um
                -- perfil incompleto.
                SELECT traits_signature INTO v_pr_sealed
                  FROM public.card_printing_profile WHERE id = v_pr_prof_id;

                IF v_pr_sealed IS NULL OR v_pr_sealed IS DISTINCT FROM ARRAY[v_pr_trait_id] THEN
                    RAISE EXCEPTION 'S2 ABORT (%): selo do Perfil de Impressao sintetico nao aplicado ou divergente (selado: %, esperado: %). Nenhum vetor pode ser avaliado sobre fixture estruturalmente invalida.',
                        v_vec->>'id', v_pr_sealed, ARRAY[v_pr_trait_id];
                END IF;

                -- Restaura ANTES de qualquer outro vetor criar profile.
                SET CONSTRAINTS public.trg_card_printing_profile_seal DEFERRED;
            END IF;

            -- SELO DO MAPPING DE IMPRESSÃO: deliberadamente NÃO forçado.
            -- compute_variant_residual_signature() lê a composição como
            --     COALESCE(m.traits_signature, ARRAY(SELECT mt.trait_id ...))
            -- — mesmo fallback N:N do eixo 3. O runner não depende de
            -- `mapping.traits_signature`, então não há por que tocar no
            -- regime desse trigger.
        END IF;

        -- ===============================================================
        -- 2.2 EXECUÇÃO — um caso principal, mais os sub-casos
        -- ===============================================================
        FOR v_case IN
            SELECT c FROM (
                SELECT jsonb_build_object(
                           'label', v_vec->>'id',
                           'residual', v_vec->'residual_after_printing',
                           'raw_before', v_vec->'raw_before_printing',
                           'expected', v_vec->'expected') AS c
                 WHERE v_vec ? 'expected'
                UNION ALL
                SELECT jsonb_build_object(
                           'label', sc->>'label',
                           'residual', sc->'residual_after_printing',
                           'raw_before', v_vec->'raw_before_printing',
                           'expected', sc->'expected')
                  FROM jsonb_array_elements(COALESCE(v_vec->'sub_cases','[]'::JSONB)) sc
            ) q
        LOOP
            v_label := v_case->>'label';
            v_exp   := v_case->'expected';

            -- ---- residual pós-Impressão ESPERADO, vindo da fixture --------
            v_pre_sub := CASE WHEN v_case->'residual'->>'subtype' IS NULL THEN NULL
                              ELSE split_part(p->'bindings'->'tokens'->>(v_case->'residual'->>'subtype'), ' ', 1) END;
            SELECT ARRAY(SELECT split_part(p->'bindings'->'tokens'->>x, ' ', 1)
                           FROM jsonb_array_elements_text(COALESCE(v_case->'residual'->'stamp','[]'::JSONB)) x
                          ORDER BY 1)
              INTO v_pre_stamp;

            -- ---- raw_data de ENTRADA (pré-Impressão) ----------------------
            IF v_case->'raw_before' IS NOT NULL THEN
                -- E17: a fixture declara explicitamente o raw pré-Impressão.
                v_sub := CASE WHEN v_case->'raw_before'->>'subtype' IS NULL THEN NULL
                              ELSE split_part(p->'bindings'->'tokens'->>(v_case->'raw_before'->>'subtype'), ' ', 1) END;
                SELECT ARRAY(SELECT split_part(p->'bindings'->'tokens'->>x, ' ', 1)
                               FROM jsonb_array_elements_text(COALESCE(v_case->'raw_before'->'stamp','[]'::JSONB)) x
                              ORDER BY 1)
                  INTO v_stamp;
            ELSIF v_pr_state <> 'RESOLVED_NO_PRINTING' THEN
                -- E3/E16: residual da fixture + token técnico de Impressão.
                v_sub   := v_pre_sub;
                v_stamp := (SELECT ARRAY(SELECT s FROM unnest(v_pre_stamp || ARRAY[c_pr_fix_token]) s ORDER BY 1));
            ELSE
                -- 14 vetores: comportamento da v1.0, byte a byte.
                v_sub   := v_pre_sub;
                v_stamp := v_pre_stamp;
            END IF;

            v_raw := jsonb_build_object(
                         'type', 'normal',
                         'size', 'STANDARD'
                     )
                  || CASE WHEN v_sub IS NULL THEN '{}'::JSONB
                          ELSE jsonb_build_object('subtype', v_sub) END
                  || CASE WHEN cardinality(v_stamp) = 0 THEN '{}'::JSONB
                          ELSE jsonb_build_object('stamp', to_jsonb(v_stamp)) END;

            -- ===========================================================
            -- GATE DE IMPRESSÃO — MEDIR ANTES DE AVALIAR O EIXO 3
            -- ===========================================================
            -- internal.compute_variant_residual_signature() é o contrato do
            -- eixo 1 (3 argumentos, sem escopo). É a medição independente que
            -- torna a entrada declarada do vetor uma afirmação verificada.
            SELECT * INTO v_pre
              FROM internal.compute_variant_residual_signature(v_raw, v_game, v_src);

            SELECT ARRAY(SELECT s FROM unnest(COALESCE(v_pre.residual_stamp,'{}'::TEXT[])) s ORDER BY s)
              INTO v_got_pre_stamp;

            v_errs := '';

            -- (0) v2.2 — PROVA DO SCAFFOLD `type`.
            --     `type` NÃO é dimensão do contrato compartilhado do eixo 3:
            --     a fixture não o declara e nenhum `expected` o menciona. Ele
            --     existe porque compute_variant_residual_signature() o exige
            --     como campo do raw externo — foi a ausência dele que abortou
            --     a BATCH7-2834-LIVE-EXECUTION-01.
            --
            --     Acrescentar um campo técnico ao raw cria uma obrigação: provar
            --     que ele chegou ao contrato como esperado E que permaneceu
            --     INERTE. `normalize_external_catalog_value()` aplica upper(),
            --     então 'normal' tem de voltar como 'NORMAL' no residual — nem
            --     consumido por routing, nem transformado em outra coisa.
            --
            --     É FAIL DO CASO, não exceção estrutural: uma divergência aqui
            --     é um resultado a ser reportado pela Seção 3, como qualquer
            --     outro, e não um aborto que esconderia os demais vetores.
            IF v_pre.residual_type IS DISTINCT FROM 'NORMAL' THEN
                v_errs := v_errs || format(
                    'PRINTING_TYPE_SCAFFOLD_MISMATCH: residual_type %s != NORMAL; o scaffold tecnico type=normal nao permaneceu inerte; ',
                    v_pre.residual_type);
            END IF;

            -- (1) o estado medido corresponde ao DECLARADO?
            IF v_pr_state = 'UNRESOLVED' THEN
                -- E16. `UNRESOLVED` na fixture é ABSTRAÇÃO de "Printing não
                -- terminal", não um literal do vocabulário SQL do eixo 1. O
                -- gate normativo é a NÃO-PERTINÊNCIA ao conjunto terminal.
                -- Exigir o literal criaria um estado que a 2211 não define e
                -- acoplaria o runner a um nome que a fixture nunca prometeu.
                IF v_pre.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') THEN
                    v_errs := v_errs || format(
                        'PRINTING_FIXTURE_MISMATCH: vetor declara Printing NAO terminal; medido %s, que e terminal; ',
                        v_pre.printing_state);
                END IF;
            ELSE
                IF v_pre.printing_state IS DISTINCT FROM v_pr_state THEN
                    v_errs := v_errs || format('PRINTING_FIXTURE_MISMATCH: declarado %s, medido %s; ',
                                               v_pr_state, v_pre.printing_state);
                END IF;
            END IF;

            -- (2) RESOLVED_WITH_PROFILE exige perfil não nulo, e que seja o
            --     perfil sintético — não um perfil de produção por acidente.
            IF v_pr_state = 'RESOLVED_WITH_PROFILE' THEN
                IF v_pre.printing_profile_id IS NULL THEN
                    v_errs := v_errs || 'PRINTING_FIXTURE_MISMATCH: RESOLVED_WITH_PROFILE com printing_profile_id NULL; ';
                ELSIF v_pre.printing_profile_id IS DISTINCT FROM v_pr_prof_id THEN
                    v_errs := v_errs || format('PRINTING_FIXTURE_MISMATCH: profile medido %s difere do sintetico PP_X %s; ',
                                               v_pre.printing_profile_id, v_pr_prof_id);
                END IF;
            END IF;

            -- (3) o residual pós-Impressão é EXATAMENTE o da fixture?
            --     Este é o predicado que prova o encadeamento: o que o eixo 1
            --     consumiu saiu do residual, e o que não é dele permaneceu.
            IF v_pre.residual_subtype IS DISTINCT FROM v_pre_sub THEN
                v_errs := v_errs || format('PRINTING_RESIDUAL_MISMATCH: subtype pos-Printing %s != %s; ',
                                           v_pre.residual_subtype, v_pre_sub);
            END IF;
            IF v_got_pre_stamp IS DISTINCT FROM v_pre_stamp THEN
                v_errs := v_errs || format('PRINTING_RESIDUAL_MISMATCH: stamp pos-Printing %s != %s; ',
                                           v_got_pre_stamp, v_pre_stamp);
            END IF;

            -- (4) E17 — predicado explícito de consumo.
            --     A armadilha do vetor é um mapping de Edition Context ATIVO
            --     para TOK_PRINTING. Se o eixo 3 lesse a assinatura BRUTA,
            --     consumiria os dois tokens. Provar aqui, ANTES do eixo 3, que
            --     TOK_PRINTING saiu e TOK_CTX_A ficou é o que transforma o
            --     resultado do eixo 3 em consequência demonstrada.
            IF v_case->'raw_before' IS NOT NULL AND v_pr_token IS NOT NULL THEN
                IF v_pr_token = ANY(v_got_pre_stamp) THEN
                    v_errs := v_errs || format('PRINTING_CONSUMPTION_MISMATCH: token de Impressao %s permanece no residual %s; ',
                                               v_pr_token, v_got_pre_stamp);
                END IF;
                IF NOT (v_pre_stamp <@ v_got_pre_stamp AND v_got_pre_stamp <@ v_pre_stamp) THEN
                    v_errs := v_errs || format('PRINTING_CONSUMPTION_MISMATCH: residual de Impressao %s nao preserva os tokens do eixo 3 %s; ',
                                               v_got_pre_stamp, v_pre_stamp);
                END IF;
            END IF;

            IF v_errs <> '' THEN
                -- FAIL é RESULTADO, nunca exceção. Vai para `v_acc` e chega
                -- intacto à Seção 3 — o sentinel não o consome nem o mascara.
                v_acc := v_acc || jsonb_build_array(jsonb_build_object(
                    'vector_id', v_vec->>'id', 'label', v_label,
                    'status', 'FAIL', 'detail', v_errs));
                CONTINUE;
            END IF;

            -- ===========================================================
            -- EIXO 3 — sobre o MESMO raw_data que acabou de ser medido
            -- ===========================================================
            SELECT * INTO v_ax
              FROM internal.resolve_variant_row_axes(
                       v_raw, v_game, v_src,
                       CASE WHEN v_vec->>'job_scope' IS NULL THEN NULL ELSE 'VEC2834A' END);

            -- coerência entre os dois contratos: o eixo 1 tem de dizer a mesma
            -- coisa nas duas chamadas.
            IF v_ax.printing_state IS DISTINCT FROM v_pre.printing_state THEN
                v_acc := v_acc || jsonb_build_array(jsonb_build_object(
                    'vector_id', v_vec->>'id', 'label', v_label, 'status', 'FAIL',
                    'detail', format('AXIS_CONTRACT_DIVERGENCE: printing_state %s no contrato de 3 eixos != %s no contrato de Impressao, para o MESMO raw_data.',
                                     v_ax.printing_state, v_pre.printing_state)));
                CONTINUE;
            END IF;

            -- ---- tradução uuid -> símbolo, para comparar com a fixture ----
            v_got_state   := v_ax.edition_context_state;
            v_got_profile := CASE WHEN v_ax.edition_context_profile_id IS NULL THEN NULL
                                  ELSE COALESCE(v_uuid2sym->>(v_ax.edition_context_profile_id::TEXT),
                                                '<<UUID DESCONHECIDO>>') END;
            SELECT ARRAY(SELECT COALESCE(v_uuid2sym->>(t::TEXT), '<<UUID DESCONHECIDO>>')
                           FROM unnest(COALESCE(v_ax.edition_context_trait_ids,'{}'::UUID[])) t
                          ORDER BY 1)
              INTO v_got_traits;
            v_got_sub   := v_ax.residual_subtype;
            SELECT ARRAY(SELECT s FROM unnest(COALESCE(v_ax.residual_stamp,'{}'::TEXT[])) s ORDER BY s)
              INTO v_got_stamp;
            v_got_emits := v_ax.printing_state IN ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE')
                       AND v_ax.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE');

            SELECT ARRAY(SELECT x FROM jsonb_array_elements_text(v_exp->'edition_context_trait_ids') x ORDER BY 1)
              INTO v_exp_traits;
            SELECT ARRAY(SELECT split_part(p->'bindings'->'tokens'->>x, ' ', 1)
                           FROM jsonb_array_elements_text(v_exp->'residual_stamp') x ORDER BY 1)
              INTO v_exp_stamp;
            v_exp_sub := CASE WHEN v_exp->>'residual_subtype' IS NULL THEN NULL
                              ELSE split_part(p->'bindings'->'tokens'->>(v_exp->>'residual_subtype'), ' ', 1) END;

            -- A comparação é SEMPRE contra o `expected` da fixture. Não existe
            -- expected local escrito neste arquivo — se existisse, o runner
            -- estaria se avaliando contra a própria opinião.
            v_errs := '';
            IF v_got_state   IS DISTINCT FROM (v_exp->>'edition_context_state')
                THEN v_errs := v_errs || format('estado: %s != %s; ', v_got_state, v_exp->>'edition_context_state'); END IF;
            IF v_got_profile IS DISTINCT FROM (v_exp->>'edition_context_profile')
                THEN v_errs := v_errs || format('profile: %s != %s; ', v_got_profile, v_exp->>'edition_context_profile'); END IF;
            IF v_got_traits  IS DISTINCT FROM v_exp_traits
                THEN v_errs := v_errs || format('traits: %s != %s; ', v_got_traits, v_exp_traits); END IF;
            IF v_got_sub     IS DISTINCT FROM v_exp_sub
                THEN v_errs := v_errs || format('res_subtype: %s != %s; ', v_got_sub, v_exp_sub); END IF;
            IF v_got_stamp   IS DISTINCT FROM v_exp_stamp
                THEN v_errs := v_errs || format('res_stamp: %s != %s; ', v_got_stamp, v_exp_stamp); END IF;
            IF v_got_emits   IS DISTINCT FROM (v_exp->>'edge_emits_axis_keys')::BOOLEAN
                THEN v_errs := v_errs || format('emits: %s != %s; ', v_got_emits, v_exp->>'edge_emits_axis_keys'); END IF;

            -- `detail` de um PASS é o estado do eixo 3 — é essa string que a
            -- Seção 3 usa para medir cobertura de vocabulário. Contrato
            -- preservado byte a byte na v2.1.
            v_acc := v_acc || jsonb_build_array(jsonb_build_object(
                'vector_id', v_vec->>'id', 'label', v_label,
                'status', CASE WHEN v_errs = '' THEN 'PASS' ELSE 'FAIL' END,
                'detail', CASE WHEN v_errs = '' THEN v_got_state ELSE v_errs END));
        END LOOP;

        -- ===============================================================
        -- 2.3 SENTINEL — DESFAZER A FIXTURE FÍSICA DESTE VETOR
        -- ===============================================================
        -- Última instrução do corpo da subtransação, sem nenhuma condição em
        -- volta. Todos os casos do vetor já foram medidos e já estão em
        -- `v_acc`. O `CONTINUE` do laço de casos continua o laço INTERNO e
        -- o fim dele cai exatamente aqui — não existe caminho que alcance o
        -- `END` do bloco sem passar por este RAISE.
        --
        -- SQLSTATE 'P2834' é exclusivo hoje — a classe 'P2' não é atribuída
        -- pelo PostgreSQL (a do PL/pgSQL é 'P0'). Mas SQLSTATE sozinho é uma
        -- garantia sobre o presente: nada impede que código futuro deste
        -- pacote reutilize 'P2834' por engano. Por isso a identidade do
        -- sentinel é a MENSAGEM, determinística e específica do vetor, fixada
        -- em `v_sent_expected` antes de a subtransação abrir.
        --
        -- O formato é `RAISE EXCEPTION '%', v_sent_expected`: a string de
        -- formato é o literal '%', então `SQLERRM` fica EXATAMENTE igual a
        -- `v_sent_expected`, caractere por caractere — o que permite comparar
        -- por igualdade em vez de por prefixo ou substring.
        --
        -- NÃO é tratamento de erro. É o único mecanismo capaz de remover uma
        -- fixture cujos Perfis estão selados sem violar selo, guard ou FK.
        RAISE EXCEPTION '%', v_sent_expected USING ERRCODE = 'P2834';

        EXCEPTION
            -- SOMENTE o sentinel. Sem `WHEN OTHERS`: qualquer exceção real —
            -- S2 ABORT de selo, violação de constraint, erro nas funções sob
            -- teste — não é capturada aqui, propaga e aborta o 2834 inteiro.
            WHEN SQLSTATE 'P2834' THEN
                -- FAIL-CLOSED. Igualdade exata contra a mensagem esperada
                -- DESTE vetor. Um 'P2834' vindo de qualquer outro ponto —
                -- inclusive de um vetor diferente — não corresponde e é
                -- re-levantado intacto por `RAISE;`, abortando o runner.
                IF SQLERRM IS DISTINCT FROM v_sent_expected THEN
                    RAISE;
                END IF;

                v_sent_hits := v_sent_hits + 1;
        END;
        -- ###############################################################
        -- ###  FIM DA SUBTRANSAÇÃO DO VETOR                           ###
        -- ###############################################################
        -- Neste ponto, pela semântica documentada do PL/pgSQL: todo o estado
        -- de banco escrito dentro do bloco foi desfeito, e as variáveis
        -- locais — `v_acc` em particular — mantêm os valores que tinham
        -- quando o sentinel foi levantado.
        --
        -- Os `SET CONSTRAINTS` escopados dos dois selos também ficam para
        -- trás: eles são revertidos pelo aborto da subtransação, além de já
        -- terem sido restaurados a DEFERRED dentro dos próprios blocos. A
        -- iteração seguinte começa no regime DEFERRED, que é o que 2.1 e
        -- 2.1-B pressupõem ao inserir cabeçalho antes da N:N.

        -- ---- prova de que o sentinel foi realmente alcançado -----------
        -- Se o bloco tivesse terminado por qualquer outro caminho, o handler
        -- não teria rodado e o contador ficaria para trás do ordinal.
        IF v_sent_hits <> v_vec_ord THEN
            RAISE EXCEPTION 'S2 ABORT (%): sentinel nao capturado para este vetor (% sentinel(s) para % vetor(es) iniciado(s)). A fixture fisica pode nao ter sido desfeita.',
                v_vec->>'id', v_sent_hits, v_vec_ord;
        END IF;

        -- ---- o vetor precisa ter medido alguma coisa -------------------
        -- A Seção 0 (G4) já prova que todo vetor da fixture deriva ao menos
        -- um caso. Um `v_acc` vazio aqui significaria que o laço de casos
        -- não rodou — falha silenciosa que a v2.0 não teria como acusar,
        -- porque a contagem global só aparece na Seção 3.
        IF jsonb_array_length(v_acc) = 0 THEN
            RAISE EXCEPTION 'S2 ABORT (%): nenhum caso medido para este vetor.', v_vec->>'id';
        END IF;

        -- ===============================================================
        -- 2.4 GATE DE ZERO RESÍDUO — SAÍDA DO VETOR
        -- ===============================================================
        -- Prova independente de que o rollback da subtransação removeu TODA
        -- a fixture física, nas dez tabelas sintéticas. É o predicado que
        -- substitui os DELETEs da v2.0: em vez de mandar apagar e torcer, o
        -- runner verifica e falha alto. Roda ANTES do próximo vetor e antes
        -- de qualquer escrita em `_res2834`.
        SELECT string_agg(t || '=' || c, ', ' ORDER BY t) INTO v_residue FROM (
            SELECT 'card_edition_context_trait' AS t, count(*) AS c
              FROM public.card_edition_context_trait WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_profile', count(*)
              FROM public.card_edition_context_profile WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_profile_trait', count(*)
              FROM public.card_edition_context_profile_trait pt
             WHERE EXISTS (SELECT 1 FROM public.card_edition_context_profile pp
                            WHERE pp.id = pt.profile_id AND pp.code LIKE 'VEC2834%')
            UNION ALL SELECT 'card_edition_context_external_mapping', count(*)
              FROM public.card_edition_context_external_mapping WHERE normalized_token LIKE 'VEC2834%'
            UNION ALL SELECT 'card_edition_context_external_mapping_trait', count(*)
              FROM public.card_edition_context_external_mapping_trait mt
             WHERE EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping mm
                            WHERE mm.id = mt.mapping_id AND mm.normalized_token LIKE 'VEC2834%')
            UNION ALL SELECT 'card_printing_trait', count(*)
              FROM public.card_printing_trait WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_profile', count(*)
              FROM public.card_printing_profile WHERE code LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_profile_trait', count(*)
              FROM public.card_printing_profile_trait pt
             WHERE EXISTS (SELECT 1 FROM public.card_printing_profile pp
                            WHERE pp.id = pt.profile_id AND pp.code LIKE 'VEC2834%')
            UNION ALL SELECT 'card_printing_external_mapping', count(*)
              FROM public.card_printing_external_mapping WHERE normalized_token LIKE 'VEC2834%'
            UNION ALL SELECT 'card_printing_external_mapping_trait', count(*)
              FROM public.card_printing_external_mapping_trait mt
             WHERE EXISTS (SELECT 1 FROM public.card_printing_external_mapping mm
                            WHERE mm.id = mt.mapping_id AND mm.normalized_token LIKE 'VEC2834%')
        ) q WHERE c > 0;

        IF v_residue IS NOT NULL THEN
            RAISE EXCEPTION 'S2 ABORT (%): a subtransacao foi desfeita mas restou fixture VEC2834* — %. Isolamento entre vetores NAO demonstrado.',
                v_vec->>'id', v_residue;
        END IF;

        -- ===============================================================
        -- 2.5 MATERIALIZAÇÃO — só agora, e fora da subtransação
        -- ===============================================================
        -- `_res2834` foi criada fora do bloco e nunca é escrita dentro dele.
        -- Por isso estas linhas sobrevivem até a Seção 3 enquanto a fixture
        -- física já não existe.
        INSERT INTO _res2834 (vector_id, label, status, detail)
        SELECT r->>'vector_id', r->>'label', r->>'status', r->>'detail'
          FROM jsonb_array_elements(v_acc) r;

    END LOOP;

    -- Fecho global: um sentinel deliberado por vetor, nem mais nem menos.
    IF v_sent_hits <> v_vec_ord THEN
        RAISE EXCEPTION 'S2 ABORT: % sentinel(s) capturado(s) para % vetor(es) percorrido(s).',
            v_sent_hits, v_vec_ord;
    END IF;

    RAISE NOTICE 'S2 OK — % vetor(es) medidos, % subtransacao(oes) desfeita(s) pelo sentinel, zero residuo em cada saida.',
        v_vec_ord, v_sent_hits;
END
$s2$;


-- ===========================================================================
-- SEÇÃO 3 — GATE FINAL
-- ===========================================================================
-- Desde a v2.0 o gate deixou de ser "nenhum FAIL" e passou a ser "a fixture
-- inteira foi provada". Sete condições, todas obrigatórias:
--
--   (1) zero FAIL;
--   (2) zero SKIP — SKIP não é resultado admissível;
--   (3) casos PASS == casos derivados da fixture (dinâmico);
--   (4) casos executados == casos derivados da fixture (dinâmico);
--   (5) todo vector_id do roster com ao menos um caso PASS (nominal);
--   (6) vector_ids distintos == vetores da fixture;
--   (7) cobertura de vocabulário completa.
--
-- As condições (3)/(4) são o que impede a regressão que a v1.0 permitia:
-- contar só FAIL deixava passar um runner que simplesmente não rodou parte da
-- fixture.
--
-- Nada aqui muda na v2.1. A Seção 3 lê `_res2834` exatamente como antes — a
-- subtransação por vetor alterou COMO as linhas chegam até aqui, nunca o que
-- elas significam nem o rigor com que são cobradas.
-- ===========================================================================
DO $s3$
DECLARE
    v_pass INTEGER; v_fail INTEGER; v_skip INTEGER; v_rows INTEGER;
    v_vec_seen INTEGER;
    v_n_vectors INTEGER; v_n_cases INTEGER; v_n_vocab INTEGER;
    v_cov INTEGER;
    v_det  TEXT;
    v_miss TEXT;
    v_miss_vec TEXT;
    v_gap  TEXT := '';
BEGIN
    SELECT n_vectors, n_cases, n_vocab INTO v_n_vectors, v_n_cases, v_n_vocab FROM _expect2834;

    SELECT count(*) FILTER (WHERE status='PASS'),
           count(*) FILTER (WHERE status='FAIL'),
           count(*) FILTER (WHERE status='SKIP'),
           count(*),
           count(DISTINCT vector_id)
      INTO v_pass, v_fail, v_skip, v_rows, v_vec_seen
      FROM _res2834;

    RAISE NOTICE '=== 2834 v2.2 — % PASS / % FAIL / % SKIP em % caso(s), % vetor(es) ===',
        v_pass, v_fail, v_skip, v_rows, v_vec_seen;
    RAISE NOTICE '=== esperado pela fixture: % caso(s), % vetor(es), % estado(s) ===',
        v_n_cases, v_n_vectors, v_n_vocab;

    FOR v_det IN SELECT format('%s %-6s %s', status, label, detail) FROM _res2834 ORDER BY vector_id, label LOOP
        RAISE NOTICE '%', v_det;
    END LOOP;

    -- cobertura de vocabulário, medida sobre o que PASSOU.
    SELECT count(*) INTO v_cov
      FROM jsonb_array_elements_text((SELECT payload->'vocabulary' FROM _vec2834)) w
     WHERE w IN (SELECT detail FROM _res2834 WHERE status='PASS');

    SELECT string_agg(w, ', ') INTO v_miss
      FROM jsonb_array_elements_text((SELECT payload->'vocabulary' FROM _vec2834)) w
     WHERE w NOT IN (SELECT detail FROM _res2834 WHERE status='PASS');

    RAISE NOTICE '=== cobertura de vocabulario: %/% ===', v_cov, v_n_vocab;

    IF v_fail > 0 THEN
        v_gap := v_gap || format('%s caso(s) FAIL; ', v_fail);
    END IF;

    IF v_skip > 0 THEN
        v_gap := v_gap || format('%s caso(s) SKIP — a v2.0 nao admite SKIP: todo vetor da fixture tem de ser montavel e medido; ', v_skip);
    END IF;

    IF v_pass IS DISTINCT FROM v_n_cases THEN
        v_gap := v_gap || format('%s caso(s) PASS para %s derivado(s) da fixture — nem todo caso esta PASS; ',
                                 v_pass, v_n_cases);
    END IF;

    IF v_rows IS DISTINCT FROM v_n_cases THEN
        v_gap := v_gap || format('executou %s caso(s) para %s derivado(s) da fixture; ', v_rows, v_n_cases);
    END IF;

    -- Cobertura do roster NOMINAL, não por contagem. Um vetor executado duas
    -- vezes e outro nenhuma daria a mesma contagem e passaria despercebido.
    SELECT string_agg(x, ', ') INTO v_miss_vec
      FROM jsonb_array_elements_text((SELECT payload->'roster' FROM _vec2834)) x
     WHERE x NOT IN (SELECT vector_id FROM _res2834 WHERE status='PASS');

    IF v_miss_vec IS NOT NULL THEN
        v_gap := v_gap || format('vector_id(s) do roster sem nenhum caso PASS: %s; ', v_miss_vec);
    END IF;

    IF v_vec_seen IS DISTINCT FROM v_n_vectors THEN
        v_gap := v_gap || format('cobriu %s vector_id(s) de %s; ', v_vec_seen, v_n_vectors);
    END IF;

    IF v_miss IS NOT NULL THEN
        v_gap := v_gap || format('estados sem nenhum caso PASS: %s; ', v_miss);
    END IF;

    IF v_gap <> '' THEN
        RAISE EXCEPTION '2834 FALHOU: %. Paridade Edge x SQL NAO demonstrada — rollout do eixo 3 bloqueado. Cobertura parcial nunca e verde.', v_gap;
    END IF;

    RAISE NOTICE '2834 OK — fixture compartilhada provada integralmente: %/% casos, %/% vetores, %/% estados, 0 FAIL, 0 SKIP.',
        v_pass, v_n_cases, v_vec_seen, v_n_vectors, v_cov, v_n_vocab;
END
$s3$;

ROLLBACK;
