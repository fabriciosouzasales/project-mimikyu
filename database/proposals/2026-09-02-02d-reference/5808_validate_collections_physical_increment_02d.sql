/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5808 - Validate Collections Physical Increment 02D (PROPOSTA)
Versão......: 2.4 (v2.0 em COLLECTIONS-PHYSICAL-INCREMENT-02D-
               STAGING-REVISION-01 — v1.0 continha SQL não executável,
               confirmado por tentativa real contra o Supabase: uso
               inválido de SAVEPOINT dentro de blocos DO/PLpgSQL,
               assinaturas incorretas de create_storage_container()/
               add_physical_cards(), e um padrão array_agg()+LIMIT que
               não limita o conjunto agregado; v2.1 em
               -STAGING-FINAL-FIX-01 — três correções de correção de
               teste, ver itens 8-10 abaixo: Caso U reexecutava uma
               desalocação já feita, Caso Z aceitava qualquer exceção
               como PASS, Caso X podia dar falso PASS por ausência de
               função; v2.2 em -IMPLEMENTATION-01 — execução real contra
               Supabase revelou que o catálogo real só tem Card Sets
               carregados para 1 Game (Pokémon TCG); o segundo Game real
               existente (Lorcana) tem 9 Expansions cadastradas mas 0
               Card Set. O fixture do Caso K exigia >= 2 Games com Card
               Set REAL e abortava a transação inteira antes de
               qualquer Caso rodar. Decisão de Fabrício: não carregar
               Card Sets de Lorcana no catálogo real — é divergência de
               FIXTURE, não do produto. Correção, ver item 12 abaixo;
               v2.3 em -IMPLEMENTATION-01 — segunda divergência real na
               mesma execução: CS1/CS2 eram escolhidos por
               `ORDER BY cs.id LIMIT 1` dentro do Game G1, sem checar se
               o Card Set escolhido tem Card Variant carregada — vários
               Card Sets reais de Pokémon TCG têm Card (linha) mas 0
               Card Variant (ex.: SWSH5/Estilos de Batalha, 183 Cards,
               0 variantes). CS2 caiu exatamente num desses e o fixture
               de Physical Cards abortou. Correção, ver item 13 abaixo
               — mesma categoria de divergência do item 12 (catálogo
               real mais incompleto do que a seleção por ID
               presumia), mesma política aplicada: fixture passa a
               EXIGIR explicitamente >= 1 Card Variant real na condição
               de seleção, em vez de descobrir a ausência só depois,
               por exceção; v2.4 em -IMPLEMENTATION-01 — terceira
               divergência real na mesma execução, desta vez um bug de
               mecânica PL/pgSQL nunca antes executado de fato contra o
               Supabase (mesma categoria das corrigidas em
               -STAGING-REVISION-01): Casos G/I/W inlinavam subqueries
               `(SELECT ... FROM fixture_ctx/fixture_storage_id)`
               DENTRO do bloco BEGIN, DEPOIS de
               `set_config('role','authenticated',true)` — como as
               tabelas de fixture são TEMP TABLE, pertencem à role que
               abriu a sessão, não a 'authenticated' impersonada, e a
               subquery falha com "permission denied for table
               fixture_ctx". Todo o resto do script (Casos A-F, H, J-V,
               X, Z) já seguia corretamente o padrão de resolver esses
               valores em variável na cláusula DECLARE — que roda ANTES
               do BEGIN e portanto antes do set_config de role, ainda
               sob a role de conexão. Correção, ver item 14 abaixo —
               mesmo padrão já usado em todo o resto do arquivo,
               nenhuma leitura de fixture depois do role switch)
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02D-
               MODELING-01/-REVISION-01/-FINAL-01/-STAGING-REVISION-01)

Descrição...:
Bateria de validação funcional do Incremento 02D. Cobre os 24 itens do
plano de validação de -MODELING-FINAL-01 (seção 10) mais o caso novo
do blocker fechado em -STAGING-REVISION-01 (item 1), mapeados abaixo
em Casos A-Z. Só será executada de fato numa futura rodada
-IMPLEMENTATION-01, depois de 5049-5066 aplicadas ao Supabase real.

Mudanças estruturais desta reescrita (v2.0), todas de mecânica SQL —
NENHUMA decisão conceitual foi reaberta:

1. SAVEPOINT/ROLLBACK TO SAVEPOINT removidos de todo bloco DO. Postgres
   não permite comandos de controle de transação dentro de PL/pgSQL
   (ERROR: unsupported transaction command in PL/pgSQL). Em vez disso,
   cada caso usa um bloco BEGIN ... EXCEPTION WHEN OTHERS ... END do
   próprio PL/pgSQL — a linguagem já cria uma subtransação implícita
   nesse ponto e a desfaz automaticamente ao capturar a exceção, sem
   precisar de nenhum comando SQL de controle de transação explícito.
   SET CONSTRAINTS continua sendo usado como statement solto (não é
   comando de controle de transação — é um utility command comum,
   permitido em PL/pgSQL como qualquer INSERT/UPDATE/DELETE).
2. create_storage_container() corrigido para a assinatura real de 1
   argumento (p_name text) — RETURNS TABLE(id, name, created_at).
   Confirmado em database/schema/5022 (CANÔNICA).
3. add_physical_cards() removido inteiramente dos fixtures. Contrato
   real é add_physical_cards(p_items jsonb), não uuid[]. Para não
   depender do shape exato do payload jsonb — e por ser mais simples
   de auditar — os Physical Cards de fixture são inseridos diretamente
   em public.physical_card (mesma técnica já usada nos Casos
   estruturais/bypass B/D/E/F/G/H/I/R), reaproveitando um Language real
   do catálogo. Confirmado em database/schema/5010/5012 (CANÔNICAS).
4. Todo padrão `SELECT array_agg(x) ... LIMIT N` corrigido para
   `SELECT array_agg(x) FROM (SELECT ... LIMIT N) q` — LIMIT depois de
   um agregado sem GROUP BY nunca limita o conjunto agregado (a query
   produz uma única linha de saída; LIMIT N não filtra as linhas de
   ENTRADA do agregado).
5. Caso E simplificado — removida a linha executável
   `UPDATE collection SET mode = 'REFERENCE_BASED'` que o próprio
   comentário original já reconhecia como incorreta (falharia por
   5061). Só resta o cenário real, por INSERT direto.
6. Caso X fortalecido: checa has_function_privilege() tanto para anon
   quanto para authenticated sobre toda função de trigger/helper
   (espera false nas duas), e confirma explicitamente que as duas RPCs
   novas (5065/5066) têm authenticated=true e anon=false — não apenas
   ausência de non-enumeration.
7. Caso Z novo, cobrindo o blocker fechado em -STAGING-REVISION-01,
   item 1: uma Collection REFERENCE_BASED recebe sua primeira
   Allocation ANTES de qualquer Collection Reference existir (possível
   porque a checagem de elegibilidade é um LEFT JOIN — sem Reference
   ainda, nada a checar) — reference_locked_at materializa — só então
   se tenta criar a Collection Reference -> deve FAIL imediatamente
   (checagem nova em 5055/5056, não diferida).
