/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5812 - Validate Collections Physical Increment 02F (MASTER_SET Scope & Completion)
Versão......: 2.3
Status......: EXECUTADO (COLLECTIONS-PHYSICAL-INCREMENT-02F-IMPLEMENTATION-FIX-02) — ver 5813 para performance
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-02 (COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01 → -STAGING-REVISION-01 → -STAGING-FINAL-REVISION-02 → -IMPLEMENTATION-FIX-01 → -IMPLEMENTATION-FIX-02)

CORREÇÃO v2.3 (IMPLEMENTATION-FIX-02) — RUNTIME FINDING DO TEST HARNESS,
  NÃO DEFEITO DO SCHEMA 02F: a execução real de v2.2 abortou em
  REG-STD-7 com `P0001: game not found`. Causa raiz confirmada (não é
  hipótese): `authenticated` TEM GRANT de SELECT em `card`/
  `card_variant`/`card_set`/`expansion` (confirmado via
  `has_table_privilege`), mas a RLS dessas tabelas filtra as linhas
  visíveis para admin apenas — mesma razão pela qual o próprio Caso `E`
  desta bateria espera 0 linhas em `SELECT count(*) FROM card_variant`
  sob Owner A. REG-STD-7 fazia essa mesma classe de leitura direta
  (achar o Card Set com menos Cards + seu `game_id` + os
  `card_variant_id` de cada Card) *depois* da troca de role — sob RLS,
  isso retorna 0 linhas silenciosamente (não é erro de permissão como
  o achado do 5812 v2.2), `v_small_set_id`/`v_game_id` ficavam NULL, e
  a RPC `create_reference_based_card_set_collection(NULL, ...)`
  falhava. Auditoria completa de todo o arquivo após `SET ROLE
  authenticated` (Owner A e Owner B) por leituras diretas de `card`,
  `card_variant`, `card_set`, `expansion`, `card_variant_type`,
  `rarity`, `category`: só 2 pontos encontrados — Caso `E` (linha
  ~875, teste INTENCIONAL do bloqueio RLS, mantido sem alteração) e as
  3 consultas de REG-STD-7 (linhas ~981-1003 da v2.2, classe B, únicas
  corrigidas). Nenhuma outra ocorrência. Correção: as mesmas 3 queries
  (Card Set pequeno, `game_id`, Variants de cada Card do Set) foram
  movidas para o Passo 3 (contexto privilegiado, antes do `SET ROLE`),
  resolvidas em `test_ctx` (`small_card_set_id`, `small_game_id`) e na
  nova tabela temporária `test_small_set_cards` (`card_id`,
  `variant_id`) — mesmo padrão já usado para `variant_a..e`/
  `test_card_set`/`foreign_variant`. REG-STD-7 passou a ler
  exclusivamente dessas duas fontes, sem tocar o Catálogo Editorial
  sob `authenticated`. Nenhum GRANT novo foi criado em tabela de
  catálogo; a única concessão nova é `GRANT SELECT ON
  test_small_set_cards TO authenticated` (tabela de fixture da própria
  bateria, mesmo padrão de `test_other_cards`). RLS não foi relaxada
  em nenhum ponto. REG-STD-1..7 preservados sem redução de cobertura.

CORREÇÃO v2.2 (IMPLEMENTATION-FIX-01) — RUNTIME FINDING DO TEST HARNESS,
  NÃO DEFEITO DO SCHEMA 02F (5072-5084): a primeira execução real de
  v2.1 contra o banco físico abortou com `42501: permission denied for
  table physical_card` dentro do bloco REG-STD. Auditoria confirmou:
  `authenticated` tem SELECT em `physical_card`, mas NUNCA teve INSERT
  direto por desenho — toda escrita em `physical_card` sob esse role
  passa exclusivamente pela RPC pública `add_physical_cards(p_items
  jsonb)` (SECURITY DEFINER, resolve `inventory_id` do próprio
  `auth.uid()`, aceita array de `{"card_variant_id","language_id"}`,
  devolve `TABLE(id, card_variant_id, language_id, created_at)`,
  1-500 itens por chamada). REG-STD-0..7 (impersonando Owner A já sob
  `authenticated`, Passo 7) fazia `INSERT INTO public.physical_card`
  direto — os únicos 3 pontos do arquivo inteiro onde isso acontecia
  depois da troca de role (auditoria completa de todas as ocorrências
  de `INSERT INTO public.physical_card`, classificadas A/antes-do-
  SET-ROLE vs B/depois — Passo 4 são 5 ocorrências classe A, legítimas,
  fixture privilegiada, inalteradas; REG-STD tinha 2 ocorrências classe
  B, REG-STD-7 tinha 1 ocorrência classe B dentro de um loop — as 3
  corrigidas aqui). Nenhuma outra escrita direta em tabela protegida
  sob `authenticated` foi encontrada no restante do arquivo (Passo
  7-11 revisado por completo: todo o resto já usava RPC pública ou
  SELECT, coberto por GRANT existente). ACL/RLS não foi relaxada em
  nenhum ponto — a correção troca o mecanismo de escrita do teste pela
  superfície pública real, preservando o teste sob o mesmo contrato
  que o frontend usaria. REG-STD-1..7 preservados sem redução de
  cobertura — mesmas asserções, mesmos fixtures lógicos, só a origem
  dos `physical_card.id` mudou de INSERT direto para o retorno de
  `add_physical_cards()`.

CORREÇÃO v2.1 (STAGING-FINAL-REVISION-02, item 2): novo caso
  PAYLOAD-DUPLICATE-CANONICAL — mesmo UUID válido de variant_a
  requisitado duas vezes com representações textuais diferentes
  (lowercase/UPPERCASE), via set_collection_completion_policy_to_
  master_set(). Prova a correção de 5079 v2.1 (item 1): a duplicata
  deve ser rejeitada por IDENTIDADE UUID, não por igualdade textual —
  a v2.0 de 5079 deixaria passar esse caso (falso negativo). Esperado:
  FAIL, zero Scope writes, completion_policy permanece STANDARD_SET —
  integrado à mesma prova final PAYLOAD-ZERO-CHANGES já existente.

CORREÇÕES v2.0 (STAGING-REVISION-01, auditoria fonte-a-fonte):
  item 6 (BLOCKER) — POSTCHECK-4..7 tinham os bits BEFORE/AFTER de
    `pg_trigger.tgtype` INVERTIDOS. No Postgres real, bit BEFORE = 2
    (não 0); AFTER é a AUSÊNCIA desse bit. Corrigido, e passou a
    validar também os bits de EVENTO (INSERT=4, UPDATE=16, DELETE=8),
    não só o timing.
  item 7 (BLOCKER de falso negativo) — a checagem de `search_path=''`
    em SEC-5 comparava `cfg = 'search_path='`, mas a representação
    física real de `SET search_path = ''` em `pg_proc.proconfig` é
    `search_path=""`. Corrigido para uma comparação robusta ao valor
    (via `split_part`), aceitando ambas as formas.
  item 3 — S2M-REUSE agora espera `kept_count` real (2), não 0 (ver
    correção correspondente em 5080).
  item 8 — bloco REG-STD novo: regressão mínima obrigatória de
    STANDARD_SET pós-5083 (denominador por Card, satisfação por
    qualquer Variant da Card, duplicatas não inflam, incomplete/
    complete, `collection_completion_positions()` Card-oriented,
    `p_only_missing`).
  item 9 — ARCHIVED-MUT-3 agora usa uma fixture genuinamente
    STANDARD_SET+ARCHIVED (`col_std_archive`), não mais a fixture
    MASTER_SET+ARCHIVED reaproveitada de ARCHIVED-MUT-1/2 (que não
    provava o cenário STANDARD->MASTER arquivado de fato).
  item 10 — bloco PAYLOAD-* novo: contrato de payload de 5079
    (duplicate/malformed/non-string/non-array/empty/foreign-set),
    todos FAIL + zero Scope changes.

Descrição...:
Bateria funcional de validação de 5072-5084 (MASTER_SET Scope &
Completion). Mesmo mecanismo já estabelecido em 5808/5810 (02D/02E):
BEGIN...ROLLBACK, pg_temp.log_result()/test_results, impersonação real
via set_config, casos "deveria FALHAR" em DO $$ ... EXCEPTION WHEN ...
$$ (savepoint implícito), casos "deveria PASSAR" sem tratamento de
exceção (fail-loud), SELECT final consolidado, ROLLBACK incondicional,
prova pós-ROLLBACK em chamada separada. Nenhum COMMIT nesta bateria.

MECANISMO NOVO NESTA RODADA — prova de enforcement DIFERIDO sem COMMIT.
Os dois constraint triggers de 5076/5077 só decidem de fato no momento
em que o Postgres processa a fila de checagens diferidas — normalmente
no COMMIT. Como esta bateria inteira roda dentro de uma única
transação que NUNCA comita (mesma disciplina de zero resíduo de
5808/5810), o COMMIT real nunca acontece. Para provar o comportamento
do enforcement diferido de forma real (não simulada) sem abrir mão do
ROLLBACK final, esta bateria usa:

    SET CONSTRAINTS trg_collection_master_set_scope_presence,
                     trg_collection_master_set_scope_presence_on_delete
        IMMEDIATE;

— comando transacional padrão do Postgres que força o processamento
imediato da fila de checagens pendentes desses dois constraint
triggers nomeados especificamente (nunca `SET CONSTRAINTS ALL`, para
não forçar também os triggers diferidos do 02D — mode<->reference,
supertipo<->subtipo — que não são objeto desta bateria e cujo estado
de fixture não foi construído para ser avaliado neste ponto). Chamado
sempre via `EXECUTE` dentro de um DO $$ ... $$ (garantia de forma,
não depende de PL/pgSQL aceitar SET CONSTRAINTS como statement direto).
Nos casos "deveria FALHAR" (G0), a exceção lançada pela checagem
forçada é capturada pelo savepoint implícito do próprio bloco DO — o
que também reverte o próprio `SET CONSTRAINTS ... IMMEDIATE` (é estado
transacional, sujeito a rollback-to-savepoint como qualquer outro).
Nos casos "deveria PASSAR" (F, TEMP-EMPTY, CASCADE), nenhuma exceção
ocorre, então o modo IMMEDIATE persiste após o bloco — por isso, ao
final de cada um desses blocos, o próprio bloco reverte explicitamente
para DEFERRED antes de terminar, para não afetar avaliações
posteriores dos mesmos dois triggers mais adiante no script.

Pré-condições (fail-loud, Passo 2): >= 2 Owners NÃO-ADMIN distintos com
Inventory (Owner A/Owner B, mesmo padrão de segurança de 5810 — nunca
Owners admin); >= 1 Game; >= 1 Language; um Card com >= 2 Card Variants
cujo Card Set tenha >= 5 Cards distintas, cada uma com >= 1 Card
Variant (fixture A-E: a Card multi-variant fornece Variant A + a
Variant "irmã" de mesma Card para o Caso EXACT-MATCH; as 4 Cards
restantes fornecem Variants B/C/D/E); um Card Set DIFERENTE do Card Set
acima, com >= 1 Card Variant (fixture do Caso B — Scope de Set errado).