8. Todo caso que usa SET CONSTRAINTS ... IMMEDIATE agora reverte
   explicitamente para DEFERRED ao final do bloco DO (nos dois ramos,
   sucesso e exceção) — sem isso, uma vez setado IMMEDIATE numa
   transação, o modo permanece IMMEDIATE para os casos seguintes que
   dependem do mesmo nome de constraint, contaminando resultados
   posteriores.
9. (-STAGING-FINAL-FIX-01) Caso U corrigido: a v2.0 chamava
   reactivate_collection()/deallocate_physical_cards_from_collection()/
   archive_collection() presumindo que a Allocation do Caso N ainda
   estava pendente — mas o Caso P já a desalocou totalmente, e o Caso T
   já arquivou a Collection. Reexecutar o deallocate ali quebraria o
   teste pelo motivo errado (fail-closed de 5047 sobre uma carta já
   desalocada). Corrigido: o caso agora só COMPROVA a pré-condição já
   satisfeita (ARCHIVED + Reference existente + zero Allocations, com
   FAIL explícito se não bater) e então chama delete_collection()
   diretamente, confirmando as três exclusões por CASCADE
   separadamente (Collection, Collection Reference, Card Set Reference).
10. (-STAGING-FINAL-FIX-01) Caso Z fortalecido: não aceita mais
   qualquer EXCEPTION como PASS — verifica que SQLERRM contém
   especificamente 'reference_locked_at already set' (o guard novo de
   5056), não qualquer outra falha incidental.
11. (-STAGING-FINAL-FIX-01) Caso X fortalecido: conta explicitamente a
   EXISTÊNCIA das 8 funções de trigger/helper e das 2 RPCs esperadas
   antes de avaliar grants — evita o falso PASS que ocorreria se uma
   função estivesse simplesmente ausente (um JOIN filtrado por nome
   contra pg_proc não detecta ausência por si só, só teria 0 linhas por
   falta de sujeito).
12. (-IMPLEMENTATION-01) Fixture do segundo Game (Caso K) corrigido:
   antes exigia um segundo Game com >= 1 Card Set REAL já carregado no
   catálogo — execução real revelou que só Pokémon TCG tem Card Sets
   carregados hoje (Lorcana existe, com 9 Expansions reais, mas 0 Card
   Set). Corrigido para: (a) aceitar qualquer segundo Game real,
   independente de já ter Card Set; (b) se o segundo Game não tiver
   nenhum Card Set real, reaproveitar uma Expansion real desse Game e
   inserir SOMENTE 1 Card Set sintético mínimo, exclusivamente DENTRO
   desta transação — nunca sobrevive ao ROLLBACK final do script. Não é
   carga de catálogo real (decisão explícita de Fabrício: "NÃO carregar
   Card Sets de Lorcana no catálogo real" — isso é divergência de
   FIXTURE de teste, não do produto, e por isso não deve gerar carga
   operacional permanente).
13. (-IMPLEMENTATION-01) Seleção de card_set_cs1_id/card_set_cs2_id
   corrigida: escolhia por `ORDER BY cs.id LIMIT 1` sem checar se o
   Card Set tem Card Variant carregada — vários Card Sets reais de
   Pokémon TCG têm Card (linha) mas 0 Card Variant. Corrigido para
   exigir `EXISTS (... JOIN card_variant ...)` na própria condição de
   seleção, em vez de descobrir a ausência só depois por
   RAISE EXCEPTION.
14. (-IMPLEMENTATION-01) Casos G/I/W corrigidos: resolviam owner/game/
   storage/card_set via subquery direta contra fixture_ctx/fixture_
   storage_id DEPOIS de já terem chamado
   set_config('role','authenticated',true) — como essas tabelas são
   TEMP TABLE (pertencem à role de conexão, não a 'authenticated'
   impersonada), a subquery falhava com "permission denied for table
   fixture_ctx". Corrigido movendo essas leituras para a cláusula
   DECLARE de cada bloco DO (executada antes do BEGIN, logo antes de
   qualquer set_config de role) — mesmo padrão já usado em todos os
   outros Casos do arquivo.

Mapa Caso -> item do plano de validação:
  A -> "OPEN_CURATION sem Reference -> PASS"
  B -> "OPEN_CURATION com Reference -> FAIL"
  C -> "REFERENCE_BASED completa -> PASS"
  D -> "REFERENCE_BASED sem Reference -> FAIL"
  E -> "CARD_SET parent sem subtype -> FAIL"
  F -> "subtype delete standalone -> FAIL"
  G -> "reparent collection_reference -> FAIL"
  H -> "alterar reference_kind -> FAIL"
  I -> "reparent subtype -> FAIL"
  J -> "Card Set mesmo Game -> PASS"
  K -> "Card Set outro Game -> FAIL"
  L -> "trocar Card Set antes do lock -> PASS"
  M -> "após lock -> FAIL"
  N -> "first Allocation materializa reference_locked_at"
  O -> "OPEN_CURATION nunca materializa reference_locked_at"
  P -> "deallocate total preserva lock"
  Q -> "carta fora do Set -> FAIL" (camada RPC)
  R -> "carta fora do Set -> FAIL" (camada estrutural, bypass da RPC)
  S -> "lote misto -> zero writes"
  T -> "ARCHIVED bloqueia mudanças" (config standalone)
  U -> "DELETE Collection ARCHIVED com Reference e zero Allocations -> comportamento real confirmado"
  V -> "DELETE Collection com Reference e zero Allocations -> PASS/CASCADE" (ACTIVE)
  W -> "non-enumeration"
  X -> "RLS/grants"
  Y -> "zero residue" (verificação final, fora da transação principal)
  Z -> "Reference nasce após reference_locked_at já materializado -> FAIL" (blocker de -STAGING-REVISION-01, item 1)

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

BEGIN;

-- ============================================================
-- FIXTURES
-- ============================================================

CREATE TEMP TABLE test_results (
    seq        SERIAL PRIMARY KEY,
    case_label TEXT NOT NULL,
    status     TEXT NOT NULL,
    detail     TEXT
);