Cobertura desta bateria (mandato item 14, mínimo obrigatório): criar/
usar Master válido (Caso A); Scope de Set errado rejeitado (Caso B,
via trigger direto e via RPC); owner alheio rejeitado/não-enumerável
(Caso C); anônimo negado (Caso D); SELECT direto do catálogo continua
bloqueado (Caso E); MASTER vazio impossível — nível RPC (EMPTY-1) e
nível estrutural diferido (G0); vazio temporário + reposição -> PASS
(TEMP-EMPTY); UPDATE em Scope proibido (UPDATE-BLOCK); KEEP preserva
adopted_at/adopted_by (KEEP); ADD cria nova proveniência (ADD); REMOVE
só remove requisito, nunca Physical Card/Allocation (REMOVE);
duplicatas não inflam progresso (DUPLICATES); correspondência exata de
Variant (EXACT-MATCH); completo/incompleto (COMPLETE/INCOMPLETE);
leitura ARCHIVED funciona (ARCHIVED-READ); mutação ARCHIVED falha
(ARCHIVED-MUT-1/2/3); MASTER->STANDARD preserva Scope (M2S-PRESERVE);
STANDARD->MASTER reaproveita Scope persistido, caminho B (S2M-REUSE);
STANDARD->MASTER com novo Scope requisitado executa KEEP/ADD/REMOVE
contra o Scope PERSISTIDO, caminho A (Caso G, MODELING-FINAL-FIX-02
item 2); exclusão de Collection + CASCADE funciona (CASCADE-DELETE);
regressão mínima de STANDARD_SET pós-5083 (REG-STD-0..7, novo nesta
revisão); contrato de payload de apply_master_set_scope_diff() —
non-array/empty/non-string/malformed UUID/nonexistent/foreign-set/
duplicate, todos FAIL + zero writes (PAYLOAD-*, novo nesta revisão).

CASO F OBRIGATÓRIO (mandato item 14): STANDARD -> MASTER -> STANDARD
na MESMA transação, por SQL direto (não pela RPC pública), sem nunca
inserir Scope -> força a checagem diferida -> deve PASSAR. Prova que o
helper `check_master_set_scope_presence()` decide pelo estado CORRENTE
da Collection no momento da checagem, nunca pelo `NEW.completion_policy`
capturado no evento intermediário que ficou "MASTER_SET" (Caso F do
raciocínio de MODELING-FINAL-FIX-02).

CASO G OBRIGATÓRIO (mandato item 14): Scope persistido {A,B,C} sobre
uma Collection hoje STANDARD_SET (chegou lá via um ciclo MASTER_SET
anterior seguido de volta a STANDARD_SET, preservando o Scope) ->
STANDARD -> MASTER via `set_collection_completion_policy_to_master_set()`
com requested_scope {A,B,C,D} -> A/B/C devem ser KEEP (adopted_at/
adopted_by_user_id idênticos aos capturados antes da chamada); D deve
ser ADD (nova proveniência). Prova a correção de MODELING-FINAL-FIX-02
item 2: a RPC compara contra o Scope efetivamente PERSISTIDO, nunca
presume "tudo ADD" só porque completion_policy atual não é MASTER_SET.

STATUS DESTA QUERY: PROPOSTA — NÃO EXECUTADA.
================================================================
*/

-- ================================================================
-- PASSO -1 (fora de transação) — baseline de resíduo
-- ================================================================
SELECT count(*) AS collections_com_prefixo_antes
FROM public.collection
WHERE name LIKE 'VAL-TEST-02F-%';

SELECT count(*) AS physical_card_count_antes
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);

SELECT count(*) AS scope_rows_com_prefixo_antes
FROM public.collection_master_set_scope s
JOIN public.collection c ON c.id = s.collection_id
WHERE c.name LIKE 'VAL-TEST-02F-%';

-- ================================================================
-- PASSO 0 — BEGIN + infraestrutura de log
-- ================================================================
BEGIN;

CREATE TEMP TABLE test_results (
    id          SERIAL PRIMARY KEY,
    case_label  TEXT NOT NULL,
    passed      BOOLEAN NOT NULL,
    detail      TEXT
);

CREATE FUNCTION pg_temp.log_result(p_case TEXT, p_passed BOOLEAN, p_detail TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO test_results (case_label, passed, detail) VALUES (p_case, p_passed, p_detail);
END;
$$;

-- ================================================================
-- PASSO 1 — POSTCHECKS ESTRUTURAIS (5072-5084 existem com a forma certa)
-- ================================================================

-- POSTCHECK-1 — tabela existe
DO $$
BEGIN
    PERFORM pg_temp.log_result('POSTCHECK-1 - collection_master_set_scope existe',
        to_regclass('public.collection_master_set_scope') IS NOT NULL, NULL);
END $$;

-- POSTCHECK-2 — PK composta (collection_id, card_variant_id), nenhum UUID próprio
DO $$
DECLARE
    v_pk_cols TEXT[];
BEGIN
    SELECT array_agg(a.attname ORDER BY k.ord) INTO v_pk_cols
    FROM pg_constraint con
    JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
    JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = k.attnum
    WHERE con.conrelid = 'public.collection_master_set_scope'::regclass
      AND con.contype = 'p';

    PERFORM pg_temp.log_result('POSTCHECK-2 - PK composta (collection_id, card_variant_id)',
        v_pk_cols = ARRAY['collection_id', 'card_variant_id'], format('pk_cols=%s', v_pk_cols));

    PERFORM pg_temp.log_result('POSTCHECK-2b - nenhuma coluna id/uuid propria adicional',
        NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'collection_master_set_scope'
              AND column_name = 'id'
        ), NULL);
END $$;

-- POSTCHECK-3 — sem updated_at (insert/delete-only por desenho)
DO $$
BEGIN
    PERFORM pg_temp.log_result('POSTCHECK-3 - nenhuma coluna updated_at',
        NOT EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'collection_master_set_scope'
              AND column_name = 'updated_at'
        ), NULL);
END $$;

-- POSTCHECK-4 — trigger de elegibilidade: BEFORE INSERT, ROW
-- (correção STAGING-REVISION-01 item 6 — BLOCKER: bit BEFORE = 2 no
-- Postgres real, nao 0; AFTER = ausencia desse bit. Tambem valida
-- agora o bit de evento INSERT, nao so o timing.)
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT tgtype, tgdeferrable INTO r
    FROM pg_trigger
    WHERE tgname = 'trg_collection_master_set_scope_eligibility'
      AND tgrelid = 'public.collection_master_set_scope'::regclass;

    PERFORM pg_temp.log_result('POSTCHECK-4 - trigger de elegibilidade existe, BEFORE ROW INSERT, nao deferravel',
        FOUND AND (r.tgtype & 1) = 1        -- bit 0 (valor 1): ROW
              AND (r.tgtype & 2) = 2        -- bit 1 (valor 2): BEFORE
              AND (r.tgtype & 4) = 4        -- bit 2 (valor 4): INSERT
              AND r.tgdeferrable IS FALSE,
        format('found=%s tgtype=%s tgdeferrable=%s', FOUND, r.tgtype, r.tgdeferrable));
END $$;

-- POSTCHECK-5 — trigger de bloqueio de UPDATE: BEFORE UPDATE, ROW
-- (mesma correção de bits do POSTCHECK-4)
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT tgtype, tgdeferrable INTO r
    FROM pg_trigger
    WHERE tgname = 'trg_collection_master_set_scope_reject_update'
      AND tgrelid = 'public.collection_master_set_scope'::regclass;

    PERFORM pg_temp.log_result('POSTCHECK-5 - trigger de bloqueio de UPDATE existe, BEFORE ROW UPDATE, nao deferravel',
        FOUND AND (r.tgtype & 1) = 1
              AND (r.tgtype & 2) = 2        -- BEFORE
              AND (r.tgtype & 16) = 16      -- bit 4 (valor 16): UPDATE
              AND r.tgdeferrable IS FALSE,
        format('found=%s tgtype=%s tgdeferrable=%s', FOUND, r.tgtype, r.tgdeferrable));
END $$;

-- POSTCHECK-6 — trigger lado Collection: AFTER INSERT/UPDATE, ROW,
-- DEFERRABLE INITIALLY DEFERRED (mesma correção de bits)
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT tgtype, tgdeferrable, tginitdeferred INTO r
    FROM pg_trigger
    WHERE tgname = 'trg_collection_master_set_scope_presence'
      AND tgrelid = 'public.collection'::regclass;

    PERFORM pg_temp.log_result('POSTCHECK-6 - trigger lado Collection: AFTER ROW INSERT/UPDATE DEFERRABLE INITIALLY DEFERRED',
        FOUND AND (r.tgtype & 1) = 1
              AND (r.tgtype & 2) = 0        -- AFTER (ausencia do bit BEFORE=2)
              AND (r.tgtype & 4) = 4        -- INSERT
              AND (r.tgtype & 16) = 16      -- UPDATE
              AND r.tgdeferrable IS TRUE AND r.tginitdeferred IS TRUE,
        format('found=%s tgtype=%s tgdeferrable=%s tginitdeferred=%s', FOUND, r.tgtype, r.tgdeferrable, r.tginitdeferred));
END $$;

-- POSTCHECK-7 — trigger lado Scope: AFTER DELETE, ROW, DEFERRABLE
-- INITIALLY DEFERRED (mesma correção de bits)
DO $$
DECLARE
    r RECORD;
BEGIN
    SELECT tgtype, tgdeferrable, tginitdeferred INTO r
    FROM pg_trigger
    WHERE tgname = 'trg_collection_master_set_scope_presence_on_delete'
      AND tgrelid = 'public.collection_master_set_scope'::regclass;

    PERFORM pg_temp.log_result('POSTCHECK-7 - trigger lado Scope: AFTER ROW DELETE DEFERRABLE INITIALLY DEFERRED',
        FOUND AND (r.tgtype & 1) = 1
              AND (r.tgtype & 2) = 0        -- AFTER
              AND (r.tgtype & 8) = 8        -- bit 3 (valor 8): DELETE
              AND r.tgdeferrable IS TRUE AND r.tginitdeferred IS TRUE,
        format('found=%s tgtype=%s tgdeferrable=%s tginitdeferred=%s', FOUND, r.tgtype, r.tgdeferrable, r.tginitdeferred));
END $$;

-- POSTCHECK-8 — CHECK widened para incluir MASTER_SET
DO $$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint
    WHERE conrelid = 'public.collection'::regclass
      AND conname = 'chk_collection_completion_policy';
    PERFORM pg_temp.log_result('POSTCHECK-8 - chk_collection_completion_policy inclui MASTER_SET',
        v_def LIKE '%MASTER_SET%', COALESCE(v_def, 'constraint nao encontrada'));
END $$;