CREATE OR REPLACE FUNCTION pg_temp.log_result(p_case TEXT, p_status TEXT, p_detail TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE sql AS $$
    INSERT INTO test_results (case_label, status, detail) VALUES (p_case, p_status, p_detail);
$$;

-- Owner A: reaproveita o primeiro User real com Inventory já existente
-- (mesmo critério de robustez de 5807 — nenhum dado sintético de User).
CREATE TEMP TABLE fixture_ctx AS
SELECT
    inv.owner_user_id AS owner_a_id,
    inv.id             AS inventory_a_id
FROM public.inventory inv
LIMIT 1;

DO $$
BEGIN
    IF (SELECT count(*) FROM fixture_ctx) = 0 THEN
        RAISE EXCEPTION 'nenhum Inventory real encontrado — 5808 exige ao menos 1 Owner com Inventory já existente';
    END IF;
END;
$$;

-- Owner B: um segundo User real com Inventory, distinto de Owner A —
-- necessário para os Casos W/X (não-enumeração/RLS).
ALTER TABLE fixture_ctx ADD COLUMN owner_b_id UUID;
UPDATE fixture_ctx SET owner_b_id = (
    SELECT inv.owner_user_id FROM public.inventory inv
    WHERE inv.owner_user_id <> (SELECT owner_a_id FROM fixture_ctx)
    LIMIT 1
);

DO $$
BEGIN
    IF (SELECT owner_b_id FROM fixture_ctx) IS NULL THEN
        RAISE EXCEPTION 'nenhum segundo Owner real encontrado — Casos W/X exigem >= 2 Owners com Inventory';
    END IF;
END;
$$;

-- Game G1 (com >= 2 Card Sets reais) e Game G2 (diferente de G1, com
-- >= 1 Card Set real) — reaproveitando catálogo permanente existente.
ALTER TABLE fixture_ctx ADD COLUMN game_g1_id UUID;
ALTER TABLE fixture_ctx ADD COLUMN card_set_cs1_id UUID;
ALTER TABLE fixture_ctx ADD COLUMN card_set_cs2_id UUID;
ALTER TABLE fixture_ctx ADD COLUMN game_g2_id UUID;
ALTER TABLE fixture_ctx ADD COLUMN card_set_other_game_id UUID;

UPDATE fixture_ctx SET game_g1_id = (
    SELECT ex.game_id
    FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    GROUP BY ex.game_id
    HAVING count(DISTINCT cs.id) >= 2
    LIMIT 1
);

DO $$
BEGIN
    IF (SELECT game_g1_id FROM fixture_ctx) IS NULL THEN
        RAISE EXCEPTION 'nenhum Game com >= 2 Card Sets reais encontrado — 5808 exige catálogo mínimo já carregado';
    END IF;
END;
$$;

-- (-IMPLEMENTATION-01, item 13) CS1/CS2 agora exigem explicitamente
-- >= 1 Card Variant real já carregada — vários Card Sets reais de
-- Pokémon TCG têm Card (linha) mas 0 Card Variant, então escolher só
-- por ORDER BY cs.id arriscava cair num Card Set inútil para o
-- fixture (confirmado: aconteceu com CS2 nesta execução real).
UPDATE fixture_ctx SET card_set_cs1_id = (
    SELECT cs.id FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE ex.game_id = (SELECT game_g1_id FROM fixture_ctx)
      AND EXISTS (
          SELECT 1 FROM public.card ca1
          JOIN public.card_variant cv1 ON cv1.card_id = ca1.id
          WHERE ca1.card_set_id = cs.id
      )
    ORDER BY cs.id LIMIT 1
);

UPDATE fixture_ctx SET card_set_cs2_id = (
    SELECT cs.id FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE ex.game_id = (SELECT game_g1_id FROM fixture_ctx)
      AND cs.id <> (SELECT card_set_cs1_id FROM fixture_ctx)
      AND EXISTS (
          SELECT 1 FROM public.card ca2
          JOIN public.card_variant cv2 ON cv2.card_id = ca2.id
          WHERE ca2.card_set_id = cs.id
      )
    ORDER BY cs.id LIMIT 1
);

-- (-IMPLEMENTATION-01, item 12) Não exige mais que o segundo Game já
-- tenha Card Set REAL carregado — só que exista como Game. Execução
-- real mostrou que apenas Pokémon TCG tem Card Sets carregados hoje.
UPDATE fixture_ctx SET game_g2_id = (
    SELECT g.id FROM public.game g
    WHERE g.id <> (SELECT game_g1_id FROM fixture_ctx)
    LIMIT 1
);

DO $$
BEGIN
    IF (SELECT game_g2_id FROM fixture_ctx) IS NULL THEN
        RAISE EXCEPTION 'nenhum segundo Game encontrado — Caso K exige >= 2 Games cadastrados (Card Set pode ser sintético, só dentro da transação)';
    END IF;
END;
$$;

-- Tenta reaproveitar um Card Set REAL do segundo Game. Se não existir
-- nenhum (caso confirmado do catálogo atual: Lorcana tem Expansions
-- reais mas 0 Card Set), reaproveita uma Expansion REAL desse Game e
-- insere só 1 Card Set SINTÉTICO mínimo, exclusivamente dentro desta
-- transação — nunca sobrevive ao ROLLBACK final do script (item 12).
UPDATE fixture_ctx SET card_set_other_game_id = (
    SELECT cs.id FROM public.card_set cs
    JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE ex.game_id = (SELECT game_g2_id FROM fixture_ctx)
    ORDER BY cs.id LIMIT 1
);

DO $$
DECLARE
    v_game_g2      UUID := (SELECT game_g2_id FROM fixture_ctx);
    v_expansion_id UUID;
    v_card_set_id  UUID;
BEGIN
    IF (SELECT card_set_other_game_id FROM fixture_ctx) IS NOT NULL THEN
        RETURN; -- já existe Card Set real do segundo Game, nada a fazer
    END IF;

    SELECT ex.id INTO v_expansion_id
    FROM public.expansion ex
    WHERE ex.game_id = v_game_g2
    ORDER BY ex.id LIMIT 1;

    IF v_expansion_id IS NULL THEN
        RAISE EXCEPTION 'segundo Game não tem nenhuma Expansion real — impossível construir Card Set nem sintético';
    END IF;

    INSERT INTO public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    VALUES (v_expansion_id, 'TEST02D', 'TEST-02D Synthetic Card Set (fixture, nunca sobrevive ao ROLLBACK)', 'REGULAR', 999999, 1, 1)
    RETURNING id INTO v_card_set_id;

    UPDATE fixture_ctx SET card_set_other_game_id = v_card_set_id;
END;
$$;

-- Storage Container (Default Storage) de Owner A — assinatura real:
-- create_storage_container(p_name text).
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_storage_id UUID;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT id INTO v_storage_id FROM public.create_storage_container('TEST-02D-Storage');

    RESET ROLE;

    CREATE TEMP TABLE fixture_storage_id AS SELECT v_storage_id AS storage_id;
END;
$$;

-- Physical Cards de Owner A: inseridas DIRETAMENTE em physical_card
-- (não via add_physical_cards(), cujo contrato real é jsonb — ver nota
-- 3 do cabeçalho). 4 sob CS1 (pc_cs1_a/b/c/d — elegíveis para
-- Reference de CS1) + 1 sob CS2 (pc_cs2_a — inelegível, usado nos
-- Casos Q/R/S).
DO $$
DECLARE
    v_inv_a       UUID := (SELECT inventory_a_id FROM fixture_ctx);
    v_cs1         UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_cs2         UUID := (SELECT card_set_cs2_id FROM fixture_ctx);
    v_lang        UUID;
    v_variant_cs1 UUID[];
    v_variant_cs2 UUID;
    v_pc_cs1_a    UUID;
    v_pc_cs1_b    UUID;
    v_pc_cs1_c    UUID;
    v_pc_cs1_d    UUID;
    v_pc_cs2_a    UUID;
BEGIN
    SELECT id INTO v_lang FROM public.language LIMIT 1;
    IF v_lang IS NULL THEN
        RAISE EXCEPTION 'nenhum Language real encontrado — 5808 exige catálogo mínimo já carregado';
    END IF;

    SELECT array_agg(x.id) INTO v_variant_cs1
    FROM (
        SELECT cv.id
        FROM public.card_variant cv
        JOIN public.card ca ON ca.id = cv.card_id
        WHERE ca.card_set_id = v_cs1
        LIMIT 5
    ) x;

    SELECT x.id INTO v_variant_cs2
    FROM (
        SELECT cv.id
        FROM public.card_variant cv
        JOIN public.card ca ON ca.id = cv.card_id
        WHERE ca.card_set_id = v_cs2
        LIMIT 1
    ) x;

    IF v_variant_cs1 IS NULL OR array_length(v_variant_cs1, 1) < 4 THEN
        RAISE EXCEPTION 'card_set_cs1 não tem Card Variants suficientes (>= 4) para os fixtures';
    END IF;

    IF v_variant_cs2 IS NULL THEN
        RAISE EXCEPTION 'card_set_cs2 não tem nenhuma Card Variant para o fixture inelegível';
    END IF;

    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_variant_cs1[1], v_lang, v_inv_a) RETURNING id INTO v_pc_cs1_a;
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_variant_cs1[2], v_lang, v_inv_a) RETURNING id INTO v_pc_cs1_b;
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_variant_cs1[3], v_lang, v_inv_a) RETURNING id INTO v_pc_cs1_c;
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_variant_cs1[4], v_lang, v_inv_a) RETURNING id INTO v_pc_cs1_d;
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (v_variant_cs2, v_lang, v_inv_a) RETURNING id INTO v_pc_cs2_a;

    CREATE TEMP TABLE fixture_pc AS
    SELECT v_pc_cs1_a AS pc_cs1_a, v_pc_cs1_b AS pc_cs1_b, v_pc_cs1_c AS pc_cs1_c,
           v_pc_cs1_d AS pc_cs1_d, v_pc_cs2_a AS pc_cs2_a;
END;
$$;

-- ============================================================
-- CASO A — OPEN_CURATION sem Reference -> PASS
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_coll_id UUID;
    v_ref_count INT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT id INTO v_coll_id
    FROM public.create_collection(v_game, 'TEST-02D-OpenCuration-A', NULL, v_storage);

    SELECT count(*) INTO v_ref_count FROM public.collection_reference WHERE collection_id = v_coll_id;

    RESET ROLE;

    IF v_ref_count = 0 THEN
        PERFORM pg_temp.log_result('A', 'PASS', 'OPEN_CURATION criada com 0 Collection Reference, conforme esperado');
    ELSE
        PERFORM pg_temp.log_result('A', 'FAIL', format('esperava 0 references, encontrou %s', v_ref_count));
    END IF;
END;
$$;

-- ============================================================
-- CASO B — OPEN_CURATION com Reference -> FAIL (diferida)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_coll_id UUID;
    v_ref_id  UUID;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    SELECT id INTO v_coll_id FROM public.create_collection(v_game, 'TEST-02D-OpenCuration-B', NULL, v_storage);
    RESET ROLE;

    BEGIN
        INSERT INTO public.collection_reference (collection_id, reference_kind)
        VALUES (v_coll_id, 'CARD_SET') RETURNING id INTO v_ref_id;
        INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
        VALUES (v_ref_id, v_cs1);

        SET CONSTRAINTS trg_collection_reference_consistency IMMEDIATE;
        SET CONSTRAINTS trg_collection_card_set_reference_consistency IMMEDIATE;

        PERFORM pg_temp.log_result('B', 'FAIL', 'exceção esperada não foi levantada — OPEN_CURATION aceitou Reference');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('B', 'PASS', SQLERRM);
    END;

    SET CONSTRAINTS trg_collection_reference_consistency DEFERRED;
    SET CONSTRAINTS trg_collection_card_set_reference_consistency DEFERRED;
END;
$$;

-- ============================================================
-- CASO C — REFERENCE_BASED completa (criação atômica) -> PASS
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_row     RECORD;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT * INTO v_row
    FROM public.create_reference_based_card_set_collection(v_game, 'TEST-02D-RefBased-C', NULL, v_storage, v_cs1);

    RESET ROLE;

    CREATE TEMP TABLE fixture_collection_c AS SELECT v_row.id AS collection_id;

    IF v_row.mode = 'REFERENCE_BASED' AND v_row.card_set_id = v_cs1 THEN
        PERFORM pg_temp.log_result('C', 'PASS', 'Collection + Reference + Card Set Reference criadas atomicamente');
    ELSE
        PERFORM pg_temp.log_result('C', 'FAIL', 'retorno inesperado da RPC de criação atômica');
    END IF;
END;
$$;

-- ============================================================
-- CASO D — REFERENCE_BASED sem Reference -> FAIL (diferida, lado collection)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
BEGIN
    BEGIN
        INSERT INTO public.collection (owner_user_id, game_id, name, default_storage_container_id, mode)
        VALUES (v_owner_a, v_game, 'TEST-02D-Bypass-D', v_storage, 'REFERENCE_BASED');

        SET CONSTRAINTS trg_collection_reference_presence IMMEDIATE;

        PERFORM pg_temp.log_result('D', 'FAIL', 'exceção esperada não foi levantada — REFERENCE_BASED sem Reference foi aceita');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('D', 'PASS', SQLERRM);
    END;

    SET CONSTRAINTS trg_collection_reference_presence DEFERRED;
END;
$$;