-- POSTCHECK-9 — funções novas existem
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT fname FROM unnest(ARRAY[
            'check_master_set_scope_presence', 'apply_master_set_scope_diff',
            'set_collection_completion_policy_to_master_set',
            'set_collection_completion_policy_to_standard_set',
            'replace_master_set_scope', 'collection_master_set_scope_positions'
        ]) AS fname
    LOOP
        PERFORM pg_temp.log_result(
            format('POSTCHECK-9 - funcao %s existe', r.fname),
            EXISTS (SELECT 1 FROM pg_proc WHERE proname = r.fname), NULL);
    END LOOP;
END $$;

-- POSTCHECK-10 — collection_completion_summary é a v3.0 (ramo MASTER_SET presente)
DO $$
DECLARE
    v_src TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p WHERE p.proname = 'collection_completion_summary';
    PERFORM pg_temp.log_result('POSTCHECK-10 - collection_completion_summary contem ramo master_denom (v3.0)',
        v_src LIKE '%master_denom%', NULL);
END $$;

-- ================================================================
-- PASSO 2 — PRÉ-CONDIÇÕES (fail-loud)
-- ================================================================
DO $$
DECLARE
    v_owner_count      INT;
    v_game_count       INT;
    v_language_count   INT;
    v_fixture_set_count INT;
    v_foreign_set_count INT;
BEGIN
    SELECT count(DISTINCT i.owner_user_id) INTO v_owner_count
    FROM public.inventory i
    WHERE i.owner_user_id NOT IN (SELECT au.id FROM public.admin_user au);
    IF v_owner_count < 2 THEN
        RAISE EXCEPTION 'fixtures insuficientes: >= 2 Owners NAO-ADMIN distintos com Inventory necessarios (encontrados: %)', v_owner_count;
    END IF;

    SELECT count(*) INTO v_game_count FROM public.game;
    IF v_game_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Game encontrado';
    END IF;

    SELECT count(*) INTO v_language_count FROM public.language;
    IF v_language_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhuma Language encontrada';
    END IF;

    -- Card Set com uma Card de >= 2 Variants e >= 5 Cards distintas no
    -- total, cada uma com >= 1 Variant (fixture A-E + EXACT-MATCH).
    SELECT count(*) INTO v_fixture_set_count
    FROM (
        SELECT c.card_set_id
        FROM public.card c
        WHERE (SELECT count(*) FROM public.card_variant cv WHERE cv.card_id = c.id) >= 2
    ) multi
    WHERE (
        SELECT count(DISTINCT c2.id)
        FROM public.card c2
        JOIN public.card_variant cv2 ON cv2.card_id = c2.id
        WHERE c2.card_set_id = multi.card_set_id
    ) >= 5;
    IF v_fixture_set_count < 1 THEN
        RAISE EXCEPTION 'fixtures insuficientes: nenhum Card Set com uma Card de >= 2 Variants e >= 5 Cards distintas com >= 1 Variant cada (necessario para fixture A-E/EXACT-MATCH)';
    END IF;

    -- Card Set diferente do escolhido acima, com >= 1 Card Variant
    -- (fixture do Caso B). A checagem real de "diferente" acontece na
    -- resolução do Passo 3; aqui só confirma que existe mais de 1 Card
    -- Set elegível no catálogo.
    SELECT count(DISTINCT c.card_set_id) INTO v_foreign_set_count
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id;
    IF v_foreign_set_count < 2 THEN
        RAISE EXCEPTION 'fixtures insuficientes: sao necessarios >= 2 Card Sets distintos com Card Variant (Caso B precisa de um Card Set estrangeiro)';
    END IF;
END $$;

-- ================================================================
-- PASSO 3 — resolver contexto em test_ctx (key/value)
-- ================================================================
CREATE TEMP TABLE test_ctx (key TEXT PRIMARY KEY, value TEXT);