-- ============================================================
-- CASO E — CARD_SET parent sem subtype -> FAIL (diferida)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_coll_id UUID;
BEGIN
    BEGIN
        INSERT INTO public.collection (owner_user_id, game_id, name, default_storage_container_id, mode)
        VALUES (v_owner_a, v_game, 'TEST-02D-Bypass-E', v_storage, 'REFERENCE_BASED')
        RETURNING id INTO v_coll_id;

        INSERT INTO public.collection_reference (collection_id, reference_kind)
        VALUES (v_coll_id, 'CARD_SET');
        -- Nenhum INSERT em collection_card_set_reference — o Caso a
        -- provar.

        SET CONSTRAINTS trg_collection_reference_presence IMMEDIATE;
        SET CONSTRAINTS trg_collection_reference_consistency IMMEDIATE;

        PERFORM pg_temp.log_result('E', 'FAIL', 'exceção esperada não foi levantada — CARD_SET parent sem subtype foi aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('E', 'PASS', SQLERRM);
    END;

    SET CONSTRAINTS trg_collection_reference_presence DEFERRED;
    SET CONSTRAINTS trg_collection_reference_consistency DEFERRED;
END;
$$;

-- ============================================================
-- CASO F — subtype delete standalone -> FAIL (diferida, blocker fix do 02D)
-- ============================================================
DO $$
DECLARE
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_ref_id  UUID;
BEGIN
    SELECT id INTO v_ref_id FROM public.collection_reference WHERE collection_id = v_coll_id;

    BEGIN
        DELETE FROM public.collection_card_set_reference WHERE collection_reference_id = v_ref_id;

        SET CONSTRAINTS trg_collection_card_set_reference_consistency IMMEDIATE;

        PERFORM pg_temp.log_result('F', 'FAIL', 'exceção esperada não foi levantada — subtype removido isoladamente foi aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('F', 'PASS', SQLERRM);
    END;

    SET CONSTRAINTS trg_collection_card_set_reference_consistency DEFERRED;
END;
$$;

-- ============================================================
-- CASO G — reparent collection_reference -> FAIL (imediata)
-- ============================================================
DO $$
DECLARE
    v_ref_id     UUID := (SELECT id FROM public.collection_reference WHERE collection_id = (SELECT collection_id FROM fixture_collection_c));
    v_owner_a    UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game       UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage    UUID := (SELECT storage_id FROM fixture_storage_id);
    v_other_coll UUID;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    SELECT id INTO v_other_coll FROM public.create_collection(v_game, 'TEST-02D-Reparent-G', NULL, v_storage);
    RESET ROLE;

    BEGIN
        UPDATE public.collection_reference SET collection_id = v_other_coll WHERE id = v_ref_id;
        PERFORM pg_temp.log_result('G', 'FAIL', 'exceção esperada não foi levantada — reparent de collection_reference aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('G', 'PASS', SQLERRM);
    END;
END;
$$;

-- ============================================================
-- CASO H — alterar reference_kind -> FAIL (imediata)
-- Nesta rodada, só 'CARD_SET' é valor legal (chk_collection_
-- reference_kind) — a tentativa já falha no CHECK, antes de alcançar
-- o trigger de imutabilidade (5051). O trigger passa a ser o
-- mecanismo relevante quando 'POKEDEX' existir como segundo valor
-- legal; documentado aqui para não reivindicar prova do que não foi
-- provado.
-- ============================================================
DO $$
DECLARE
    v_ref_id UUID := (SELECT id FROM public.collection_reference WHERE collection_id = (SELECT collection_id FROM fixture_collection_c));
BEGIN
    BEGIN
        UPDATE public.collection_reference SET reference_kind = 'POKEDEX' WHERE id = v_ref_id;
        PERFORM pg_temp.log_result('H', 'FAIL', 'exceção esperada não foi levantada — mudança de reference_kind aceita');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('H', 'PASS', SQLERRM || ' (bloqueado hoje pelo CHECK chk_collection_reference_kind, não pelo trigger — só 1 valor legal existe)');
    END;
END;
$$;

-- ============================================================
-- CASO I — reparent subtype -> FAIL (imediata)
-- ============================================================
DO $$
DECLARE
    v_original_ref UUID := (SELECT id FROM public.collection_reference WHERE collection_id = (SELECT collection_id FROM fixture_collection_c));
    v_owner_a      UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game         UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage      UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs2          UUID := (SELECT card_set_cs2_id FROM fixture_ctx);
    v_other_ref    UUID;
    v_other_coll   UUID;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    SELECT id INTO v_other_coll FROM public.create_reference_based_card_set_collection(v_game, 'TEST-02D-Reparent-I', NULL, v_storage, v_cs2);
    RESET ROLE;

    SELECT id INTO v_other_ref FROM public.collection_reference WHERE collection_id = v_other_coll;

    BEGIN
        UPDATE public.collection_card_set_reference
        SET collection_reference_id = v_other_ref
        WHERE collection_reference_id = v_original_ref;
        PERFORM pg_temp.log_result('I', 'FAIL', 'exceção esperada não foi levantada — reparent de subtype aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('I', 'PASS', SQLERRM);
    END;
END;
$$;

-- ============================================================
-- CASO J — Card Set mesmo Game -> PASS (já coberto pelo Caso C,
-- reconfirmado aqui explicitamente como item próprio do plano)
-- ============================================================
DO $$
BEGIN
    IF (SELECT status FROM test_results WHERE case_label = 'C' ORDER BY seq DESC LIMIT 1) = 'PASS' THEN
        PERFORM pg_temp.log_result('J', 'PASS', 'reconfirmação do Caso C — Card Set do mesmo Game aceito');
    ELSE
        PERFORM pg_temp.log_result('J', 'FAIL', 'Caso C não passou — ver detalhe do Caso C');
    END IF;
END;
$$;

-- ============================================================
-- CASO K — Card Set outro Game -> FAIL
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs_other UUID := (SELECT card_set_other_game_id FROM fixture_ctx);
    v_status  TEXT;
    v_detail  TEXT;
BEGIN
    -- log_result é chamado só DEPOIS de RESET ROLE nesta rodada
    -- (-STAGING-REVISION-01): a tabela/função pg_temp pertencem à role
    -- que abriu a sessão, não a 'authenticated' — chamar log_result
    -- enquanto impersonando 'authenticated' arriscaria erro de
    -- permissão sobre objetos pg_temp sem GRANT explícito. O resultado
    -- é capturado em variável local e só logado depois do RESET ROLE.
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    BEGIN
        PERFORM public.create_reference_based_card_set_collection(v_game, 'TEST-02D-OtherGame-K', NULL, v_storage, v_cs_other);
        v_status := 'FAIL';
        v_detail := 'exceção esperada não foi levantada — Card Set de outro Game aceito';
    EXCEPTION WHEN OTHERS THEN
        v_status := 'PASS';
        v_detail := SQLERRM;
    END;

    RESET ROLE;

    PERFORM pg_temp.log_result('K', v_status, v_detail);
END;
$$;

-- ============================================================
-- CASO L — trocar Card Set antes do lock -> PASS
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_cs2     UUID := (SELECT card_set_cs2_id FROM fixture_ctx);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_row     RECORD;
    v_status  TEXT;
    v_detail  TEXT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT * INTO v_row FROM public.set_collection_card_set_reference(v_coll_id, v_cs2);

    IF v_row.card_set_id = v_cs2 THEN
        v_status := 'PASS';
        v_detail := 'card_set_id trocado com sucesso antes do lock';
    ELSE
        v_status := 'FAIL';
        v_detail := 'card_set_id não foi atualizado conforme esperado';
    END IF;

    -- devolve para CS1, estado esperado pelos casos seguintes
    PERFORM public.set_collection_card_set_reference(v_coll_id, v_cs1);

    RESET ROLE;

    PERFORM pg_temp.log_result('L', v_status, v_detail);
END;
$$;

-- ============================================================
-- CASO N — first Allocation materializa reference_locked_at
-- (executado antes do Caso M de propósito — M depende do lock já
-- existir)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_pc      UUID := (SELECT pc_cs1_a FROM fixture_pc);
    v_locked_at TIMESTAMPTZ;
    v_alloc_created_at TIMESTAMPTZ;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT created_at INTO v_alloc_created_at
    FROM public.allocate_physical_cards_to_collection(v_coll_id, ARRAY[v_pc]);

    RESET ROLE;

    SELECT reference_locked_at INTO v_locked_at FROM public.collection WHERE id = v_coll_id;

    IF v_locked_at IS NOT NULL AND v_locked_at = v_alloc_created_at THEN
        PERFORM pg_temp.log_result('N', 'PASS', format('reference_locked_at materializado = %s', v_locked_at));
    ELSE
        PERFORM pg_temp.log_result('N', 'FAIL', format('reference_locked_at = %s, esperado %s', v_locked_at, v_alloc_created_at));
    END IF;
END;
$$;

-- ============================================================
-- CASO M — após lock, trocar Card Set -> FAIL
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_cs2     UUID := (SELECT card_set_cs2_id FROM fixture_ctx);
    v_status  TEXT;
    v_detail  TEXT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    BEGIN
        PERFORM public.set_collection_card_set_reference(v_coll_id, v_cs2);
        v_status := 'FAIL';
        v_detail := 'exceção esperada não foi levantada — troca de Card Set após o lock aceita';
    EXCEPTION WHEN OTHERS THEN
        v_status := 'PASS';
        v_detail := SQLERRM;
    END;

    RESET ROLE;

    PERFORM pg_temp.log_result('M', v_status, v_detail);
END;
$$;

-- ============================================================
-- CASO O — OPEN_CURATION nunca materializa reference_locked_at
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_coll_id UUID;
    v_pc      UUID := (SELECT pc_cs1_b FROM fixture_pc);
    v_locked_at TIMESTAMPTZ;
    v_started_at TIMESTAMPTZ;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT id INTO v_coll_id FROM public.create_collection(v_game, 'TEST-02D-OpenAlloc-O', NULL, v_storage);
    PERFORM public.allocate_physical_cards_to_collection(v_coll_id, ARRAY[v_pc]);

    RESET ROLE;

    SELECT reference_locked_at, started_at INTO v_locked_at, v_started_at
    FROM public.collection WHERE id = v_coll_id;

    IF v_locked_at IS NULL AND v_started_at IS NOT NULL THEN
        PERFORM pg_temp.log_result('O', 'PASS', 'started_at definido, reference_locked_at permanece NULL em OPEN_CURATION');
    ELSE
        PERFORM pg_temp.log_result('O', 'FAIL', format('reference_locked_at = %s, started_at = %s', v_locked_at, v_started_at));
    END IF;
END;
$$;

-- ============================================================
-- CASO P — deallocate total preserva lock
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_pc      UUID := (SELECT pc_cs1_a FROM fixture_pc);
    v_locked_before TIMESTAMPTZ;
    v_locked_after  TIMESTAMPTZ;
BEGIN
    SELECT reference_locked_at INTO v_locked_before FROM public.collection WHERE id = v_coll_id;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    PERFORM public.deallocate_physical_cards_from_collection(v_coll_id, ARRAY[v_pc]);
    RESET ROLE;

    SELECT reference_locked_at INTO v_locked_after FROM public.collection WHERE id = v_coll_id;

    IF v_locked_before IS NOT NULL AND v_locked_after = v_locked_before THEN
        PERFORM pg_temp.log_result('P', 'PASS', 'reference_locked_at preservado após deallocate total');
    ELSE
        PERFORM pg_temp.log_result('P', 'FAIL', format('antes=%s depois=%s', v_locked_before, v_locked_after));
    END IF;
END;
$$;

-- ============================================================
-- CASO Q — carta fora do Set -> FAIL (camada RPC)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_pc_cs2  UUID := (SELECT pc_cs2_a FROM fixture_pc);
    v_status  TEXT;
    v_detail  TEXT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    BEGIN
        PERFORM public.allocate_physical_cards_to_collection(v_coll_id, ARRAY[v_pc_cs2]);
        v_status := 'FAIL';
        v_detail := 'exceção esperada não foi levantada — carta fora do Card Set aceita pela RPC';
    EXCEPTION WHEN OTHERS THEN
        v_status := 'PASS';
        v_detail := SQLERRM;
    END;

    RESET ROLE;

    PERFORM pg_temp.log_result('Q', v_status, v_detail);
END;
$$;

-- ============================================================
-- CASO R — carta fora do Set -> FAIL (camada estrutural, bypass da RPC)
-- ============================================================
DO $$
DECLARE
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_pc_cs2  UUID := (SELECT pc_cs2_a FROM fixture_pc);
BEGIN
    BEGIN
        INSERT INTO public.collection_allocation (physical_card_id, collection_id) VALUES (v_pc_cs2, v_coll_id);
        PERFORM pg_temp.log_result('R', 'FAIL', 'exceção esperada não foi levantada — INSERT direto bypassando a RPC aceito');
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp.log_result('R', 'PASS', SQLERRM);
    END;
END;
$$;

-- ============================================================
-- CASO S — lote misto -> zero writes
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_pc_cs1  UUID := (SELECT pc_cs1_c FROM fixture_pc);
    v_pc_cs2  UUID := (SELECT pc_cs2_a FROM fixture_pc);
    v_count_before INT;
    v_count_after  INT;
BEGIN
    SELECT count(*) INTO v_count_before FROM public.collection_allocation WHERE collection_id = v_coll_id;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    BEGIN
        PERFORM public.allocate_physical_cards_to_collection(v_coll_id, ARRAY[v_pc_cs1, v_pc_cs2]);
    EXCEPTION WHEN OTHERS THEN
        NULL; -- esperado: RPC falha e não escreve nada, provado abaixo pela contagem
    END;

    RESET ROLE;

    SELECT count(*) INTO v_count_after FROM public.collection_allocation WHERE collection_id = v_coll_id;

    IF v_count_after = v_count_before THEN
        PERFORM pg_temp.log_result('S', 'PASS', format('lote misto rejeitado, %s Allocations antes e depois (fail-closed)', v_count_before));
    ELSE
        PERFORM pg_temp.log_result('S', 'FAIL', format('antes=%s depois=%s — inserção parcial detectada', v_count_before, v_count_after));
    END IF;
END;
$$;

-- ============================================================
-- CASO T — ARCHIVED bloqueia mudanças (config standalone)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_cs2     UUID := (SELECT card_set_cs2_id FROM fixture_ctx);
    v_status  TEXT;
    v_detail  TEXT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    PERFORM public.archive_collection(v_coll_id);

    BEGIN
        -- card_set_id já está travado por reference_locked_at (Caso N)
        -- de qualquer forma; o objetivo aqui é confirmar que a
        -- rejeição também acontece com a Collection ARCHIVED. Ambos os
        -- guards (lock e ARCHIVED) são válidos para este caso — o que
        -- importa é a rejeição em si.
        PERFORM public.set_collection_card_set_reference(v_coll_id, v_cs2);
        v_status := 'FAIL';
        v_detail := 'exceção esperada não foi levantada — mudança de configuração em Collection ARCHIVED aceita';
    EXCEPTION WHEN OTHERS THEN
        v_status := 'PASS';
        v_detail := SQLERRM;
    END;

    RESET ROLE;

    PERFORM pg_temp.log_result('T', v_status, v_detail);
END;
$$;

-- ============================================================
-- CASO U — DELETE Collection ARCHIVED com Reference e zero Allocations
-- -> comportamento real confirmado (delete_collection() nunca exigiu
-- ACTIVE; CASCADE deve funcionar mesmo assim)
--
-- CORREÇÃO (-STAGING-FINAL-FIX-01): a versão anterior chamava
-- reactivate_collection()/deallocate_physical_cards_from_collection()/
-- archive_collection() aqui, presumindo que a Collection ainda tinha a
-- Allocation do Caso N pendente. Isso está errado: o Caso P já
-- desalocou pc_cs1_a TOTALMENTE, e o Caso T já arquivou a Collection.
-- Ao chegar aqui a Collection JÁ está ARCHIVED com ZERO Allocations —
-- tentar desalocar pc_cs1_a de novo violaria o contrato fail-closed de
-- 5047 (carta não alocada a esta Collection -> FAIL), quebrando o
-- teste por um motivo errado. A pré-condição correta (ARCHIVED +
-- Reference existente + zero Allocations) já está satisfeita pelos
-- Casos T/P — este caso só precisa COMPROVAR essa pré-condição
-- explicitamente e então chamar delete_collection() diretamente.
-- ============================================================
DO $$
DECLARE
    v_coll_id UUID := (SELECT collection_id FROM fixture_collection_c);
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_lifecycle_before TEXT;
    v_alloc_count_before INT;
    v_ref_id  UUID;
    v_deleted_id UUID;
    v_coll_count_after INT;
    v_ref_count_after INT;
    v_subtype_count_after INT;
BEGIN
    SELECT col.lifecycle_status INTO v_lifecycle_before
    FROM public.collection col WHERE col.id = v_coll_id;

    SELECT count(*) INTO v_alloc_count_before
    FROM public.collection_allocation WHERE collection_id = v_coll_id;

    SELECT id INTO v_ref_id FROM public.collection_reference WHERE collection_id = v_coll_id;

    IF v_lifecycle_before IS DISTINCT FROM 'ARCHIVED' OR v_alloc_count_before <> 0 OR v_ref_id IS NULL THEN
        PERFORM pg_temp.log_result('U', 'FAIL', format(
            'pré-condição do Caso U não satisfeita: lifecycle_status=%s (esperado ARCHIVED), allocation_count=%s (esperado 0), collection_reference_id=%s (esperado not null)',
            v_lifecycle_before, v_alloc_count_before, v_ref_id));
        RETURN;
    END IF;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT id INTO v_deleted_id FROM public.delete_collection(v_coll_id);

    RESET ROLE;

    SELECT count(*) INTO v_coll_count_after FROM public.collection WHERE id = v_coll_id;
    SELECT count(*) INTO v_ref_count_after FROM public.collection_reference WHERE id = v_ref_id;
    SELECT count(*) INTO v_subtype_count_after FROM public.collection_card_set_reference WHERE collection_reference_id = v_ref_id;

    IF v_deleted_id = v_coll_id AND v_coll_count_after = 0 AND v_ref_count_after = 0 AND v_subtype_count_after = 0 THEN
        PERFORM pg_temp.log_result('U', 'PASS', 'pré-condição comprovada (ARCHIVED, zero Allocations, Reference existente); Collection excluída; Collection Reference excluída por CASCADE; Card Set Reference excluída por CASCADE');
    ELSE
        PERFORM pg_temp.log_result('U', 'FAIL', format('deleted_id=%s collection_count_after=%s reference_count_after=%s subtype_count_after=%s', v_deleted_id, v_coll_count_after, v_ref_count_after, v_subtype_count_after));
    END IF;
END;
$$;

-- ============================================================
-- CASO V — DELETE Collection ACTIVE com Reference e zero Allocations
-- -> PASS/CASCADE
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_coll_id UUID;
    v_ref_id  UUID;
    v_subtype_count_after INT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);

    SELECT id INTO v_coll_id FROM public.create_reference_based_card_set_collection(v_game, 'TEST-02D-DeleteActive-V', NULL, v_storage, v_cs1);
    SELECT id INTO v_ref_id FROM public.collection_reference WHERE collection_id = v_coll_id;
    PERFORM public.delete_collection(v_coll_id);

    RESET ROLE;

    SELECT count(*) INTO v_subtype_count_after FROM public.collection_card_set_reference WHERE collection_reference_id = v_ref_id;

    IF NOT EXISTS (SELECT 1 FROM public.collection WHERE id = v_coll_id) AND v_subtype_count_after = 0 THEN
        PERFORM pg_temp.log_result('V', 'PASS', 'Collection ACTIVE com Reference e zero Allocations excluída; CASCADE completo');
    ELSE
        PERFORM pg_temp.log_result('V', 'FAIL', 'Collection ou subtipo ainda existem após delete_collection()');
    END IF;
END;
$$;

-- ============================================================
-- CASO W — non-enumeration (Owner B contra Collection de Owner A)
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_owner_b UUID := (SELECT owner_b_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_coll_a  UUID;
    v_msg_nonexistent TEXT;
    v_msg_foreign     TEXT;
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    SELECT id INTO v_coll_a FROM public.create_collection(v_game, 'TEST-02D-NonEnum-W', NULL, v_storage);
    RESET ROLE;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);

    BEGIN
        PERFORM public.set_collection_card_set_reference(gen_random_uuid(), v_cs1);
    EXCEPTION WHEN OTHERS THEN
        v_msg_nonexistent := SQLERRM;
    END;

    BEGIN
        PERFORM public.set_collection_card_set_reference(v_coll_a, v_cs1);
    EXCEPTION WHEN OTHERS THEN
        v_msg_foreign := SQLERRM;
    END;

    RESET ROLE;

    IF v_msg_nonexistent = v_msg_foreign THEN
        PERFORM pg_temp.log_result('W', 'PASS', format('mesma mensagem genérica: %s', v_msg_nonexistent));
    ELSE
        PERFORM pg_temp.log_result('W', 'FAIL', format('mensagens distintas: [%s] vs [%s]', v_msg_nonexistent, v_msg_foreign));
    END IF;
END;
$$;

-- ============================================================
-- CASO X — RLS/grants + EXISTÊNCIA (-STAGING-FINAL-FIX-01, item 3):
-- has_function_privilege() sobre um nome que não existe em pg_proc
-- simplesmente não aparece na consulta — um LEFT/INNER JOIN contra
-- pg_proc filtrado por proname nunca detecta "função ausente" por si
-- só, ele só teria 0 linhas leak/misconfigured por ausência de sujeito,
-- gerando falso PASS. Corrigido: conta primeiro quantas das funções
-- esperadas de fato EXISTEM (deve bater com o tamanho do array
-- esperado) — só então avalia grants sobre as que existem.
-- ============================================================
DO $$
DECLARE
    v_owner_b UUID := (SELECT owner_b_id FROM fixture_ctx);
    v_coll_a  UUID := (SELECT collection_id FROM fixture_collection_c);
    v_helper_names TEXT[] := ARRAY[
        'validate_collection_reference_structural_identity',
        'validate_collection_card_set_reference_structural_identity',
        'validate_collection_card_set_reference_game_and_lock',
        'validate_collection_reference_lifecycle_guard',
        'validate_collection_reference_consistency',
        'validate_collection_card_set_reference_consistency',
        'validate_collection_reference_presence',
        'check_collection_reference_subtype_consistency'
    ];
    v_rpc_names TEXT[] := ARRAY[
        'create_reference_based_card_set_collection',
        'set_collection_card_set_reference'
    ];
    v_visible_count           INT;
    v_helper_existing_count   INT;
    v_helper_leak_count       INT;
    v_rpc_existing_count      INT;
    v_rpc_misconfigured_count INT;
    v_detail TEXT := '';
BEGIN
    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_b::text, true);

    SELECT count(*) INTO v_visible_count
    FROM public.collection_reference WHERE collection_id = v_coll_a;

    RESET ROLE;

    -- Existência: as 8 funções de trigger/helper precisam existir
    -- exatamente (nem mais, nem menos — um nome digitado errado em
    -- qualquer um dos dois lados também seria pego aqui).
    SELECT count(*) INTO v_helper_existing_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(v_helper_names);

    SELECT count(*) INTO v_rpc_existing_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = ANY(v_rpc_names);

    -- Grants: nenhuma função de trigger/helper pode ser executável por
    -- anon OU authenticated — só a própria trigger machinery a chama.
    SELECT count(*) INTO v_helper_leak_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_helper_names)
      AND (
          has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
      );

    -- Grants: as duas RPCs novas devem ter EXATAMENTE authenticated=true
    -- e anon=false — qualquer desvio conta como misconfigurado.
    SELECT count(*) INTO v_rpc_misconfigured_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_rpc_names)
      AND (
          NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR has_function_privilege('anon', p.oid, 'EXECUTE')
      );

    IF v_visible_count <> 0 THEN
        v_detail := v_detail || format('visible_count=%s (esperado 0); ', v_visible_count);
    END IF;
    IF v_helper_existing_count <> array_length(v_helper_names, 1) THEN
        v_detail := v_detail || format('helper_existing_count=%s (esperado %s — alguma função de trigger/helper está ausente); ', v_helper_existing_count, array_length(v_helper_names, 1));
    END IF;
    IF v_rpc_existing_count <> array_length(v_rpc_names, 1) THEN
        v_detail := v_detail || format('rpc_existing_count=%s (esperado %s — alguma RPC está ausente); ', v_rpc_existing_count, array_length(v_rpc_names, 1));
    END IF;
    IF v_helper_leak_count <> 0 THEN
        v_detail := v_detail || format('helper_leak_count=%s (esperado 0); ', v_helper_leak_count);
    END IF;
    IF v_rpc_misconfigured_count <> 0 THEN
        v_detail := v_detail || format('rpc_misconfigured_count=%s (esperado 0); ', v_rpc_misconfigured_count);
    END IF;

    IF v_detail = '' THEN
        PERFORM pg_temp.log_result('X', 'PASS', format(
            '%s/%s helpers e %s/%s RPCs existentes, todos com grants corretos; Owner B não vê Collection Reference de Owner A',
            v_helper_existing_count, array_length(v_helper_names, 1), v_rpc_existing_count, array_length(v_rpc_names, 1)));
    ELSE
        PERFORM pg_temp.log_result('X', 'FAIL', v_detail);
    END IF;
END;
$$;

-- ============================================================
-- CASO Z — Reference nasce após reference_locked_at já materializado
-- -> FAIL (blocker fechado em -STAGING-REVISION-01, item 1)
--
-- Cenário: uma Collection REFERENCE_BASED é criada por INSERT direto,
-- SEM nenhuma Collection Reference ainda. Como a checagem de
-- elegibilidade em allocate_physical_cards_to_collection() (Query
-- 5064) usa LEFT JOIN até collection_reference/collection_card_set_
-- reference, ela simplesmente não encontra nada a checar quando a
-- Reference não existe — a Allocation é aceita, e o trigger de 5062
-- materializa reference_locked_at normalmente. Só então se tenta criar
-- a Collection Reference — que agora precisa falhar IMEDIATAMENTE
-- (não no COMMIT) pelos guards novos de 5055/5056.
-- ============================================================
DO $$
DECLARE
    v_owner_a UUID := (SELECT owner_a_id FROM fixture_ctx);
    v_game    UUID := (SELECT game_g1_id FROM fixture_ctx);
    v_storage UUID := (SELECT storage_id FROM fixture_storage_id);
    v_cs1     UUID := (SELECT card_set_cs1_id FROM fixture_ctx);
    v_pc      UUID := (SELECT pc_cs1_d FROM fixture_pc);
    v_coll_id UUID;
    v_ref_id  UUID;
    v_locked_at TIMESTAMPTZ;