INSERT INTO test_ctx (key, value)
SELECT 'owner_a', owner_user_id::text FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
ORDER BY owner_user_id LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'owner_b', owner_user_id::text FROM public.inventory
WHERE owner_user_id NOT IN (SELECT id FROM public.admin_user)
  AND owner_user_id <> (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a')
ORDER BY owner_user_id LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'inventory_a', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a');

INSERT INTO test_ctx (key, value)
SELECT 'inventory_b', id::text FROM public.inventory
WHERE owner_user_id = (SELECT value::uuid FROM test_ctx WHERE key = 'owner_b');

INSERT INTO test_ctx (key, value)
SELECT 'language_id', id::text FROM public.language LIMIT 1;

-- Card Set fixture A-E: escolhe a Card multi-variant cujo Card Set tem
-- >= 5 Cards distintas com >= 1 Variant cada.
DO $$
DECLARE
    v_card_multi UUID;
    v_card_set   UUID;
    v_game       UUID;
BEGIN
    SELECT c.id, c.card_set_id INTO v_card_multi, v_card_set
    FROM public.card c
    WHERE (SELECT count(*) FROM public.card_variant cv WHERE cv.card_id = c.id) >= 2
      AND (
          SELECT count(DISTINCT c2.id)
          FROM public.card c2
          JOIN public.card_variant cv2 ON cv2.card_id = c2.id
          WHERE c2.card_set_id = c.card_set_id
      ) >= 5
    LIMIT 1;

    SELECT ex.game_id INTO v_game
    FROM public.card_set cs JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = v_card_set;

    INSERT INTO test_ctx (key, value) VALUES
        ('card_multi', v_card_multi::text),
        ('test_card_set', v_card_set::text),
        ('game_id_test', v_game::text);
END $$;

-- variant_a e variant_x_samecard: as 2 Variants da mesma Card
-- (fixture do Caso EXACT-MATCH: variant_x_samecard NUNCA entra no
-- Scope, mas satisfaz a mesma Card que variant_a).
INSERT INTO test_ctx (key, value)
SELECT 'variant_a', id::text FROM public.card_variant
WHERE card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
ORDER BY variant_order LIMIT 1;

INSERT INTO test_ctx (key, value)
SELECT 'variant_x_samecard', id::text FROM public.card_variant
WHERE card_id = (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
ORDER BY variant_order OFFSET 1 LIMIT 1;

-- variant_b/c/d/e: 4 outras Cards distintas do mesmo Card Set, 1
-- Variant cada.
CREATE TEMP TABLE test_other_cards (card_id UUID, variant_id UUID, rn INT);

INSERT INTO test_other_cards (card_id, variant_id, rn)
SELECT card_id, variant_id, row_number() OVER ()
FROM (
    SELECT DISTINCT ON (c.id) c.id AS card_id, cv.id AS variant_id
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    WHERE c.card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
      AND c.id <> (SELECT value::uuid FROM test_ctx WHERE key = 'card_multi')
    ORDER BY c.id, cv.variant_order
    LIMIT 4
) sub;

INSERT INTO test_ctx (key, value)
SELECT 'variant_b', variant_id::text FROM test_other_cards WHERE rn = 1;
INSERT INTO test_ctx (key, value)
SELECT 'variant_c', variant_id::text FROM test_other_cards WHERE rn = 2;
INSERT INTO test_ctx (key, value)
SELECT 'variant_d', variant_id::text FROM test_other_cards WHERE rn = 3;
INSERT INTO test_ctx (key, value)
SELECT 'variant_e', variant_id::text FROM test_other_cards WHERE rn = 4;

-- Card Set estrangeiro (Caso B) — diferente de test_card_set, com >= 1
-- Card Variant real.
DO $$
DECLARE
    v_foreign_variant UUID;
    v_foreign_set     UUID;
BEGIN
    SELECT cv.id, c.card_set_id INTO v_foreign_variant, v_foreign_set
    FROM public.card_variant cv
    JOIN public.card c ON c.id = cv.card_id
    WHERE c.card_set_id <> (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    LIMIT 1;

    INSERT INTO test_ctx (key, value) VALUES
        ('foreign_variant', v_foreign_variant::text),
        ('foreign_card_set', v_foreign_set::text);
END $$;

-- CORREÇÃO v2.3 (IMPLEMENTATION-FIX-02): fixture do Card Set pequeno
-- dedicado (REG-STD-7) resolvida aqui, em contexto PRIVILEGIADO —
-- antes tentava resolver isso sob role authenticated (Passo 7), mas
-- Catálogo Editorial (`card`/`card_variant`/`card_set`/`expansion`) é
-- fechado por RLS para usuários comuns (mesma razão do Caso E), então
-- a leitura direta ali retornava 0 linhas e propagava NULL até estourar
-- em `create_reference_based_card_set_collection(NULL, ...)`. Mesmas
-- queries de antes, só que resolvidas aqui e guardadas em test_ctx/
-- test_small_set_cards, exatamente como já se faz para
-- variant_a..e/test_card_set/foreign_variant.
DO $$
DECLARE
    v_small_set_id  UUID;
    v_small_game_id UUID;
BEGIN
    SELECT c.card_set_id INTO v_small_set_id
    FROM public.card c
    JOIN public.card_variant cv ON cv.card_id = c.id
    GROUP BY c.card_set_id
    ORDER BY count(DISTINCT c.id) ASC
    LIMIT 1;

    SELECT ex.game_id INTO v_small_game_id
    FROM public.card_set cs JOIN public.expansion ex ON ex.id = cs.expansion_id
    WHERE cs.id = v_small_set_id;

    INSERT INTO test_ctx (key, value) VALUES
        ('small_card_set_id', v_small_set_id::text),
        ('small_game_id', v_small_game_id::text);
END $$;

CREATE TEMP TABLE test_small_set_cards (card_id UUID, variant_id UUID);

INSERT INTO test_small_set_cards (card_id, variant_id)
SELECT DISTINCT ON (c.id) c.id, cv.id
FROM public.card c
JOIN public.card_variant cv ON cv.card_id = c.id
WHERE c.card_set_id = (SELECT value::uuid FROM test_ctx WHERE key = 'small_card_set_id')
ORDER BY c.id, cv.variant_order;

-- ================================================================
-- PASSO 4 — fixtures privilegiadas (Storage, Physical Cards)
-- ================================================================
WITH ins AS (
    INSERT INTO public.storage_container (inventory_id, name)
    VALUES ((SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a'), 'VAL-TEST-02F-STORAGE-A')
    RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'storage_a', id::text FROM ins;

-- pc_b1/pc_b2: 2 Physical Cards da MESMA Variant B (fixture DUPLICATES)
WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_b1', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_b2', id::text FROM ins;

-- pc_samecard: Physical Card de variant_x_samecard (fixture EXACT-MATCH negativo)
WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_x_samecard'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_samecard', id::text FROM ins;

-- pc_a1/pc_c1: completam o Scope {A,B,C} de col_a_master
WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_a1', id::text FROM ins;

WITH ins AS (
    INSERT INTO public.physical_card (card_variant_id, language_id, inventory_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'language_id'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'inventory_a')
    ) RETURNING id
)
INSERT INTO test_ctx (key, value) SELECT 'pc_c1', id::text FROM ins;

-- ================================================================
-- PASSO 5 — provas ESTRUTURAIS diretas (privilegiado, sem RPC, sem
-- impersonação) — testam os triggers/constraints em si, não a
-- fronteira de autorização das RPCs (essa vem no Passo 7 em diante)
-- ================================================================

-- col_struct: Collection REFERENCE_BASED/STANDARD_SET construida por
-- INSERT direto (mesmo padrao dos Casos C/D de 5810) — usada só para
-- ELIG-1/ELIG-2/UPDATE-BLOCK, nunca chega a MASTER_SET.
DO $$
DECLARE
    v_col_id UUID;
    v_ref_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02F-COL-STRUCT', 'REFERENCE_BASED', 'STANDARD_SET'
    )
    RETURNING id INTO v_col_id;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_col_id, 'CARD_SET') RETURNING id INTO v_ref_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_ref_id, (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set'));

    INSERT INTO test_ctx (key, value) VALUES ('col_struct', v_col_id::text);
END $$;

-- ELIG-1 (FAIL esperado) — INSERT direto de Scope com Variant de Set errado
DO $$
BEGIN
    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_struct'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'foreign_variant'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a')
    );
    PERFORM pg_temp.log_result('ELIG-1 - trigger de elegibilidade rejeita Variant de Set errado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('ELIG-1 - trigger de elegibilidade rejeita Variant de Set errado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- ELIG-2 (PASS) — INSERT direto de Scope válido (variant_a) — também
-- serve de fixture para UPDATE-BLOCK a seguir.
DO $$
DECLARE
    v_ok BOOLEAN;
BEGIN
    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'col_struct'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a')
    );
    v_ok := EXISTS (
        SELECT 1 FROM public.collection_master_set_scope
        WHERE collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_struct')
          AND card_variant_id = (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a')
    );
    PERFORM pg_temp.log_result('ELIG-2 - trigger de elegibilidade aceita Variant do Set correto (PASS)', v_ok, NULL);
END $$;

-- UPDATE-BLOCK (FAIL esperado) — UPDATE direto na linha acima
DO $$
BEGIN
    UPDATE public.collection_master_set_scope
    SET adopted_at = NOW()
    WHERE collection_id = (SELECT value::uuid FROM test_ctx WHERE key = 'col_struct')
      AND card_variant_id = (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    PERFORM pg_temp.log_result('UPDATE-BLOCK - UPDATE em collection_master_set_scope rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('UPDATE-BLOCK - UPDATE em collection_master_set_scope rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- col_f: Collection dedicada ao CASO F OBRIGATÓRIO
DO $$
DECLARE
    v_col_id UUID;
    v_ref_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02F-COL-F', 'REFERENCE_BASED', 'STANDARD_SET'
    )
    RETURNING id INTO v_col_id;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_col_id, 'CARD_SET') RETURNING id INTO v_ref_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_ref_id, (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set'));

    INSERT INTO test_ctx (key, value) VALUES ('col_f', v_col_id::text);
END $$;

-- CASO F OBRIGATÓRIO (PASS) — STANDARD -> MASTER -> STANDARD, SQL
-- direto, nunca insere Scope, força a checagem diferida -> deve
-- passar porque o estado FINAL é STANDARD_SET, nao o NEW histórico do
-- primeiro UPDATE.
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_f');
BEGIN
    UPDATE public.collection SET completion_policy = 'MASTER_SET' WHERE id = v_col_id;
    UPDATE public.collection SET completion_policy = 'STANDARD_SET' WHERE id = v_col_id;

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete IMMEDIATE';

    PERFORM pg_temp.log_result('F - STANDARD->MASTER->STANDARD mesma transacao sem Scope final -> COMMIT/PASS', TRUE, 'nenhuma excecao — estado final STANDARD_SET, helper le estado corrente');

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete DEFERRED';
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('F - STANDARD->MASTER->STANDARD mesma transacao sem Scope final -> COMMIT/PASS', FALSE, SQLERRM);
END $$;

-- col_g0: Collection MASTER_SET com 1 única linha de Scope, construída
-- por INSERT direto (chk_collection_completion_policy já aceita
-- REFERENCE_BASED/MASTER_SET desde 5078 — nenhuma RPC necessária para
-- montar este estado, só disciplina de fixture).
DO $$
DECLARE
    v_col_id UUID;
    v_ref_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02F-COL-G0', 'REFERENCE_BASED', 'MASTER_SET'
    )
    RETURNING id INTO v_col_id;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_col_id, 'CARD_SET') RETURNING id INTO v_ref_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_ref_id, (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set'));

    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    VALUES (v_col_id, (SELECT value::uuid FROM test_ctx WHERE key = 'variant_d'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'));

    INSERT INTO test_ctx (key, value) VALUES ('col_g0', v_col_id::text);
END $$;

-- G0 OBRIGATÓRIO (FAIL esperado) — remove a única linha de Scope sem
-- reposição, força a checagem diferida -> deve FALHAR.
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_g0');
BEGIN
    DELETE FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id
      AND card_variant_id = (SELECT value::uuid FROM test_ctx WHERE key = 'variant_d');

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete IMMEDIATE';

    PERFORM pg_temp.log_result('G0 - ultima linha de Scope removida sem reposicao -> checagem diferida deve FALHAR', FALSE, 'nenhuma excecao levantada — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('G0 - ultima linha de Scope removida sem reposicao -> checagem diferida deve FALHAR', TRUE, SQLERRM);
    -- savepoint implicito do bloco ja reverte o SET CONSTRAINTS IMMEDIATE
    -- junto com a excecao — nenhuma acao adicional necessaria aqui.
END $$;

-- col_tempempty: Collection MASTER_SET com 1 linha de Scope (variant_b),
-- dedicada ao caso TEMP-EMPTY.
DO $$
DECLARE
    v_col_id UUID;
    v_ref_id UUID;
BEGIN
    INSERT INTO public.collection (
        owner_user_id, game_id, default_storage_container_id, name, mode, completion_policy
    )
    VALUES (
        (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        'VAL-TEST-02F-COL-TEMPEMPTY', 'REFERENCE_BASED', 'MASTER_SET'
    )
    RETURNING id INTO v_col_id;

    INSERT INTO public.collection_reference (collection_id, reference_kind)
    VALUES (v_col_id, 'CARD_SET') RETURNING id INTO v_ref_id;

    INSERT INTO public.collection_card_set_reference (collection_reference_id, card_set_id)
    VALUES (v_ref_id, (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set'));

    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    VALUES (v_col_id, (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'));

    INSERT INTO test_ctx (key, value) VALUES ('col_tempempty', v_col_id::text);
END $$;

-- TEMP-EMPTY (PASS) — remove a única linha E insere uma nova (outra
-- Variant) antes de forçar a checagem -> vazio só INSTANTANEAMENTE
-- entre as duas statements, nunca no momento em que o helper roda.
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_tempempty');
BEGIN
    DELETE FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id
      AND card_variant_id = (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');

    INSERT INTO public.collection_master_set_scope (collection_id, card_variant_id, adopted_by_user_id)
    VALUES (v_col_id, (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a'));

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete IMMEDIATE';

    PERFORM pg_temp.log_result('TEMP-EMPTY - Scope vazio apenas temporariamente (DELETE + INSERT) -> PASS', TRUE, 'nenhuma excecao — estado final tem 1 linha (variant_c)');

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete DEFERRED';
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('TEMP-EMPTY - Scope vazio apenas temporariamente (DELETE + INSERT) -> PASS', FALSE, SQLERRM);
END $$;

-- ================================================================
-- PASSO 6 — GRANTs em pg_temp para authenticated/anon (ANTES da troca
-- de role — mesma correção já aprendida em 02C/02D/02E/5811)
-- ================================================================
GRANT SELECT, INSERT ON test_ctx TO authenticated;
GRANT SELECT ON test_other_cards TO authenticated;
GRANT SELECT ON test_small_set_cards TO authenticated;
GRANT INSERT, SELECT ON test_results TO authenticated;
GRANT USAGE ON SEQUENCE test_results_id_seq TO authenticated;
GRANT EXECUTE ON FUNCTION pg_temp.log_result(TEXT, BOOLEAN, TEXT) TO authenticated;

GRANT SELECT ON test_ctx TO anon;
GRANT INSERT, SELECT ON test_results TO anon;
GRANT USAGE ON SEQUENCE test_results_id_seq TO anon;
GRANT EXECUTE ON FUNCTION pg_temp.log_result(TEXT, BOOLEAN, TEXT) TO anon;

-- ================================================================
-- PASSO 7 — impersonar Owner A (authenticated)
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_a'), true);

DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    PERFORM pg_temp.log_result('PRECOND-ADMIN-A - Owner A authenticated: is_admin() = false', v_is_admin IS FALSE, format('is_admin=%s', v_is_admin));
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner A resolvido em test_ctx e ADMIN (is_admin()=%)', v_is_admin;
    END IF;
END $$;

-- Caso E — SELECT direto do catálogo continua bloqueado para não-admin
DO $$
DECLARE
    v_count INT;
BEGIN
    SELECT count(*) INTO v_count FROM public.card_variant;
    PERFORM pg_temp.log_result('E - SELECT direto em card_variant continua bloqueado para nao-admin (0 linhas)', v_count = 0, format('count=%s', v_count));
END $$;

-- ----------------------------------------------------------------
-- REG-STD — regressão obrigatória de STANDARD_SET pós-5083
-- (correção STAGING-REVISION-01 item 8: MASTER_SET não pode quebrar
-- STANDARD_SET). Reaproveita fixtures A-E já resolvidas no Passo 3
-- (test_card_set, card_multi/variant_a/variant_x_samecard) para
-- denominador-por-Card/satisfação-por-qualquer-Variant/duplicatas/
-- positions Card-oriented; usa um Card Set MENOR dedicado só para o
-- subcaso de completude total, evitando depender do tamanho real
-- (desconhecido) de test_card_set. Não repete toda 5810 — só o
-- mínimo obrigatório listado no mandato desta revisão.
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
    r RECORD;
    v_pos_count_total   INT;
    v_pos_count_missing INT;
    v_pc_sib  UUID;
    v_pc_sib2 UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-REG-STD', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM pg_temp.log_result('REG-STD-0 - Collection criada ja em STANDARD_SET (default)',
        (SELECT completion_policy FROM public.collection WHERE id = v_col_id) = 'STANDARD_SET', NULL);

    -- 1 Physical Card de variant_x_samecard ("irma" de variant_a na
    -- mesma Card) — deve satisfazer a Card de card_multi mesmo sem
    -- nenhuma Physical Card de variant_a.
    -- CORREÇÃO v2.2 (IMPLEMENTATION-FIX-01): sob role authenticated,
    -- authenticated NAO tem INSERT direto em physical_card (por
    -- desenho — so SELECT; escrita e exclusiva via add_physical_cards()).
    -- Fixture passa a usar a RPC publica real, ownership resolvido
    -- pelo proprio auth.uid() dentro da funcao (inventory_a de Owner A,
    -- ja impersonado neste ponto do script).
    SELECT id INTO v_pc_sib
    FROM public.add_physical_cards(
        jsonb_build_array(
            jsonb_build_object(
                'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_x_samecard'),
                'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
            )
        )
    );
    PERFORM public.allocate_physical_cards_to_collection(v_col_id, ARRAY[v_pc_sib]);

    -- Duplicata: 2a Physical Card da MESMA Card (via variant_a, Variant
    -- irma) — nao deve inflar satisfied_positions.
    -- CORREÇÃO v2.2 (IMPLEMENTATION-FIX-01): mesma correção acima.
    SELECT id INTO v_pc_sib2
    FROM public.add_physical_cards(
        jsonb_build_array(
            jsonb_build_object(
                'card_variant_id', (SELECT value FROM test_ctx WHERE key = 'variant_a'),
                'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
            )
        )
    );
    PERFORM public.allocate_physical_cards_to_collection(v_col_id, ARRAY[v_pc_sib2]);

    SELECT * INTO r FROM public.collection_completion_summary(v_col_id);

    PERFORM pg_temp.log_result('REG-STD-1 - STANDARD denominador continua por Card (total_positions = Cards do Card Set, nao Variants)',
        r.total_positions >= 5, format('total_positions=%s', r.total_positions));

    PERFORM pg_temp.log_result('REG-STD-2 - outra Variant da mesma Card satisfaz a posicao (variant_x_samecard satisfaz Card de card_multi)',
        r.satisfied_positions = 1, format('satisfied=%s', r.satisfied_positions));

    PERFORM pg_temp.log_result('REG-STD-3 - duplicatas (2 PC na mesma Card via Variants irmas) nao inflam satisfied_positions',
        r.satisfied_positions = 1, format('satisfied=%s (esperado continuar 1, nao 2)', r.satisfied_positions));

    PERFORM pg_temp.log_result('REG-STD-4 - INCOMPLETE corretamente reportado (1 de >=5 posicoes)',
        r.is_complete IS FALSE, format('is_complete=%s', r.is_complete));

    SELECT count(*) INTO v_pos_count_total FROM public.collection_completion_positions(v_col_id, FALSE);
    SELECT count(*) INTO v_pos_count_missing FROM public.collection_completion_positions(v_col_id, TRUE);

    PERFORM pg_temp.log_result('REG-STD-5 - collection_completion_positions() continua Card-oriented (1 linha por Card, nao por Variant)',
        v_pos_count_total = r.total_positions, format('positions_rows=%s total_positions=%s', v_pos_count_total, r.total_positions));

    PERFORM pg_temp.log_result('REG-STD-6 - p_only_missing continua correto (total - satisfied = missing rows)',
        v_pos_count_missing = r.missing_positions, format('missing_rows=%s missing_positions=%s', v_pos_count_missing, r.missing_positions));

    INSERT INTO test_ctx (key, value) VALUES ('col_reg_std', v_col_id::text);
END $$;

-- REG-STD-7 — COMPLETE genuino, em Card Set pequeno dedicado (nao
-- depende do tamanho real de test_card_set)
-- CORREÇÃO v2.3 (IMPLEMENTATION-FIX-02): small_card_set_id/small_game_id
-- e a lista de Variants (test_small_set_cards) agora sao resolvidos no
-- Passo 3, em contexto privilegiado — REG-STD-7 so LE de test_ctx/
-- test_small_set_cards, nenhuma consulta direta a card/card_variant/
-- card_set/expansion sob role authenticated (Catalogo Editorial e
-- fechado por RLS para usuarios comuns, mesma razao do Caso E; a
-- versao v2.2 ainda resolvia isso aqui e retornava 0 linhas sob
-- Owner A, propagando NULL ate estourar em
-- create_reference_based_card_set_collection(NULL, ...)).
DO $$
DECLARE
    v_col_id UUID;
    r   RECORD;
    rec RECORD;
    v_pc_id UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'small_game_id'),
        'VAL-TEST-02F-COL-REG-STD-COMPLETE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'small_card_set_id')
    );

    FOR rec IN
        SELECT variant_id FROM test_small_set_cards
    LOOP
        SELECT id INTO v_pc_id
        FROM public.add_physical_cards(
            jsonb_build_array(
                jsonb_build_object(
                    'card_variant_id', rec.variant_id::text,
                    'language_id', (SELECT value FROM test_ctx WHERE key = 'language_id')
                )
            )
        );
        PERFORM public.allocate_physical_cards_to_collection(v_col_id, ARRAY[v_pc_id]);
    END LOOP;

    SELECT * INTO r FROM public.collection_completion_summary(v_col_id);

    PERFORM pg_temp.log_result('REG-STD-7 - COMPLETE corretamente reportado (100% das Cards de um Card Set pequeno dedicado)',
        r.is_complete IS TRUE AND r.satisfied_positions = r.total_positions,
        format('total=%s satisfied=%s is_complete=%s', r.total_positions, r.satisfied_positions, r.is_complete));

    INSERT INTO test_ctx (key, value) VALUES ('col_reg_std_complete', v_col_id::text);
END $$;

-- ----------------------------------------------------------------
-- col_payload — fixture dedicada aos testes de contrato de payload de
-- apply_master_set_scope_diff() (5079), via set_collection_completion_
-- policy_to_master_set() (correção STAGING-REVISION-01 item 2/10)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-PAYLOAD', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );
    INSERT INTO test_ctx (key, value) VALUES ('col_payload', v_col_id::text);
END $$;

-- PAYLOAD-NONARRAY (FAIL esperado) — payload nao e um array JSON
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, '"not-an-array"'::jsonb);
    PERFORM pg_temp.log_result('PAYLOAD-NONARRAY - payload nao-array rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-NONARRAY - payload nao-array rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-EMPTY (FAIL esperado) — array vazio (cobertura complementar a EMPTY-1)
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, '[]'::jsonb);
    PERFORM pg_temp.log_result('PAYLOAD-EMPTY - array vazio rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-EMPTY - array vazio rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-NONSTRING (FAIL esperado) — elemento numerico no array
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(1, 2));
    PERFORM pg_temp.log_result('PAYLOAD-NONSTRING - elemento nao-string rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-NONSTRING - elemento nao-string rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-MALFORMED (FAIL esperado) — string que nao e UUID valido
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array('not-a-uuid'));
    PERFORM pg_temp.log_result('PAYLOAD-MALFORMED - UUID malformado rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-MALFORMED - UUID malformado rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-NONEXISTENT (FAIL esperado) — UUID bem formado, mas inexistente
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(gen_random_uuid()::text));
    PERFORM pg_temp.log_result('PAYLOAD-NONEXISTENT - UUID inexistente rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-NONEXISTENT - UUID inexistente rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-FOREIGNSET (FAIL esperado) — UUID valido, mas de outro Card Set
DO $$
DECLARE v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array((SELECT value FROM test_ctx WHERE key = 'foreign_variant')));
    PERFORM pg_temp.log_result('PAYLOAD-FOREIGNSET - Variant de outro Card Set rejeitado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-FOREIGNSET - Variant de outro Card Set rejeitado (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-DUPLICATE (FAIL esperado) — mesmo variant_id repetido no
-- payload; NUNCA normalizado silenciosamente via DISTINCT
DO $$
DECLARE
    v_col_id    UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
    v_variant_a UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(v_variant_a, v_variant_a, v_variant_b));
    PERFORM pg_temp.log_result('PAYLOAD-DUPLICATE - UUID duplicado no payload rejeitado, nunca normalizado via DISTINCT (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-DUPLICATE - UUID duplicado no payload rejeitado, nunca normalizado via DISTINCT (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-DUPLICATE-CANONICAL (FAIL esperado) — novo caso
-- (STAGING-FINAL-REVISION-02 item 2): mesmo UUID valido de variant_a
-- requisitado duas vezes, com representacoes textuais DIFERENTES
-- (lowercase/UPPERCASE) — nao um duplicado textual exato. Prova a
-- correcao de 5079 v2.1 (item 1 — BLOCKER residual): a deteccao de
-- duplicata agora compara por IDENTIDADE UUID (`elem::uuid`), nao por
-- igualdade textual bruta — a v2.0 de 5079 comparava
-- `count(DISTINCT elem)` sobre o texto bruto e deixaria este caso
-- passar (falso negativo), pois 'aaaa...' e 'AAAA...' sao strings
-- diferentes mesmo sendo o MESMO UUID.
DO $$
DECLARE
    v_col_id         UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
    v_variant_a_text TEXT := (SELECT value FROM test_ctx WHERE key = 'variant_a');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(
        v_col_id,
        jsonb_build_array(lower(v_variant_a_text), upper(v_variant_a_text))
    );
    PERFORM pg_temp.log_result('PAYLOAD-DUPLICATE-CANONICAL - mesmo UUID em lowercase/UPPERCASE rejeitado por IDENTIDADE, nao so por igualdade textual (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('PAYLOAD-DUPLICATE-CANONICAL - mesmo UUID em lowercase/UPPERCASE rejeitado por IDENTIDADE, nao so por igualdade textual (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- PAYLOAD-ZERO-CHANGES — apos todas as rejeicoes acima (incluindo
-- PAYLOAD-DUPLICATE-CANONICAL), confirmar que col_payload permanece
-- STANDARD_SET e nunca ganhou nenhuma linha de Scope (zero writes em
-- qualquer das tentativas)
DO $$
DECLARE
    v_col_id      UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_payload');
    v_scope_count INT;
    v_policy      TEXT;
BEGIN
    SELECT count(*) INTO v_scope_count FROM public.collection_master_set_scope WHERE collection_id = v_col_id;
    SELECT completion_policy INTO v_policy FROM public.collection WHERE id = v_col_id;

    PERFORM pg_temp.log_result('PAYLOAD-ZERO-CHANGES - nenhuma escrita em Scope nem em completion_policy apos todas as rejeicoes de contrato de payload (incluindo PAYLOAD-DUPLICATE-CANONICAL)',
        v_scope_count = 0 AND v_policy = 'STANDARD_SET', format('scope_count=%s policy=%s', v_scope_count, v_policy));
END $$;

-- ----------------------------------------------------------------
-- col_a_master — Caso A (criar/usar Master válido) + DUPLICATES +
-- EXACT-MATCH + INCOMPLETE/COMPLETE + POSITIONS + KEEP + Caso B via
-- RPC + REMOVE + ADD
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id  UUID;
    v_variant_a UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_variant_d UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_d');
    v_added INT; v_removed INT; v_kept INT; v_policy TEXT;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-A-MASTER', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    SELECT completion_policy, scope_added_count, scope_removed_count, scope_kept_count
      INTO v_policy, v_added, v_removed, v_kept
    FROM public.set_collection_completion_policy_to_master_set(
        v_col_id, jsonb_build_array(v_variant_a, v_variant_b, v_variant_c)
    );

    PERFORM pg_temp.log_result('A - STANDARD->MASTER com Scope {A,B,C} (PASS)',
        v_policy = 'MASTER_SET' AND v_added = 3 AND v_removed = 0 AND v_kept = 0,
        format('policy=%s added=%s removed=%s kept=%s', v_policy, v_added, v_removed, v_kept));

    INSERT INTO test_ctx (key, value) VALUES ('col_a_master', v_col_id::text);
END $$;

-- Alocação real de Physical Cards (pc_b1/pc_b2/pc_samecard) via RPC,
-- como Owner A
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_rows   INT;
BEGIN
    SELECT count(*) INTO v_rows FROM public.allocate_physical_cards_to_collection(
        v_col_id,
        ARRAY[
            (SELECT value::uuid FROM test_ctx WHERE key = 'pc_b1'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'pc_b2'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'pc_samecard')
        ]
    );
    PERFORM pg_temp.log_result('setup - alocacao inicial (pc_b1/pc_b2/pc_samecard) em col_a_master', v_rows = 3, format('rows=%s', v_rows));
END $$;

-- DUPLICATES + EXACT-MATCH + INCOMPLETE (summary), MASTER-POSITIONS only_missing
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    r RECORD;
    v_missing_count INT;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary(v_col_id);

    PERFORM pg_temp.log_result('DUPLICATES - pc_b1/pc_b2 (mesma Variant B) satisfazem 1 unico requisito',
        r.total_positions = 3 AND r.satisfied_positions = 1 AND r.missing_positions = 2,
        format('total=%s satisfied=%s missing=%s', r.total_positions, r.satisfied_positions, r.missing_positions));

    PERFORM pg_temp.log_result('EXACT-MATCH - pc_samecard (mesma Card de A, Variant diferente) NAO satisfaz A',
        r.satisfied_positions = 1, format('satisfied=%s (deveria ser so B)', r.satisfied_positions));

    PERFORM pg_temp.log_result('INCOMPLETE - is_complete=false com 2/3 posicoes faltando', r.is_complete IS FALSE, NULL);

    SELECT count(*) INTO v_missing_count
    FROM public.collection_master_set_scope_positions(v_col_id, TRUE);
    PERFORM pg_temp.log_result('POSITIONS - only_missing=TRUE retorna exatamente 2 linhas (A e C)', v_missing_count = 2, format('rows=%s', v_missing_count));
END $$;

-- Completar (pc_a1/pc_c1) -> COMPLETE
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    r RECORD;
    v_missing_count INT;
BEGIN
    PERFORM public.allocate_physical_cards_to_collection(
        v_col_id,
        ARRAY[
            (SELECT value::uuid FROM test_ctx WHERE key = 'pc_a1'),
            (SELECT value::uuid FROM test_ctx WHERE key = 'pc_c1')
        ]
    );

    SELECT * INTO r FROM public.collection_completion_summary(v_col_id);
    PERFORM pg_temp.log_result('COMPLETE - 3/3 posicoes satisfeitas -> is_complete=true',
        r.total_positions = 3 AND r.satisfied_positions = 3 AND r.is_complete IS TRUE,
        format('total=%s satisfied=%s is_complete=%s', r.total_positions, r.satisfied_positions, r.is_complete));

    SELECT count(*) INTO v_missing_count
    FROM public.collection_master_set_scope_positions(v_col_id, TRUE);
    PERFORM pg_temp.log_result('POSITIONS - only_missing=TRUE retorna 0 linhas apos completar', v_missing_count = 0, format('rows=%s', v_missing_count));
END $$;

-- KEEP preserva adopted_at/adopted_by (replace com o MESMO conjunto)
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_a UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_before_at  TIMESTAMPTZ;
    v_before_by  UUID;
    v_after_at   TIMESTAMPTZ;
    v_after_by   UUID;
    v_added INT; v_removed INT; v_kept INT;
BEGIN
    SELECT adopted_at, adopted_by_user_id INTO v_before_at, v_before_by
    FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;

    SELECT scope_added_count, scope_removed_count, scope_kept_count
      INTO v_added, v_removed, v_kept
    FROM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_a, v_variant_b, v_variant_c));

    SELECT adopted_at, adopted_by_user_id INTO v_after_at, v_after_by
    FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;

    PERFORM pg_temp.log_result('KEEP - replace com o mesmo conjunto: added=0 removed=0 kept=3',
        v_added = 0 AND v_removed = 0 AND v_kept = 3, format('added=%s removed=%s kept=%s', v_added, v_removed, v_kept));

    PERFORM pg_temp.log_result('KEEP - adopted_at/adopted_by_user_id de A INALTERADOS',
        v_before_at = v_after_at AND v_before_by = v_after_by,
        format('before=(%s,%s) after=(%s,%s)', v_before_at, v_before_by, v_after_at, v_after_by));
END $$;

-- Caso B via RPC (FAIL esperado) — replace incluindo Variant de Set
-- errado -> zero mudanças
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_foreign   UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'foreign_variant');
    v_count_before INT;
    v_count_after  INT;
BEGIN
    SELECT count(*) INTO v_count_before FROM public.collection_master_set_scope WHERE collection_id = v_col_id;

    PERFORM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_b, v_variant_c, v_foreign));

    PERFORM pg_temp.log_result('B - replace_master_set_scope com Variant de Set errado (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    SELECT count(*) INTO v_count_after FROM public.collection_master_set_scope WHERE collection_id = v_col_id;
    PERFORM pg_temp.log_result('B - replace_master_set_scope com Variant de Set errado (FAIL esperado)', TRUE, SQLERRM);
    PERFORM pg_temp.log_result('B - zero mudancas no Scope apos rejeicao', v_count_before = v_count_after, format('before=%s after=%s', v_count_before, v_count_after));
END $$;

-- REMOVE-only (replace {B,C}, removendo A) — nao toca Physical Card/Allocation
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_pc_a1     UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'pc_a1');
    v_added INT; v_removed INT; v_kept INT;
    v_pc_exists BOOLEAN;
    v_alloc_exists BOOLEAN;
BEGIN
    SELECT scope_added_count, scope_removed_count, scope_kept_count
      INTO v_added, v_removed, v_kept
    FROM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_b, v_variant_c));

    PERFORM pg_temp.log_result('REMOVE - replace {B,C} remove A do Scope: added=0 removed=1 kept=2',
        v_added = 0 AND v_removed = 1 AND v_kept = 2, format('added=%s removed=%s kept=%s', v_added, v_removed, v_kept));

    v_pc_exists := EXISTS (SELECT 1 FROM public.physical_card WHERE id = v_pc_a1);
    v_alloc_exists := EXISTS (SELECT 1 FROM public.collection_allocation WHERE physical_card_id = v_pc_a1 AND collection_id = v_col_id);

    PERFORM pg_temp.log_result('REMOVE - pc_a1 permanece intacto e alocado (REMOVE so afeta Scope)',
        v_pc_exists AND v_alloc_exists, format('pc_exists=%s alloc_exists=%s', v_pc_exists, v_alloc_exists));
END $$;

-- ADD-provenance (replace {B,C,D}, adiciona D)
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_variant_d UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_d');
    v_owner_a   UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a');
    v_added INT; v_removed INT; v_kept INT;
    v_d_by UUID; v_d_at TIMESTAMPTZ;
BEGIN
    SELECT scope_added_count, scope_removed_count, scope_kept_count
      INTO v_added, v_removed, v_kept
    FROM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_b, v_variant_c, v_variant_d));

    PERFORM pg_temp.log_result('ADD - replace {B,C,D} adiciona D: added=1 removed=0 kept=2',
        v_added = 1 AND v_removed = 0 AND v_kept = 2, format('added=%s removed=%s kept=%s', v_added, v_removed, v_kept));

    SELECT adopted_by_user_id, adopted_at INTO v_d_by, v_d_at
    FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id AND card_variant_id = v_variant_d;

    PERFORM pg_temp.log_result('ADD - D tem nova proveniencia (adopted_by=Owner A, adopted_at preenchido)',
        v_d_by = v_owner_a AND v_d_at IS NOT NULL, format('adopted_by=%s adopted_at=%s', v_d_by, v_d_at));
END $$;

-- ----------------------------------------------------------------
-- EMPTY-1 — nivel RPC: p_card_variant_ids = [] rejeitado imediatamente
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-EMPTY1', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, '[]'::jsonb);

    PERFORM pg_temp.log_result('EMPTY-1 - p_card_variant_ids=[] rejeitado no nivel da RPC (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('EMPTY-1 - p_card_variant_ids=[] rejeitado no nivel da RPC (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- ----------------------------------------------------------------
-- col_a_archive — ARCHIVED-READ + ARCHIVED-MUT-1/2/3
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
    v_variant_e UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_e');
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-ARCHIVE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(v_variant_e));
    PERFORM public.archive_collection(v_col_id);

    INSERT INTO test_ctx (key, value) VALUES ('col_a_archive', v_col_id::text);
END $$;

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_archive');
    v_variant_e UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_e');
    r RECORD;
    v_pos_count INT;
BEGIN
    SELECT * INTO r FROM public.collection_completion_summary(v_col_id);
    PERFORM pg_temp.log_result('ARCHIVED-READ - collection_completion_summary retorna dados de Collection arquivada',
        r.total_positions = 1, format('total=%s', r.total_positions));

    SELECT count(*) INTO v_pos_count FROM public.collection_master_set_scope_positions(v_col_id, FALSE);
    PERFORM pg_temp.log_result('ARCHIVED-READ - collection_master_set_scope_positions retorna dados de Collection arquivada',
        v_pos_count = 1, format('rows=%s', v_pos_count));
END $$;

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_archive');
    v_variant_e UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_e');
BEGIN
    PERFORM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_e));
    PERFORM pg_temp.log_result('ARCHIVED-MUT-1 - replace_master_set_scope em Collection arquivada (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('ARCHIVED-MUT-1 - replace_master_set_scope em Collection arquivada (FAIL esperado)', TRUE, SQLERRM);
END $$;

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_archive');
BEGIN
    PERFORM public.set_collection_completion_policy_to_standard_set(v_col_id);
    PERFORM pg_temp.log_result('ARCHIVED-MUT-2 - MASTER->STANDARD em Collection arquivada (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('ARCHIVED-MUT-2 - MASTER->STANDARD em Collection arquivada (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- col_std_archive — fixture dedicada a ARCHIVED-MUT-3, genuinamente
-- STANDARD_SET + ARCHIVED (correção STAGING-REVISION-01 item 9: a
-- fixture antiga reaproveitava col_a_archive, que já era MASTER_SET —
-- a exceção acontecia de qualquer forma pelo check de lifecycle_status,
-- mas não provava especificamente que uma Collection STANDARD_SET
-- arquivada bloqueia a transição para MASTER_SET).
DO $$
DECLARE
    v_col_id UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-STD-ARCHIVE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM pg_temp.log_result('ARCHIVED-MUT-3-fixture - Collection criada em STANDARD_SET (nao MASTER_SET)',
        (SELECT completion_policy FROM public.collection WHERE id = v_col_id) = 'STANDARD_SET', NULL);

    PERFORM public.archive_collection(v_col_id);

    INSERT INTO test_ctx (key, value) VALUES ('col_std_archive', v_col_id::text);
END $$;

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_std_archive');
BEGIN
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, NULL);
    PERFORM pg_temp.log_result('ARCHIVED-MUT-3 - STANDARD->MASTER em Collection genuinamente STANDARD_SET+arquivada (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN check_violation THEN
    PERFORM pg_temp.log_result('ARCHIVED-MUT-3 - STANDARD->MASTER em Collection genuinamente STANDARD_SET+arquivada (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- ----------------------------------------------------------------
-- col_a_reuse — M2S-PRESERVE + S2M-REUSE (caminho B)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
    v_variant_a UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_before_at TIMESTAMPTZ;
    v_before_by UUID;
    v_scope_count_after_standard INT;
    v_policy TEXT;
    v_after_at  TIMESTAMPTZ;
    v_after_by  UUID;
    v_added INT; v_removed INT; v_kept INT;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-REUSE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(v_variant_a, v_variant_b));

    SELECT adopted_at, adopted_by_user_id INTO v_before_at, v_before_by
    FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;

    PERFORM public.set_collection_completion_policy_to_standard_set(v_col_id);

    SELECT count(*) INTO v_scope_count_after_standard
    FROM public.collection_master_set_scope WHERE collection_id = v_col_id;

    PERFORM pg_temp.log_result('M2S-PRESERVE - MASTER->STANDARD preserva as 2 linhas de Scope',
        v_scope_count_after_standard = 2, format('scope_count=%s', v_scope_count_after_standard));

    SELECT completion_policy, scope_added_count, scope_removed_count, scope_kept_count
      INTO v_policy, v_added, v_removed, v_kept
    FROM public.set_collection_completion_policy_to_master_set(v_col_id, NULL);

    SELECT adopted_at, adopted_by_user_id INTO v_after_at, v_after_by
    FROM public.collection_master_set_scope
    WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;

    PERFORM pg_temp.log_result('S2M-REUSE - STANDARD->MASTER caminho B (sem novo Scope) reativa MASTER_SET, kept_count = contagem real do Scope persistido (correcao STAGING-REVISION-01 item 3)',
        v_policy = 'MASTER_SET' AND v_added = 0 AND v_removed = 0 AND v_kept = 2,
        format('policy=%s added=%s removed=%s kept=%s', v_policy, v_added, v_removed, v_kept));

    PERFORM pg_temp.log_result('S2M-REUSE - Scope persistido reaproveitado sem tocar adopted_at/adopted_by',
        v_before_at = v_after_at AND v_before_by = v_after_by,
        format('before=(%s,%s) after=(%s,%s)', v_before_at, v_before_by, v_after_at, v_after_by));
END $$;

-- ----------------------------------------------------------------
-- col_a_diffscope — CASO G OBRIGATÓRIO
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
    v_variant_a UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_a');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_variant_c UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_c');
    v_variant_d UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_d');
    v_owner_a   UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'owner_a');
    v_a_at TIMESTAMPTZ; v_a_by UUID;
    v_b_at TIMESTAMPTZ; v_b_by UUID;
    v_c_at TIMESTAMPTZ; v_c_by UUID;
    v_policy TEXT; v_added INT; v_removed INT; v_kept INT;
    v_a_at2 TIMESTAMPTZ; v_a_by2 UUID;
    v_b_at2 TIMESTAMPTZ; v_b_by2 UUID;
    v_c_at2 TIMESTAMPTZ; v_c_by2 UUID;
    v_d_by2 UUID; v_d_at2 TIMESTAMPTZ;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-DIFFSCOPE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    -- Ciclo 1: STANDARD -> MASTER com {A,B,C}
    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(v_variant_a, v_variant_b, v_variant_c));

    SELECT adopted_at, adopted_by_user_id INTO v_a_at, v_a_by FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;
    SELECT adopted_at, adopted_by_user_id INTO v_b_at, v_b_by FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_b;
    SELECT adopted_at, adopted_by_user_id INTO v_c_at, v_c_by FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_c;

    -- Volta para STANDARD_SET, Scope {A,B,C} preservado inativo
    PERFORM public.set_collection_completion_policy_to_standard_set(v_col_id);

    -- Ciclo 2 (CASO G): STANDARD -> MASTER com requested {A,B,C,D} —
    -- compara contra o Scope PERSISTIDO ({A,B,C}), mesmo com policy
    -- atual = STANDARD_SET no momento da chamada.
    SELECT completion_policy, scope_added_count, scope_removed_count, scope_kept_count
      INTO v_policy, v_added, v_removed, v_kept
    FROM public.set_collection_completion_policy_to_master_set(
        v_col_id, jsonb_build_array(v_variant_a, v_variant_b, v_variant_c, v_variant_d)
    );

    PERFORM pg_temp.log_result('G - STANDARD->MASTER com requested {A,B,C,D} sobre persistido {A,B,C}: added=1 removed=0 kept=3',
        v_policy = 'MASTER_SET' AND v_added = 1 AND v_removed = 0 AND v_kept = 3,
        format('policy=%s added=%s removed=%s kept=%s', v_policy, v_added, v_removed, v_kept));

    SELECT adopted_at, adopted_by_user_id INTO v_a_at2, v_a_by2 FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_a;
    SELECT adopted_at, adopted_by_user_id INTO v_b_at2, v_b_by2 FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_b;
    SELECT adopted_at, adopted_by_user_id INTO v_c_at2, v_c_by2 FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_c;
    SELECT adopted_at, adopted_by_user_id INTO v_d_at2, v_d_by2 FROM public.collection_master_set_scope WHERE collection_id = v_col_id AND card_variant_id = v_variant_d;

    PERFORM pg_temp.log_result('G - A/B/C sao KEEP: adopted_at/adopted_by IDENTICOS aos capturados no ciclo 1',
        v_a_at = v_a_at2 AND v_a_by = v_a_by2 AND v_b_at = v_b_at2 AND v_b_by = v_b_by2 AND v_c_at = v_c_at2 AND v_c_by = v_c_by2,
        format('A(%s,%s)->(%s,%s) B(%s,%s)->(%s,%s) C(%s,%s)->(%s,%s)',
            v_a_at, v_a_by, v_a_at2, v_a_by2, v_b_at, v_b_by, v_b_at2, v_b_by2, v_c_at, v_c_by, v_c_at2, v_c_by2));

    PERFORM pg_temp.log_result('G - D e ADD: nova proveniencia (adopted_by=Owner A, adopted_at preenchido)',
        v_d_by2 = v_owner_a AND v_d_at2 IS NOT NULL, format('adopted_by=%s adopted_at=%s', v_d_by2, v_d_at2));

    INSERT INTO test_ctx (key, value) VALUES ('col_a_diffscope', v_col_id::text);
END $$;

-- ----------------------------------------------------------------
-- col_a_cascade — criação/transição, exclusão via RPC (a prova
-- estrutural do CASCADE acontece no Passo 8, ja privilegiado)
-- ----------------------------------------------------------------
DO $$
DECLARE
    v_col_id UUID;
    v_variant_e UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_e');
    v_deleted_id UUID;
BEGIN
    SELECT id INTO v_col_id FROM public.create_reference_based_card_set_collection(
        (SELECT value::uuid FROM test_ctx WHERE key = 'game_id_test'),
        'VAL-TEST-02F-COL-CASCADE', NULL,
        (SELECT value::uuid FROM test_ctx WHERE key = 'storage_a'),
        (SELECT value::uuid FROM test_ctx WHERE key = 'test_card_set')
    );

    PERFORM public.set_collection_completion_policy_to_master_set(v_col_id, jsonb_build_array(v_variant_e));

    SELECT id INTO v_deleted_id FROM public.delete_collection(v_col_id);

    PERFORM pg_temp.log_result('CASCADE-DELETE - delete_collection() de Collection MASTER_SET com Scope tem sucesso',
        v_deleted_id = v_col_id, format('deleted_id=%s', v_deleted_id));

    INSERT INTO test_ctx (key, value) VALUES ('col_a_cascade', v_col_id::text);
END $$;

-- ================================================================
-- PASSO 8 — voltar ao contexto privilegiado, provar CASCADE
-- estruturalmente (checagem diferida forçada + contagem privilegiada
-- de resíduo, que a RLS de Owner nao consegue mais ver pois a
-- Collection ja nao existe)
-- ================================================================
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_cascade');
    v_residual_scope INT;
BEGIN
    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete IMMEDIATE';

    PERFORM pg_temp.log_result('CASCADE-DELETE - checagem diferida forcada apos DELETE+CASCADE nao levanta excecao', TRUE, 'Collection ja nao existe — helper retorna PASS incondicional');

    EXECUTE 'SET CONSTRAINTS trg_collection_master_set_scope_presence, trg_collection_master_set_scope_presence_on_delete DEFERRED';

    SELECT count(*) INTO v_residual_scope FROM public.collection_master_set_scope WHERE collection_id = v_col_id;
    PERFORM pg_temp.log_result('CASCADE-DELETE - zero linhas residuais de Scope para a Collection excluida (leitura privilegiada)', v_residual_scope = 0, format('residual=%s', v_residual_scope));
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('CASCADE-DELETE - checagem diferida forcada apos DELETE+CASCADE nao levanta excecao', FALSE, SQLERRM);
END $$;

-- ================================================================
-- PASSO 9 — impersonar Owner B (authenticated) — Caso C
-- ================================================================
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claim.sub', (SELECT value FROM test_ctx WHERE key = 'owner_b'), true);

DO $$
DECLARE
    v_is_admin BOOLEAN;
BEGIN
    SELECT public.is_admin() INTO v_is_admin;
    PERFORM pg_temp.log_result('PRECOND-ADMIN-B - Owner B authenticated: is_admin() = false', v_is_admin IS FALSE, format('is_admin=%s', v_is_admin));
    IF v_is_admin IS NOT FALSE THEN
        RAISE EXCEPTION 'fixture invalido: Owner B resolvido em test_ctx e ADMIN (is_admin()=%)', v_is_admin;
    END IF;
END $$;

-- Caso C-1 — Owner B tenta replace_master_set_scope() na Collection do Owner A
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
    v_msg_foreign TEXT;
BEGIN
    PERFORM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_b));
    PERFORM pg_temp.log_result('C-1 - Owner B tenta replace_master_set_scope() em Collection do Owner A (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    v_msg_foreign := SQLERRM;
    PERFORM pg_temp.log_result('C-1 - Owner B tenta replace_master_set_scope() em Collection do Owner A (FAIL esperado)', TRUE, v_msg_foreign);

    -- Caso C-2 — mesma RPC com UUID aleatorio (inexistente) DEVE
    -- produzir a MESMA mensagem — nao-enumeracao.
    DECLARE
        v_msg_nonexistent TEXT;
    BEGIN
        PERFORM public.replace_master_set_scope(gen_random_uuid(), jsonb_build_array(v_variant_b));
        PERFORM pg_temp.log_result('C-2 - replace_master_set_scope() com UUID inexistente (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
    EXCEPTION WHEN OTHERS THEN
        v_msg_nonexistent := SQLERRM;
        PERFORM pg_temp.log_result('C-2 - replace_master_set_scope() com UUID inexistente (FAIL esperado)', TRUE, v_msg_nonexistent);
        PERFORM pg_temp.log_result('C - mensagens de "Collection alheia" e "Collection inexistente" sao IDENTICAS (nao-enumeravel)',
            v_msg_foreign = v_msg_nonexistent, format('alheia=%s inexistente=%s', v_msg_foreign, v_msg_nonexistent));
    END;
END $$;

-- Caso C-3 — Owner B tenta set_collection_completion_policy_to_standard_set() na Collection do Owner A
DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
BEGIN
    PERFORM public.set_collection_completion_policy_to_standard_set(v_col_id);
    PERFORM pg_temp.log_result('C-3 - Owner B tenta set_collection_completion_policy_to_standard_set() em Collection do Owner A (FAIL esperado)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('C-3 - Owner B tenta set_collection_completion_policy_to_standard_set() em Collection do Owner A (FAIL esperado)', TRUE, SQLERRM);
END $$;

-- ================================================================
-- PASSO 10 — impersonar anônimo — Caso D
-- ================================================================
SELECT set_config('role', 'anon', true);
SELECT set_config('request.jwt.claim.sub', '', true);

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
    v_variant_b UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'variant_b');
BEGIN
    PERFORM public.replace_master_set_scope(v_col_id, jsonb_build_array(v_variant_b));
    PERFORM pg_temp.log_result('D - anonimo tenta replace_master_set_scope() (FAIL esperado — permission denied)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN insufficient_privilege THEN
    PERFORM pg_temp.log_result('D - anonimo tenta replace_master_set_scope() (FAIL esperado — permission denied)', TRUE, SQLERRM);
WHEN OTHERS THEN
    -- alguns clientes reportam 42501 sob um SQLSTATE distinto do bloco
    -- nomeado acima dependendo da via (GRANT vs RLS) — capturado aqui
    -- como rede de seguranca, ainda contando como FAIL esperado.
    PERFORM pg_temp.log_result('D - anonimo tenta replace_master_set_scope() (FAIL esperado — permission denied)', TRUE, SQLERRM);
END $$;

DO $$
DECLARE
    v_col_id UUID := (SELECT value::uuid FROM test_ctx WHERE key = 'col_a_master');
BEGIN
    PERFORM public.collection_master_set_scope_positions(v_col_id, FALSE);
    PERFORM pg_temp.log_result('D - anonimo tenta collection_master_set_scope_positions() (FAIL esperado — permission denied)', FALSE, 'nenhum erro levantado — BUG');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.log_result('D - anonimo tenta collection_master_set_scope_positions() (FAIL esperado — permission denied)', TRUE, SQLERRM);
END $$;

-- ================================================================
-- PASSO 11 — voltar ao contexto privilegiado — auditoria de segurança
-- ================================================================
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

-- SEC-1..5 — EXECUTE das 5 RPCs/funções expostas: PUBLIC/anon sem
-- EXECUTE, authenticated com EXECUTE (mesmo padrao SEC-I/J de 5810)
DO $$
DECLARE
    r RECORD;
    v_public_sem_execute BOOLEAN;
    v_anon_pode          BOOLEAN;
    v_authenticated_pode BOOLEAN;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('replace_master_set_scope', 'uuid, jsonb'),
            ('set_collection_completion_policy_to_master_set', 'uuid, jsonb'),
            ('set_collection_completion_policy_to_standard_set', 'uuid'),
            ('collection_master_set_scope_positions', 'uuid, boolean'),
            ('collection_completion_summary', 'uuid')
        ) AS t(proname, args)
    LOOP
        v_public_sem_execute := NOT has_function_privilege('public', format('public.%I(%s)', r.proname, r.args), 'EXECUTE');
        v_anon_pode := has_function_privilege('anon', format('public.%I(%s)', r.proname, r.args), 'EXECUTE');
        v_authenticated_pode := has_function_privilege('authenticated', format('public.%I(%s)', r.proname, r.args), 'EXECUTE');

        PERFORM pg_temp.log_result(format('SEC-1 - %s: PUBLIC sem EXECUTE', r.proname), v_public_sem_execute, NULL);
        PERFORM pg_temp.log_result(format('SEC-2 - %s: anon sem EXECUTE', r.proname), v_anon_pode IS NOT TRUE, format('anon_pode=%s', v_anon_pode));
        PERFORM pg_temp.log_result(format('SEC-3 - %s: authenticated com EXECUTE', r.proname), v_authenticated_pode IS TRUE, format('authenticated_pode=%s', v_authenticated_pode));
    END LOOP;
END $$;

-- SEC-4 — collection_master_set_scope: authenticated so tem SELECT,
-- nenhum INSERT/UPDATE/DELETE de tabela; anon nao tem privilegio algum
DO $$
DECLARE
    v_auth_select BOOLEAN;
    v_auth_insert BOOLEAN;
    v_auth_update BOOLEAN;
    v_auth_delete BOOLEAN;
    v_anon_any    BOOLEAN;
BEGIN
    v_auth_select := has_table_privilege('authenticated', 'public.collection_master_set_scope', 'SELECT');
    v_auth_insert := has_table_privilege('authenticated', 'public.collection_master_set_scope', 'INSERT');
    v_auth_update := has_table_privilege('authenticated', 'public.collection_master_set_scope', 'UPDATE');
    v_auth_delete := has_table_privilege('authenticated', 'public.collection_master_set_scope', 'DELETE');
    v_anon_any := has_table_privilege('anon', 'public.collection_master_set_scope', 'SELECT')
               OR has_table_privilege('anon', 'public.collection_master_set_scope', 'INSERT');

    PERFORM pg_temp.log_result('SEC-4 - authenticated tem SELECT e NAO tem INSERT/UPDATE/DELETE em collection_master_set_scope',
        v_auth_select AND NOT v_auth_insert AND NOT v_auth_update AND NOT v_auth_delete,
        format('select=%s insert=%s update=%s delete=%s', v_auth_select, v_auth_insert, v_auth_update, v_auth_delete));

    PERFORM pg_temp.log_result('SEC-4 - anon sem nenhum privilegio em collection_master_set_scope', NOT v_anon_any, NULL);
END $$;

-- SEC-5 — SECURITY DEFINER + search_path='' nas 5 funções
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.proname, p.prosecdef, p.proconfig
        FROM pg_proc p
        WHERE p.proname IN (
            'replace_master_set_scope', 'set_collection_completion_policy_to_master_set',
            'set_collection_completion_policy_to_standard_set', 'collection_master_set_scope_positions',
            'collection_completion_summary'
        )
    LOOP
        PERFORM pg_temp.log_result(format('SEC-5 - %s: SECURITY DEFINER', r.proname), r.prosecdef IS TRUE, NULL);
        -- Correção STAGING-REVISION-01 item 7 (BLOCKER de falso
        -- negativo): a representação física real de SET search_path=''
        -- em pg_proc.proconfig e 'search_path=""' (com aspas), nao
        -- 'search_path='. Comparar cfg = 'search_path=' exato nunca
        -- casava, fazendo o teste reportar FAIL para uma função
        -- corretamente implementada. split_part isola o valor apos o
        -- '=' e aceita tanto '' quanto '""' apos trim de aspas.
        PERFORM pg_temp.log_result(format('SEC-5 - %s: search_path vazio', r.proname),
            EXISTS (
                SELECT 1 FROM unnest(r.proconfig) cfg
                WHERE split_part(cfg, '=', 1) = 'search_path'
                  AND trim(both '"' from split_part(cfg, '=', 2)) = ''
            ), format('proconfig=%s', r.proconfig));
    END LOOP;
END $$;

-- SEC-6 — funções internas (helper/trigger) sem EXECUTE para nenhum papel de cliente
DO $$
DECLARE
    r RECORD;
    v_any_client_execute BOOLEAN;
BEGIN
    FOR r IN
        SELECT fname, args FROM (VALUES
            ('check_master_set_scope_presence', 'uuid'),
            ('apply_master_set_scope_diff', 'uuid, jsonb'),
            ('validate_master_set_scope_eligibility', ''),
            ('reject_collection_master_set_scope_update', ''),
            ('enforce_collection_master_set_scope_presence', ''),
            ('enforce_scope_master_set_presence_on_delete', '')
        ) AS t(fname, args)
    LOOP
        v_any_client_execute := has_function_privilege('anon', format('public.%I(%s)', r.fname, r.args), 'EXECUTE')
                              OR has_function_privilege('authenticated', format('public.%I(%s)', r.fname, r.args), 'EXECUTE');
        PERFORM pg_temp.log_result(format('SEC-6 - %s: nenhum EXECUTE para anon/authenticated (funcao interna)', r.fname), NOT v_any_client_execute, NULL);
    END LOOP;
END $$;

-- Z — fixtures de teste existem dentro da transação (serão desfeitas no ROLLBACK)
DO $$
DECLARE
    v_test_collections INT;
BEGIN
    SELECT count(*) INTO v_test_collections FROM public.collection WHERE name LIKE 'VAL-TEST-02F-%';
    PERFORM pg_temp.log_result('Z - fixtures de teste existem dentro da transacao (serao desfeitas no ROLLBACK)', v_test_collections > 0, format('collections=%s', v_test_collections));
END $$;

-- ================================================================
-- PASSO 12 — leitura final consolidada (ainda dentro da transação)
-- ================================================================
SELECT case_label, passed, detail FROM test_results ORDER BY id;

SELECT count(*) AS total_casos, count(*) FILTER (WHERE passed) AS passaram, count(*) FILTER (WHERE NOT passed) AS falharam
FROM test_results;

-- ================================================================
-- GOVERNANÇA DO RESULTADO (mesma disciplina de 5810, mandato
-- STAGING-EXECUTION-SAFETY-FIX-01 — nenhum RAISE EXCEPTION aqui; a
-- bateria SEMPRE executa ROLLBACK, independente de test_results.passed).
--
--   falharam = 0  -> pode prosseguir (redigir 5813, depois README,
--                    depois relatório final ENTREGA — nenhuma
--                    aplicação real ainda, mandato 02F-STAGING-01
--                    proibe migrations/promotion/implementation).
--   falharam > 0  -> reportar os case_label com passed=false antes de
--                    qualquer novo passo.
-- ================================================================

-- ================================================================
-- PASSO 13 — desfazer tudo
-- ================================================================
ROLLBACK;

-- ================================================================
-- PASSO 14 (fora de transação) — prova de zero resíduo
-- ================================================================
SELECT count(*) AS collections_residuais FROM public.collection WHERE name LIKE 'VAL-TEST-02F-%';
-- Esperado: 0

SELECT count(*) AS physical_card_count_depois
FROM public.physical_card
WHERE inventory_id IN (SELECT id FROM public.inventory);
-- Esperado: igual ao Passo -1

SELECT count(*) AS scope_rows_residuais
FROM public.collection_master_set_scope s
JOIN public.collection c ON c.id = s.collection_id
WHERE c.name LIKE 'VAL-TEST-02F-%';
-- Esperado: 0