BEGIN
    INSERT INTO public.collection (owner_user_id, game_id, name, default_storage_container_id, mode)
    VALUES (v_owner_a, v_game, 'TEST-02D-Bypass-Z', v_storage, 'REFERENCE_BASED')
    RETURNING id INTO v_coll_id;

    PERFORM set_config('role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', v_owner_a::text, true);
    PERFORM public.allocate_physical_cards_to_collection(v_coll_id, ARRAY[v_pc]);
    RESET ROLE;

    SELECT reference_locked_at INTO v_locked_at FROM public.collection WHERE id = v_coll_id;

    IF v_locked_at IS NULL THEN
        PERFORM pg_temp.log_result('Z', 'FAIL', 'pré-condição do cenário falhou — reference_locked_at não materializou antes da Reference existir');
    ELSE
        BEGIN
            INSERT INTO public.collection_reference (collection_id, reference_kind)
            VALUES (v_coll_id, 'CARD_SET') RETURNING id INTO v_ref_id;
            INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
            VALUES (v_ref_id, v_cs1);

            PERFORM pg_temp.log_result('Z', 'FAIL', 'exceção esperada não foi levantada — Reference criada com sucesso mesmo após reference_locked_at já materializado');
        EXCEPTION WHEN OTHERS THEN
            -- Assertion específica (-STAGING-FINAL-FIX-01, item 2): não
            -- aceitar QUALQUER exceção como PASS — precisa ser
            -- especificamente o guard novo de 5056 (que dispara
            -- primeiro, no INSERT de collection_reference; 5055 nunca é
            -- alcançada neste cenário porque o INSERT do supertipo já
            -- falha antes do INSERT do subtipo rodar). Uma exceção de
            -- outra origem (ex.: erro de sintaxe, FK inesperada, um
            -- guard diferente disparando por engano) precisa ser FAIL,
            -- não PASS por engano.
            IF SQLERRM LIKE '%reference_locked_at already set%' THEN
                PERFORM pg_temp.log_result('Z', 'PASS', SQLERRM);
            ELSE
                PERFORM pg_temp.log_result('Z', 'FAIL', format('exceção levantada, mas por motivo inesperado (não é o guard de reference_locked_at): %s', SQLERRM));
            END IF;
        END;
    END IF;

    -- Independente do resultado, a Collection Z fica com mode =
    -- REFERENCE_BASED e sem Reference — a checagem diferida de 5059
    -- também falharia no COMMIT desta transação de teste (nunca
    -- alcançado, pois o script termina em ROLLBACK). Não é um segundo
    -- caso: é o mesmo cenário inválido visto por dois ângulos
    -- (imediato aqui, diferido se chegasse ao COMMIT).
END;
$$;

-- ============================================================
-- Resultado consolidado
-- ============================================================
SELECT case_label, status, detail FROM test_results ORDER BY seq;

ROLLBACK;

-- CASO Y — zero residue: executar em uma chamada SEPARADA, DEPOIS
-- deste script, contra tabelas reais (nunca dentro da transação acima,
-- que já foi revertida por definição):
--
--   SELECT count(*) FROM public.collection      WHERE name LIKE 'TEST-02D-%';
--   SELECT count(*) FROM public.collection_reference cr
--     JOIN public.collection col ON col.id = cr.collection_id
--     WHERE col.name LIKE 'TEST-02D-%';
--   SELECT count(*) FROM public.storage_container WHERE name = 'TEST-02D-Storage';
--   SELECT count(*) FROM public.physical_card pc
--     JOIN public.inventory inv ON inv.id = pc.inventory_id
--     WHERE pc.created_at > (SELECT max(created_at) - interval '1 hour' FROM public.physical_card);
--
-- Esperado: 0 nas três primeiras (a quarta é só uma amostra temporal
-- de sanidade, não uma prova formal). Mesma metodologia de prova
-- primária (ROLLBACK, garantia ACID incondicional) + prova adicional
-- pós-ROLLBACK já usada em 5806/5807 (02C).
