/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5821 - Validate Bulk Operation Foundation (BULK-01)
Versão......: 1.3
Status......: HARNESS EXECUTÁVEL — EXECUTADO em 2026-09-07
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-07 (criado em
               COLLECTIONS-BULK-01-PHYSICAL-PROPOSAL-01;
               v1.1 em -REVISION-01;
               v1.2 em -POST-AUDIT-HARDENING-01;
               v1.3 em -POST-AUDIT-HARDENING-REVISION-02)

v1.3 — quatro correções. Nenhum rótulo novo entra; o que muda é o
rigor de casos que já existiam.
  (a) `S01` LIA `polroles` e não o usava no veredito. Agora `{0}`
      (PUBLIC — a policy vale para todos os papéis) faz parte da
      condição de PASS, junto da expressão e do WITH CHECK nulo;
  (b) `X01`/`X02` REESCRITOS. A prova por
      `xmin = pg_current_xact_id()::xid` da v1.2 estava ERRADA:
      `pg_current_xact_id()` devolve o xid da transação de TOPO,
      enquanto linhas inseridas dentro de subtransações — e este
      harness inserta quase tudo dentro de blocos `DO` com
      `EXCEPTION`, que são subtransações — carregam o SUBXID. A
      comparação falharia para linhas legítimas e passaria a impressão
      de resíduo alheio. Substituída por: BASELINE medido ANTES de
      qualquer escrita, obrigatoriamente 0; e o zero resíduo REAL
      passa a ser provado FORA do harness, num postcheck pós-ROLLBACK.
      Nenhum caso aqui afirma que o rollback aconteceu — ele ainda não
      aconteceu quando os casos rodam;
  (c) CONTRATO DE EXECUÇÃO corrigido: `service_role` NÃO serve como
      papel de execução direta — `EXECUTE` foi revogado dele nos três
      helpers, e o grupo `C` falharia com `42501`;
  (d) `S03` passa a exigir `anon` também sem UPDATE/DELETE, e `S04`
      passa a cobrir `service_role` em
      TRUNCATE/REFERENCES/TRIGGER/MAINTAIN.

v1.2 — provas FORTALECIDAS. A semântica de BULK-01 não muda; o que
muda é o quanto cada caso realmente demonstra.
  (a) grupo `R` NOVO — contrato de `result_summary` (`5146`): SQL NULL,
      `'null'::jsonb`, array, string, number e boolean rejeitados;
      JSON object aceito; e o CHECK de tabela provado por UPDATE
      direto, independente da função;
  (b) `E08` NOVO — o CHECK `chk_bulk_operation_result_summary_object`
      existe com a definição esperada;
  (c) `E03` passava com "existe UMA constraint chamada assim". Agora
      compara a LISTA ORDENADA de colunas da UNIQUE;
  (d) `E04` passava com "existe UMA FK para auth.users". Agora prova
      que a coluna local é `owner_user_id` e a remota é `id`;
  (e) `S01` passava com nome + `polcmd`. Agora compara a EXPRESSÃO
      efetiva da policy, os papéis alvo e a ausência de WITH CHECK;
  (f) `S04` afirmava testar MAINTAIN e não testava. `MAINTAIN` existe
      desde o PostgreSQL 17 e foi CONFIRMADO disponível neste servidor
      (17.6) — agora é testado de verdade;
  (g) `S05` afirmava "EXECUTE revogado de PUBLIC" testando só três
      papéis nomeados. Agora prova pelo catálogo: `proacl` NÃO NULL
      (NULL significaria o default `EXECUTE TO PUBLIC`) e nenhuma
      entrada com `grantee = 0`, que é como PUBLIC aparece em
      `aclexplode`;
  (h) `X02` era `passed = TRUE` constante — não provava nada. Passou a
      medir, por `xmin = pg_current_xact_id()`.
      **SUPERSEDIDO PELA v1.3, item (b): essa medição estava errada.**
      Mantido aqui só para o histórico da mudança.

v1.1 — alinhamento a `5142` v1.1 / `5144` v1.1, mais UM DEFEITO PRÓPRIO
corrigido:
  (a) `E02` passa a exigir `preview_fingerprint` NOT NULL;
  (b) `E07` inverte de "índice existe" para "SOMENTE índices
      estruturais" — o índice especulativo foi removido;
  (c) `S02`/`S06` passam a exigir que `authenticated` NÃO tenha
      caminho de acesso direto algum;
  (d) `C02` passa a exercitar REPLAY sobre claim JÁ COMPLETADO;
  (e) **novo `C06`** — mesmo hash com `result_summary` NULL levanta
      erro e NUNCA vira REPLAY;
  (f) **DEFEITO PRÓPRIO DA v1.0**: o grupo `C` chamava
      `claim_bulk_operation()` sob `SET LOCAL ROLE authenticated`,
      enquanto `S05` exige `EXECUTE` revogado de `authenticated` — as
      duas coisas não podem ser verdadeiras ao mesmo tempo, e o grupo
      inteiro teria abortado com `permission denied`. Corrigido: o
      grupo `C` agora define apenas `request.jwt.claims` e permanece
      privilegiado, que é exatamente como o chamador real opera (a RPC
      `SECURITY DEFINER` de BULK-02/BULK-04 roda como `postgres`);
  (g) todos os INSERTs diretos passam a informar `preview_fingerprint`,
      agora NOT NULL.

Descrição...:
Harness FUNCIONAL fail-closed de `5142`–`5146`. Executado APÓS aplicar
as cinco Queries.

GATE DE ACEITE (v1.3)
---------------------
    TOTAL 39 / PASS 36 / FAIL 0 / NOT PROVEN 3

O número foi RECONTADO mecanicamente após as mudanças da v1.3 e
coincide com o da v1.2 porque a v1.3 não cria nem remove rótulo algum
— ela endurece `S01`, `S03`, `S04`, `X01` e `X02` no lugar. Da v1.1
para a v1.2 ele havia subido de 30 para 39 (grupo `R` + `E08`).

Os três NOT PROVEN são **exatamente** `K01`, `K02` e `K03` — a prova de
concorrência entre DUAS SESSÕES REAIS. Qualquer outro NOT PROVEN, ou
qualquer FAIL, é STOP.

RESULTADO DA EXECUÇÃO REAL (2026-09-07)
---------------------------------------
Gate atingido exatamente: **TOTAL 39 / PASS 36 / FAIL 0 / NOT
PROVEN 3**, com os 3 NOT PROVEN sendo `K01`/`K02`/`K03` e nenhum
`*-ABORT` presente. Baseline 0 e postcheck pós-`ROLLBACK` = 0.

`K01`/`K02`/`K03` foram **provados em seguida**, fora deste arquivo, em
DUAS sessões `psql` persistentes (A e B, com role temporária de teste
detentora de EXECUTE explícito nos helpers e sem acesso direto à
tabela) mais um observador externo one-shot via SQL Editor do
Supabase — ver `CONCURRENCY-PROOF-BULK-CLAIM.sql` v1.2 e
`docs/05d-colecoes-e-usuarios.md`. Somados, os 39 casos estão
**efetivamente provados**. Este arquivo continua gravando os três como
NOT PROVEN de propósito: é o que ELE consegue demonstrar sozinho, e
converter isso em PASS aqui seria mentira de instrumento.

Contagem de rótulos — MEDIDA no arquivo, não estimada:
    F ... F01 F-ABORT                                    (2)
    E ... E01..E08                                       (8)
    S ... S01..S06                                       (6)
    T ... T01..T05 T-ABORT                               (6)
    C ... C01..C06 C-ABORT                               (7)
    R ... R01..R08 R-ABORT                               (9)
    K ... K01 K02 K03                                    (3)
    X ... X01 X02                                        (2)
                                 rótulos ESTÁTICOS  =    43

`F-ABORT`, `T-ABORT`, `C-ABORT` e `R-ABORT` são ramos FAIL-ONLY: só são
gravados dentro de `EXCEPTION WHEN OTHERS` e sempre com
`passed = FALSE`. No caminho saudável nenhum deles é alcançável.

    estáticos                     43
    − fail-only                  − 4
    = TOTAL de runtime            39
        dos quais NOT PROVEN       3   (K01, K02, K03)
        dos quais PASS            36
        dos quais FAIL             0

Qualquer `*-ABORT` presente = STOP.

POR QUE `K01`–`K03` NÃO SÃO AUTOMATIZÁVEIS AQUI
-----------------------------------------------
Exigem duas sessões persistentes e simultâneas, com a transação da
sessão A ABERTA enquanto B tenta o mesmo claim. Foi MEDIDO em
2026-09-07 que o canal MCP `execute_sql` não preserva sessão nem
transação entre chamadas. São a mesma classe de `C04`/`R18` do `5818`,
e recebem o mesmo tratamento: gravados como NOT PROVEN, JAMAIS
convertidos em PASS artificial, e provados por roteiro manual —
`CONCURRENCY-PROOF-BULK-CLAIM.sql`, nesta mesma pasta.

TÉCNICA OBRIGATÓRIA DO GRUPO T
------------------------------
O trigger de `5143` é `DEFERRABLE INITIALLY DEFERRED` e este harness
NUNCA comita. Para provar que "o COMMIT falha", o disparo é forçado com

    SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;

dentro de um SAVEPOINT, e o savepoint é revertido em seguida — o que
também restaura o modo DEFERRED e descarta os eventos pendentes do
bloco. Sem isso, T02/T04 seriam impossíveis de provar sem comitar.

CONTRATO DE EXECUÇÃO
--------------------
- PAPEL: `postgres`, ou outra role ADMINISTRATIVA com `EXECUTE`
  EXPLÍCITO sobre `claim_bulk_operation`, `complete_bulk_operation` e
  `validate_bulk_operation_result_summary_presence`.

  `service_role` NÃO SERVE como role SQL direta: `EXECUTE` foi
  REVOGADO dela nos três helpers (é justamente o que `S05` exige), e o
  grupo `C` abortaria com `42501 permission denied for function`.
  O mesmo vale para `authenticated` e `anon`.

  O harness NUNCA chama os helpers sob `SET ROLE`. O único `SET ROLE`
  do arquivo está em `S06`, e existe para provar AUSÊNCIA de acesso.

- TUDO em `BEGIN ... ROLLBACK`.
- FAIL-CLOSED: nenhum caso passa por omissão; erro inesperado nunca
  vira PASS; `NOT PROVEN` (passed IS NULL) é terceiro estado.
- PROTOCOLO EM TRÊS CHAMADAS:
      CALL 1 — do `BEGIN;` até o `SELECT` final, INCLUSIVE.
      CALL 2 — `ROLLBACK;`
      CALL 3 — POSTCHECK DE RESÍDUO REAL, obrigatório:

          SELECT count(*) AS deve_ser_zero FROM public.bulk_operation;

        Esperado: 0. Este postcheck é a ÚNICA prova de zero resíduo.
        Nenhum caso DENTRO do harness afirma que o ROLLBACK ocorreu —
        quando os casos rodam, ele ainda não ocorreu.

  NOTA DE CANAL (medida): o executor não preserva sessão entre
  chamadas — a CALL 1 encerra com ROLLBACK IMPLÍCITO (o arquivo abre
  `BEGIN;` e nunca emite `COMMIT;`); a CALL 2 é confirmação e no-op.
  Isso NÃO dispensa a CALL 3: o rollback implícito é comportamento do
  canal, e comportamento de canal se verifica, não se presume.

PRÉ-REQUISITOS
--------------
- `5142`, `5143`, `5144`, `5145` e **`5146`** aplicadas.
- >= 2 `auth.users` (para `S06`). Medido em 2026-09-07: 3.
- `public.bulk_operation` VAZIA antes de executar. `X01` mede esse
  BASELINE, capturado ANTES de qualquer escrita do harness, e exige 0.
  Linha pré-existente faz `X01` FALHAR, e isso é intencional: o
  harness escreve na tabela real, e o postcheck da CALL 3 só significa
  "zero resíduo" se o baseline era zero.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO (2026-09-07). Ledger e
evidencia de validacao no README.md desta pasta.
================================================================
*/

BEGIN;

SET LOCAL client_min_messages = WARNING;

-- =================================================================
-- INFRAESTRUTURA
-- =================================================================
CREATE TEMP TABLE _v (
    seq        SERIAL PRIMARY KEY,
    grp        TEXT NOT NULL,
    case_label TEXT NOT NULL,
    passed     BOOLEAN,          -- NULL = NOT PROVEN
    observed   TEXT,
    expected   TEXT
) ON COMMIT DROP;

CREATE TEMP TABLE _fx (k TEXT PRIMARY KEY, v UUID) ON COMMIT DROP;

-- =================================================================
-- BASELINE — capturado AQUI, antes de QUALQUER escrita do harness.
--
-- Esta e a primeira instrucao que toca public.bulk_operation. Nenhum
-- bloco DO rodou ainda; a primeira tentativa de INSERT so acontece em
-- E05, mais abaixo. O valor gravado aqui e, portanto, o estado da
-- tabela ANTES do harness — e X01 exige que seja 0.
-- =================================================================
CREATE TEMP TABLE _bl (n INTEGER NOT NULL) ON COMMIT DROP;
INSERT INTO _bl SELECT count(*) FROM public.bulk_operation;

GRANT ALL ON _v, _fx TO authenticated;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE _v_seq_seq TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp._rec(
    p_grp TEXT, p_label TEXT, p_passed BOOLEAN,
    p_observed TEXT DEFAULT NULL, p_expected TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    INSERT INTO _v (grp, case_label, passed, observed, expected)
    VALUES (p_grp, p_label, p_passed, p_observed, p_expected);
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._expect_error(
    p_grp TEXT, p_label TEXT, p_sql TEXT, p_fragment TEXT
) RETURNS VOID LANGUAGE plpgsql AS $fn$
DECLARE v_msg TEXT; v_state TEXT; v_raised BOOLEAN := FALSE;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_raised := TRUE; v_msg := SQLERRM; v_state := SQLSTATE;
    END;

    IF NOT v_raised THEN
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'NENHUM erro levantado', 'erro contendo: ' || p_fragment);
    ELSIF position(lower(p_fragment) in lower(v_msg)) > 0 THEN
        PERFORM pg_temp._rec(p_grp, p_label, TRUE,
            v_state || ' ' || left(v_msg, 150), 'erro contendo: ' || p_fragment);
    ELSE
        PERFORM pg_temp._rec(p_grp, p_label, FALSE,
            'erro INESPERADO: ' || v_state || ' ' || left(v_msg, 150),
            'erro contendo: ' || p_fragment);
    END IF;
END; $fn$;

-- Sessao authenticated COMPLETA (claims + SET ROLE). Usada apenas onde
-- o objetivo e provar AUSENCIA de privilegio (grupo S).
CREATE OR REPLACE FUNCTION pg_temp._as_user(p_user UUID)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_user::text, 'role', 'authenticated')::text, TRUE);
    EXECUTE 'SET LOCAL ROLE authenticated';
END; $fn$;

-- Apenas os CLAIMS, SEM trocar de role. E assim que o chamador real
-- opera: a RPC SECURITY DEFINER de BULK-02/BULK-04 roda como postgres e
-- so precisa que auth.uid() resolva o dono. Usar SET ROLE aqui seria
-- incoerente com S05 (EXECUTE revogado de authenticated) e faria o
-- grupo C abortar com permission denied.
CREATE OR REPLACE FUNCTION pg_temp._as_claims(p_user UUID)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', p_user::text, 'role', 'authenticated')::text, TRUE);
END; $fn$;

CREATE OR REPLACE FUNCTION pg_temp._as_admin()
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    EXECUTE 'RESET ROLE';
    PERFORM set_config('request.jwt.claims', '', TRUE);
END; $fn$;

-- search_path EFETIVAMENTE vazio (nao apenas presente).
CREATE OR REPLACE FUNCTION pg_temp._empty_search_path(p_oid OID)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_elem TEXT; v_val TEXT;
BEGIN
    SELECT c INTO v_elem
      FROM pg_proc p, unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS c
     WHERE p.oid = p_oid AND c LIKE 'search_path=%'
     LIMIT 1;
    IF v_elem IS NULL THEN RETURN FALSE; END IF;
    v_val := substring(v_elem from length('search_path=') + 1);
    RETURN btrim(COALESCE(v_val, ''), '''" ') = '';
END; $fn$;

-- =================================================================
-- FIXTURE — fail-loud. Nenhum usuario e fabricado.
-- =================================================================
DO $blk$
DECLARE v_owner UUID; v_other UUID;
BEGIN
    SELECT id INTO v_owner FROM auth.users ORDER BY created_at, id LIMIT 1;
    SELECT id INTO v_other FROM auth.users
     WHERE id <> v_owner ORDER BY created_at, id LIMIT 1;

    IF v_owner IS NULL OR v_other IS NULL THEN
        RAISE EXCEPTION
          'FIXTURE ABORT — sao necessarios >= 2 auth.users (owner=%, other=%). O harness NAO fabrica usuario.',
          v_owner, v_other;
    END IF;

    INSERT INTO _fx VALUES ('owner', v_owner), ('other', v_other);

    PERFORM pg_temp._rec('F','F01 - fixture SOMENTE LEITURA: dois auth.users distintos disponiveis',
        v_owner IS NOT NULL AND v_other IS NOT NULL AND v_owner <> v_other,
        format('owner=%s other=%s', v_owner, v_other), 'dois usuarios distintos');
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('F','F-ABORT - fixture abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'fixture completa');
END $blk$;

-- =================================================================
-- GRUPO E — ESTRUTURA
-- =================================================================
DO $blk$
DECLARE v_oid OID; v_cols TEXT; v_uq_cols TEXT; v_fk_desc TEXT; v_chk_def TEXT;
BEGIN
    v_oid := 'public.bulk_operation'::regclass;

    PERFORM pg_temp._rec('E','E01 - tabela existe, owner postgres, RLS habilitada',
        (SELECT c.relrowsecurity AND pg_get_userbyid(c.relowner)='postgres'
           FROM pg_class c WHERE c.oid = v_oid),
        (SELECT format('rls=%s owner=%s', c.relrowsecurity, pg_get_userbyid(c.relowner))
           FROM pg_class c WHERE c.oid = v_oid),
        'rls=t, owner=postgres');

    SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||
                      CASE WHEN a.attnotnull THEN ':NN' ELSE ':NULL' END, ', ' ORDER BY a.attnum)
      INTO v_cols
      FROM pg_attribute a
     WHERE a.attrelid = v_oid AND a.attnum > 0 AND NOT a.attisdropped;

    PERFORM pg_temp._rec('E','E02 - colunas exatas (tipos e nullability); preview_fingerprint NOT NULL; SO result_summary e NULLABLE; SEM coluna status',
        v_cols = 'id:uuid:NN, owner_user_id:uuid:NN, operation_type:text:NN, idempotency_key:uuid:NN, request_hash:text:NN, preview_fingerprint:text:NN, result_summary:jsonb:NULL, created_at:timestamp with time zone:NN',
        v_cols,
        'id/owner_user_id/operation_type/idempotency_key/request_hash/preview_fingerprint/created_at NOT NULL; APENAS result_summary NULLABLE; nenhuma coluna status');

    -- E03 — nao basta "existe UMA constraint com esse nome". A UNIQUE e
    -- o MECANISMO DE SERIALIZACAO de 5144: se as colunas ou a ordem
    -- delas divergirem, a serializacao muda de significado. Comparamos a
    -- LISTA ORDENADA de colunas, resolvida por attnum a partir de conkey.
    SELECT string_agg(att.attname, ',' ORDER BY u.ord)
      INTO v_uq_cols
      FROM pg_constraint k
      CROSS JOIN LATERAL unnest(k.conkey) WITH ORDINALITY AS u(attnum, ord)
      JOIN pg_attribute att ON att.attrelid = k.conrelid AND att.attnum = u.attnum
     WHERE k.conrelid = v_oid
       AND k.contype  = 'u'
       AND k.conname  = 'uq_bulk_operation_owner_type_key';

    PERFORM pg_temp._rec('E','E03 - 1 PK e a UNIQUE e EXATAMENTE (owner_user_id, operation_type, idempotency_key), nesta ordem',
        (SELECT count(*) FILTER (WHERE k.contype='p') = 1
            AND count(*) FILTER (WHERE k.contype='u') = 1
           FROM pg_constraint k WHERE k.conrelid = v_oid)
        AND v_uq_cols = 'owner_user_id,operation_type,idempotency_key',
        format('colunas_da_unique=[%s] | p+u=[%s]',
               COALESCE(v_uq_cols,'(constraint ausente)'),
               (SELECT COALESCE(string_agg(k.conname||'('||k.contype::text||')', ', ' ORDER BY k.conname), '(nenhuma)')
                  FROM pg_constraint k WHERE k.conrelid = v_oid AND k.contype IN ('p','u'))),
        '1 PK + 1 UNIQUE com colunas owner_user_id,operation_type,idempotency_key');

    -- E04 — idem: prova a coluna LOCAL e a coluna REMOTA, nao apenas
    -- "aponta para auth.users". Uma FK para a coluna errada de
    -- auth.users passaria no teste anterior.
    SELECT format('%s -> %s(%s)',
             (SELECT string_agg(a1.attname, ',' ORDER BY u1.ord)
                FROM unnest(k.conkey) WITH ORDINALITY u1(an, ord)
                JOIN pg_attribute a1 ON a1.attrelid = k.conrelid AND a1.attnum = u1.an),
             k.confrelid::regclass::text,
             (SELECT string_agg(a2.attname, ',' ORDER BY u2.ord)
                FROM unnest(k.confkey) WITH ORDINALITY u2(an, ord)
                JOIN pg_attribute a2 ON a2.attrelid = k.confrelid AND a2.attnum = u2.an))
      INTO v_fk_desc
      FROM pg_constraint k
     WHERE k.conrelid = v_oid AND k.contype = 'f';

    PERFORM pg_temp._rec('E','E04 - FK unica: coluna LOCAL owner_user_id -> auth.users(id), ON UPDATE RESTRICT ON DELETE RESTRICT',
        (SELECT count(*) = 1 FROM pg_constraint k
          WHERE k.conrelid = v_oid AND k.contype='f'
            AND k.confupdtype='r' AND k.confdeltype='r')
        AND v_fk_desc = 'owner_user_id -> auth.users(id)',
        format('%s | def=[%s]',
               COALESCE(v_fk_desc,'(nenhuma FK)'),
               (SELECT COALESCE(string_agg(pg_get_constraintdef(k.oid), ' | '), '(nenhuma)')
                  FROM pg_constraint k WHERE k.conrelid = v_oid AND k.contype='f')),
        'owner_user_id -> auth.users(id), RESTRICT/RESTRICT');

    -- E08 — CHECK do contrato de result_summary (5146). Comparado pela
    -- DEFINICAO normalizada devolvida pelo servidor, nao pelo nome.
    SELECT pg_get_constraintdef(k.oid) INTO v_chk_def
      FROM pg_constraint k
     WHERE k.conrelid = v_oid AND k.contype = 'c'
       AND k.conname  = 'chk_bulk_operation_result_summary_object';

    PERFORM pg_temp._rec('E','E08 - CHECK chk_bulk_operation_result_summary_object presente: result_summary NULL ou JSON object',
        v_chk_def IS NOT NULL
        AND position('jsonb_typeof' in v_chk_def) > 0
        AND position('''object''' in v_chk_def) > 0
        AND position('IS NULL' in v_chk_def) > 0,
        COALESCE(v_chk_def, '(constraint AUSENTE — 5146 nao aplicada?)'),
        'CHECK com result_summary IS NULL OR jsonb_typeof(...) = ''object''');

    -- E07 — SOMENTE indices ESTRUTURAIS. Exatamente 2: o da PK e o da
    -- UNIQUE de identidade/serializacao. Nenhum indice especulativo:
    -- o antigo ix_bulk_operation_owner_created foi REMOVIDO por nao ter
    -- workload aprovado. Este caso falha tanto se faltar um estrutural
    -- quanto se aparecer um extra.
    PERFORM pg_temp._rec('E','E07 - SOMENTE indices estruturais (PK + UNIQUE); nenhum indice especulativo',
        (SELECT count(*) = 2
             AND count(*) FILTER (WHERE x.indisprimary) = 1
             AND count(*) FILTER (WHERE i.relname='uq_bulk_operation_owner_type_key') = 1
           FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid
          WHERE x.indrelid = v_oid),
        (SELECT COALESCE(string_agg(i.relname, ', ' ORDER BY i.relname), '(nenhum)')
           FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid WHERE x.indrelid = v_oid),
        'exatamente 2: PK + uq_bulk_operation_owner_type_key');
END $blk$;

-- E05 — vocabulario FECHADO (comportamental, sob savepoint)
DO $blk$
DECLARE v_owner UUID;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';

    PERFORM pg_temp._expect_error('E','E05 - operation_type fora do vocabulario e REJEITADO pelo CHECK',
        format($q$INSERT INTO public.bulk_operation
                    (owner_user_id, operation_type, idempotency_key, request_hash,
                     preview_fingerprint, result_summary)
                  VALUES (%L::uuid, 'NAO_EXISTE', gen_random_uuid(), 'h', 'fp', '{}'::jsonb)$q$, v_owner),
        'chk_bulk_operation_type');
END $blk$;

-- E06 — trigger diferido, evento e timing
DO $blk$
BEGIN
    PERFORM pg_temp._rec('E','E06 - constraint trigger AFTER INSERT OR UPDATE, DEFERRABLE INITIALLY DEFERRED',
        (SELECT t.tgdeferrable AND t.tginitdeferred AND t.tgconstraint <> 0
             -- tgtype: bit0=ROW, bit2=INSERT(4), bit4=UPDATE(16); AFTER = bit1 desligado
             AND (t.tgtype & 1) = 1
             AND (t.tgtype & 4) = 4
             AND (t.tgtype & 16) = 16
             AND (t.tgtype & 2) = 0
           FROM pg_trigger t
          WHERE t.tgrelid='public.bulk_operation'::regclass
            AND t.tgname='trg_bulk_operation_result_summary_presence'),
        (SELECT format('tgtype=%s deferrable=%s initdeferred=%s', t.tgtype, t.tgdeferrable, t.tginitdeferred)
           FROM pg_trigger t
          WHERE t.tgrelid='public.bulk_operation'::regclass
            AND t.tgname='trg_bulk_operation_result_summary_presence'),
        'ROW, AFTER, INSERT+UPDATE, DEFERRABLE INITIALLY DEFERRED');
END $blk$;

-- =================================================================
-- GRUPO S — SEGURANCA
-- =================================================================
DO $blk$
DECLARE v_oid OID; v_qual TEXT; v_wc TEXT; v_roles TEXT;
BEGIN
    v_oid := 'public.bulk_operation'::regclass;

    -- S01 — a policy existe como DEFESA EM PROFUNDIDADE. Nome e polcmd
    -- nao provam nada sobre o ESCOPO: uma policy chamada
    -- "..._select_own" com USING (true) passaria. Comparamos a
    -- EXPRESSAO EFETIVA devolvida por pg_get_expr, mais os papeis alvo
    -- ({0} = todos) e a ausencia de WITH CHECK (policy so de leitura).
    SELECT pg_get_expr(po.polqual, po.polrelid),
           pg_get_expr(po.polwithcheck, po.polrelid),
           po.polroles::text
      INTO v_qual, v_wc, v_roles
      FROM pg_policy po WHERE po.polrelid = v_oid LIMIT 1;

    -- polroles = '{0}' e como o catalogo representa PUBLIC, ou seja: a
    -- policy se aplica a TODOS os papeis. Ate a v1.2 este valor era
    -- LIDO e exibido, mas nao entrava no veredito — uma policy
    -- restrita a um papel especifico (ex.: TO service_role) passaria,
    -- e deixaria authenticated sem escopo por dono no dia em que um
    -- GRANT de leitura fosse concedido. Agora entra na condicao.
    PERFORM pg_temp._rec('S','S01 - policy unica de SELECT, PERMISSIVE, aplicada a TODOS os papeis (polroles={0}), com EXPRESSAO efetiva owner-scoped e sem WITH CHECK',
        (SELECT count(*) = 1 FROM pg_policy po WHERE po.polrelid = v_oid)
        AND (SELECT po.polcmd = 'r' AND po.polpermissive
                AND po.polname = 'bulk_operation_select_own'
               FROM pg_policy po WHERE po.polrelid = v_oid LIMIT 1)
        AND v_roles = '{0}'
        AND v_qual  = '(owner_user_id = ( SELECT auth.uid() AS uid))'
        AND v_wc IS NULL,
        format('nome+cmd=[%s] polroles=%s qual=[%s] withcheck=[%s]',
               (SELECT COALESCE(string_agg(po.polname||'('||po.polcmd::text||')', ', '), '(nenhuma)')
                  FROM pg_policy po WHERE po.polrelid = v_oid),
               COALESCE(v_roles,'?'), COALESCE(v_qual,'(nulo)'), COALESCE(v_wc,'(nulo)')),
        'bulk_operation_select_own, cmd=r, permissive, polroles={0} (PUBLIC), qual=(owner_user_id = ( SELECT auth.uid() AS uid)), sem WITH CHECK');

    -- S02 — LEDGER INTERNO: authenticated NAO tem NEM SELECT.
    -- Leitura e escrita so acontecem dentro das funcoes SECURITY
    -- DEFINER de 5144/5145.
    PERFORM pg_temp._rec('S','S02 - authenticated SEM SELECT e sem INSERT/UPDATE/DELETE (ledger interno, sem acesso direto)',
        NOT has_table_privilege('authenticated', v_oid, 'SELECT')
        AND NOT has_table_privilege('authenticated', v_oid, 'INSERT')
        AND NOT has_table_privilege('authenticated', v_oid, 'UPDATE')
        AND NOT has_table_privilege('authenticated', v_oid, 'DELETE'),
        format('select=%s insert=%s update=%s delete=%s',
               has_table_privilege('authenticated', v_oid,'SELECT'),
               has_table_privilege('authenticated', v_oid,'INSERT'),
               has_table_privilege('authenticated', v_oid,'UPDATE'),
               has_table_privilege('authenticated', v_oid,'DELETE')),
        'SELECT/INSERT/UPDATE/DELETE = f');

    -- S03 — os QUATRO verbos DML para os DOIS papeis. Ate a v1.2 anon
    -- so era testado em SELECT/INSERT; UPDATE e DELETE ficavam de fora
    -- sem razao nenhuma.
    PERFORM pg_temp._rec('S','S03 - anon e service_role SEM SELECT/INSERT/UPDATE/DELETE (os quatro verbos, para os dois papeis)',
        NOT has_table_privilege('anon', v_oid, 'SELECT')
        AND NOT has_table_privilege('anon', v_oid, 'INSERT')
        AND NOT has_table_privilege('anon', v_oid, 'UPDATE')
        AND NOT has_table_privilege('anon', v_oid, 'DELETE')
        AND NOT has_table_privilege('service_role', v_oid, 'SELECT')
        AND NOT has_table_privilege('service_role', v_oid, 'INSERT')
        AND NOT has_table_privilege('service_role', v_oid, 'UPDATE')
        AND NOT has_table_privilege('service_role', v_oid, 'DELETE'),
        format('anon[sel=%s ins=%s upd=%s del=%s] svc[sel=%s ins=%s upd=%s del=%s]',
               has_table_privilege('anon', v_oid,'SELECT'),
               has_table_privilege('anon', v_oid,'INSERT'),
               has_table_privilege('anon', v_oid,'UPDATE'),
               has_table_privilege('anon', v_oid,'DELETE'),
               has_table_privilege('service_role', v_oid,'SELECT'),
               has_table_privilege('service_role', v_oid,'INSERT'),
               has_table_privilege('service_role', v_oid,'UPDATE'),
               has_table_privilege('service_role', v_oid,'DELETE')),
        'todos f');

    -- S04 — os quatro privilegios NAO-DML, para os TRES papeis de
    -- aplicacao. `service_role` entrou na v1.3: ele estava coberto em
    -- DML por S03, mas TRUNCATE/REFERENCES/TRIGGER/MAINTAIN ficavam
    -- fora, e `REVOKE ALL` de 5142 os revoga tambem — logo havia o que
    -- provar.
    --
    -- MAINTAIN existe desde o PostgreSQL 17 e foi CONFIRMADO
    -- disponivel neste servidor (17.6) antes de entrar aqui. Ate a v1.1
    -- o rotulo o mencionava sem testar.
    PERFORM pg_temp._rec('S','S04 - TRUNCATE/REFERENCES/TRIGGER/MAINTAIN revogados de authenticated, anon E service_role (MAINTAIN testado, nao apenas citado)',
        NOT has_table_privilege('authenticated', v_oid, 'TRUNCATE')
        AND NOT has_table_privilege('authenticated', v_oid, 'REFERENCES')
        AND NOT has_table_privilege('authenticated', v_oid, 'TRIGGER')
        AND NOT has_table_privilege('authenticated', v_oid, 'MAINTAIN')
        AND NOT has_table_privilege('anon', v_oid, 'TRUNCATE')
        AND NOT has_table_privilege('anon', v_oid, 'REFERENCES')
        AND NOT has_table_privilege('anon', v_oid, 'TRIGGER')
        AND NOT has_table_privilege('anon', v_oid, 'MAINTAIN')
        AND NOT has_table_privilege('service_role', v_oid, 'TRUNCATE')
        AND NOT has_table_privilege('service_role', v_oid, 'REFERENCES')
        AND NOT has_table_privilege('service_role', v_oid, 'TRIGGER')
        AND NOT has_table_privilege('service_role', v_oid, 'MAINTAIN'),
        format('auth[trunc=%s ref=%s trig=%s maint=%s] anon[trunc=%s ref=%s trig=%s maint=%s] svc[trunc=%s ref=%s trig=%s maint=%s]',
               has_table_privilege('authenticated', v_oid,'TRUNCATE'),
               has_table_privilege('authenticated', v_oid,'REFERENCES'),
               has_table_privilege('authenticated', v_oid,'TRIGGER'),
               has_table_privilege('authenticated', v_oid,'MAINTAIN'),
               has_table_privilege('anon', v_oid,'TRUNCATE'),
               has_table_privilege('anon', v_oid,'REFERENCES'),
               has_table_privilege('anon', v_oid,'TRIGGER'),
               has_table_privilege('anon', v_oid,'MAINTAIN'),
               has_table_privilege('service_role', v_oid,'TRUNCATE'),
               has_table_privilege('service_role', v_oid,'REFERENCES'),
               has_table_privilege('service_role', v_oid,'TRIGGER'),
               has_table_privilege('service_role', v_oid,'MAINTAIN')),
        'todos f');

    -- S05 — PUBLIC provado pelo CATALOGO, nao por nome de papel.
    --
    -- Duas condicoes, ambas necessarias:
    --   (1) proacl IS NOT NULL. proacl NULL significa "privilegios
    --       default", e o default de funcao e EXECUTE TO PUBLIC — ou
    --       seja, NULL seria justamente o caso ruim;
    --   (2) nenhuma entrada de aclexplode com grantee = 0, que e como
    --       PUBLIC aparece no catalogo.
    -- Testar so os tres papeis nomeados nao cobre PUBLIC.
    PERFORM pg_temp._rec('S','S05 - as 3 funcoes: SECURITY DEFINER, search_path vazio, owner postgres, EXECUTE ausente para PUBLIC (grantee=0) e para anon/authenticated/service_role',
        (SELECT count(*) = 3 FROM pg_proc p
          WHERE p.pronamespace='public'::regnamespace
            AND p.proname IN ('validate_bulk_operation_result_summary_presence',
                              'claim_bulk_operation','complete_bulk_operation')
            AND p.prosecdef
            AND pg_temp._empty_search_path(p.oid)
            AND pg_get_userbyid(p.proowner) = 'postgres'
            AND p.proacl IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                             WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
            AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
            AND NOT has_function_privilege('anon',          p.oid, 'EXECUTE')
            AND NOT has_function_privilege('service_role',  p.oid, 'EXECUTE')),
        (SELECT COALESCE(string_agg(format('%s[secdef=%s,sp=%s,owner=%s,acl=%s,public_exec=%s,auth=%s]',
                 p.proname, p.prosecdef, pg_temp._empty_search_path(p.oid),
                 pg_get_userbyid(p.proowner),
                 COALESCE(array_to_string(p.proacl,'+'),'NULL(=default EXECUTE TO PUBLIC)'),
                 EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                          WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
                 has_function_privilege('authenticated', p.oid,'EXECUTE')), ' | '), '(nenhuma)')
           FROM pg_proc p
          WHERE p.pronamespace='public'::regnamespace
            AND p.proname IN ('validate_bulk_operation_result_summary_presence',
                              'claim_bulk_operation','complete_bulk_operation')),
        '3 funcoes conformes, proacl NAO NULL e sem grantee=0');
END $blk$;

-- S06 — AUSENCIA DE CAMINHO DE ACESSO, provada EM RUNTIME.
--
-- Com authenticated sem GRANT algum (S02), uma sessao authenticated nem
-- chega a avaliar RLS: o SELECT e barrado por privilegio (42501).
-- Provar isso em runtime e mais forte que ler o catalogo de ACLs — nao
-- depende de eu interpretar has_table_privilege corretamente.
DO $blk$
DECLARE v_owner UUID; v_other UUID; v_id UUID;
        v_estado TEXT; v_msg TEXT; v_leu INTEGER;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    SELECT v INTO v_other FROM _fx WHERE k='other';

    INSERT INTO public.bulk_operation
        (owner_user_id, operation_type, idempotency_key, request_hash,
         preview_fingerprint, result_summary)
    VALUES (v_owner, 'REGISTER_PHYSICAL_CARDS', gen_random_uuid(), 'hash-s06',
            'fp-s06', '{"ok":true}'::jsonb)
    RETURNING id INTO v_id;

    PERFORM pg_temp._as_user(v_other);
    BEGIN
        SELECT count(*) INTO v_leu FROM public.bulk_operation b WHERE b.id = v_id;
    EXCEPTION WHEN OTHERS THEN
        v_estado := SQLSTATE; v_msg := SQLERRM;
    END;
    PERFORM pg_temp._as_admin();

    PERFORM pg_temp._rec('S','S06 - RUNTIME: sessao authenticated NAO tem caminho de acesso a tabela (barrada por privilegio, antes mesmo da RLS)',
        v_estado = '42501',
        COALESCE(v_estado||' '||left(v_msg,120),
                 'SEM ERRO — leitura retornou '||COALESCE(v_leu::text,'?')||' linha(s)'),
        '42501 insufficient_privilege');
END $blk$;

-- =================================================================
-- GRUPO T — INVARIANTE DE COMMIT (constraint trigger diferido)
--
-- Todos os casos usam SAVEPOINT + SET CONSTRAINTS ... IMMEDIATE para
-- forcar o disparo sem comitar, e revertem o savepoint em seguida —
-- o que tambem restaura o modo DEFERRED e descarta eventos pendentes.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_id UUID; v_erro TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';

    ---------------------------------------------------------------- T01
    BEGIN
        INSERT INTO public.bulk_operation
            (owner_user_id, operation_type, idempotency_key, request_hash,
             preview_fingerprint, result_summary)
        VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-t01','fp-t01','{"created":3}'::jsonb)
        RETURNING id INTO v_id;

        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
        PERFORM pg_temp._rec('T','T01 - claim COMPLETO passa na verificacao de commit',
            TRUE, 'sem erro ao forcar IMMEDIATE', 'sem erro');
        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence DEFERRED;
    EXCEPTION WHEN OTHERS THEN
        PERFORM pg_temp._rec('T','T01 - claim COMPLETO passa na verificacao de commit',
            FALSE, SQLSTATE||' '||left(SQLERRM,150), 'sem erro');
    END;

    ---------------------------------------------------------------- T02
    v_erro := NULL;
    BEGIN
        INSERT INTO public.bulk_operation
            (owner_user_id, operation_type, idempotency_key, request_hash,
             preview_fingerprint, result_summary)
        VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-t02','fp-t02', NULL);

        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLSTATE||' '||SQLERRM;
    END;

    PERFORM pg_temp._rec('T','T02 - linha com result_summary NULL IMPEDE o commit [invariante I4/R9]',
        v_erro IS NOT NULL AND position('result_summary NULL' in v_erro) > 0,
        COALESCE(left(v_erro,150), 'NENHUM erro levantado'),
        'erro contendo: result_summary NULL');

    ---------------------------------------------------------------- T03
    -- Prova de que o trigger avalia o ESTADO FINAL e nao NEW: o claim
    -- entra NULL (que reprovaria se NEW fosse inspecionado) e so depois
    -- e completado.
    v_erro := NULL;
    BEGIN
        INSERT INTO public.bulk_operation
            (owner_user_id, operation_type, idempotency_key, request_hash,
             preview_fingerprint, result_summary)
        VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-t03','fp-t03', NULL)
        RETURNING id INTO v_id;

        UPDATE public.bulk_operation SET result_summary = '{"created":7}'::jsonb WHERE id = v_id;

        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence DEFERRED;
    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLSTATE||' '||SQLERRM;
    END;

    PERFORM pg_temp._rec('T','T03 - trigger valida ESTADO FINAL, nao NEW: claim NULL depois completado PASSA',
        v_erro IS NULL, COALESCE(left(v_erro,150),'sem erro'), 'sem erro');

    ---------------------------------------------------------------- T04
    v_erro := NULL;
    BEGIN
        INSERT INTO public.bulk_operation
            (owner_user_id, operation_type, idempotency_key, request_hash,
             preview_fingerprint, result_summary)
        VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-t04','fp-t04','{"created":1}'::jsonb)
        RETURNING id INTO v_id;

        UPDATE public.bulk_operation SET result_summary = NULL WHERE id = v_id;

        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLSTATE||' '||SQLERRM;
    END;

    PERFORM pg_temp._rec('T','T04 - UPDATE zerando result_summary tambem IMPEDE o commit (trigger cobre UPDATE)',
        v_erro IS NOT NULL AND position('result_summary NULL' in v_erro) > 0,
        COALESCE(left(v_erro,150), 'NENHUM erro levantado'),
        'erro contendo: result_summary NULL');

    ---------------------------------------------------------------- T05
    v_erro := NULL;
    BEGIN
        INSERT INTO public.bulk_operation
            (owner_user_id, operation_type, idempotency_key, request_hash,
             preview_fingerprint, result_summary)
        VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-t05','fp-t05', NULL)
        RETURNING id INTO v_id;

        DELETE FROM public.bulk_operation WHERE id = v_id;

        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence IMMEDIATE;
        SET CONSTRAINTS public.trg_bulk_operation_result_summary_presence DEFERRED;
    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLSTATE||' '||SQLERRM;
    END;

    PERFORM pg_temp._rec('T','T05 - linha apagada na mesma transacao NAO faz o trigger falhar',
        v_erro IS NULL, COALESCE(left(v_erro,150),'sem erro'), 'sem erro');

EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._rec('T','T-ABORT - grupo T abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo T completo');
END $blk$;

-- =================================================================
-- GRUPO C — CLAIM (sessao unica)
--
-- CONTEXTO DE EXECUCAO: apenas `request.jwt.claims`, SEM `SET ROLE`.
-- E assim que o chamador real opera — a RPC SECURITY DEFINER de
-- BULK-02/BULK-04 roda como postgres. Trocar de role aqui contradiria
-- S05 (EXECUTE revogado de authenticated) e o grupo abortaria com
-- permission denied.
--
-- Dentro de UMA transacao, o segundo claim com a mesma chave enxerga a
-- propria linha nao-committada: ON CONFLICT DO NOTHING detecta o
-- conflito sem bloquear (mesma transacao) e devolve 0 linhas. Isso
-- exercita REPLAY, CONFLICT e o caso de claim INCOMPLETO sem precisar
-- de duas sessoes — o que as duas sessoes provam adicionalmente e a
-- SERIALIZACAO (grupo K).
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_key UUID; v_key2 UUID; v_r RECORD; v_erro TEXT;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    v_key  := gen_random_uuid();
    v_key2 := gen_random_uuid();

    PERFORM pg_temp._as_claims(v_owner);

    -- C01 — claim novo
    SELECT * INTO v_r FROM public.claim_bulk_operation(
        'REGISTER_PHYSICAL_CARDS', v_key, 'hash-A', 'fp-1');
    PERFORM pg_temp._rec('C','C01 - chave nova devolve CLAIMED com operation_id e result_summary nulo',
        v_r.outcome = 'CLAIMED' AND v_r.operation_id IS NOT NULL AND v_r.result_summary IS NULL,
        format('outcome=%s id=%s result=%s', v_r.outcome, v_r.operation_id, v_r.result_summary),
        'CLAIMED, id nao nulo, result NULL');

    -- C06 — ANTES de completar: mesma chave, MESMO hash, mas a operacao
    -- ainda NAO tem resultado. Nunca pode virar REPLAY.
    v_erro := NULL;
    BEGIN
        SELECT * INTO v_r FROM public.claim_bulk_operation(
            'REGISTER_PHYSICAL_CARDS', v_key, 'hash-A', 'fp-1');
    EXCEPTION WHEN OTHERS THEN
        v_erro := SQLSTATE||' '||SQLERRM;
    END;

    PERFORM pg_temp._rec('C','C06 - mesma chave + mesmo hash com result_summary NULL levanta erro e NUNCA vira REPLAY',
        v_erro IS NOT NULL AND position('operacao incompleta' in v_erro) > 0,
        COALESCE(left(v_erro,150),
                 'NENHUM erro — devolveu outcome='||COALESCE(v_r.outcome,'?')),
        'erro contendo: operacao incompleta');

    -- completa o claim (passo 8 de B1/B2)
    SELECT b.id INTO v_r
      FROM public.bulk_operation b WHERE b.idempotency_key = v_key;
    PERFORM public.complete_bulk_operation(v_r.id, '{"created":5,"allocated":5}'::jsonb);

    -- C02 — claim JA COMPLETADO + mesmo hash => REPLAY com o ORIGINAL
    SELECT * INTO v_r FROM public.claim_bulk_operation(
        'REGISTER_PHYSICAL_CARDS', v_key, 'hash-A', 'fp-DIFERENTE');
    PERFORM pg_temp._rec('C','C02 - claim JA COMPLETADO + mesmo request_hash devolve REPLAY com o result_summary ORIGINAL (fingerprint IGNORADO)',
        v_r.outcome = 'REPLAY' AND v_r.result_summary = '{"created":5,"allocated":5}'::jsonb,
        format('outcome=%s result=%s', v_r.outcome, v_r.result_summary),
        'REPLAY com {"created":5,"allocated":5}');

    -- C03 — mesma chave (completada) + hash diferente => CONFLICT
    SELECT * INTO v_r FROM public.claim_bulk_operation(
        'REGISTER_PHYSICAL_CARDS', v_key, 'hash-B', 'fp-1');
    PERFORM pg_temp._rec('C','C03 - mesma chave + request_hash DIFERENTE devolve CONFLICT (traduzido em BULK_IDEMPOTENCY_CONFLICT pelo chamador)',
        v_r.outcome = 'CONFLICT',
        format('outcome=%s', v_r.outcome), 'CONFLICT');

    -- fixture de C04: um claim novo e completo, com chave propria
    SELECT * INTO v_r FROM public.claim_bulk_operation(
        'REGISTER_PHYSICAL_CARDS', v_key2, 'hash-C', 'fp-2');
    PERFORM public.complete_bulk_operation(v_r.operation_id, '{"created":1}'::jsonb);

    PERFORM pg_temp._as_admin();

    -- C04 — owner vem de auth.uid(), nunca do chamador
    PERFORM pg_temp._rec('C','C04 - owner_user_id da linha e SEMPRE auth.uid() do chamador',
        (SELECT bool_and(b.owner_user_id = v_owner) FROM public.bulk_operation b
          WHERE b.idempotency_key IN (v_key, v_key2)),
        (SELECT string_agg(DISTINCT b.owner_user_id::text, ', ') FROM public.bulk_operation b
          WHERE b.idempotency_key IN (v_key, v_key2)),
        v_owner::text);
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('C','C-ABORT - grupo C abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo C completo');
END $blk$;

-- C05 — PROVA ESTATICA: ON CONFLICT DO NOTHING e ausencia de
-- SELECT-antes-de-INSERT sobre bulk_operation.
DO $blk$
DECLARE
    v_exec TEXT; v_pos_insert INTEGER; v_pos_conflict INTEGER; v_pos_select INTEGER;
BEGIN
    SELECT regexp_replace(regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/',' ','gs'),'--[^\n]*','','g')
      INTO v_exec
      FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.proname='claim_bulk_operation';

    v_pos_insert   := position('INSERT INTO public.bulk_operation' in v_exec);
    v_pos_conflict := position('ON CONFLICT ON CONSTRAINT uq_bulk_operation_owner_type_key DO NOTHING' in v_exec);
    v_pos_select   := position('FROM public.bulk_operation' in v_exec);

    PERFORM pg_temp._rec('C','C05 - STATIC PROOF: usa ON CONFLICT DO NOTHING e NAO ha SELECT sobre bulk_operation ANTES do INSERT',
        v_pos_insert > 0 AND v_pos_conflict > v_pos_insert
        AND (v_pos_select = 0 OR v_pos_select > v_pos_insert),
        format('insert=%s conflict=%s primeiro_select=%s', v_pos_insert, v_pos_conflict, v_pos_select),
        'insert>0, conflict>insert, nenhum select antes do insert');
END $blk$;

-- =================================================================
-- GRUPO R — CONTRATO DE result_summary (5146)
--
-- `result_summary IS NOT NULL` (5143) NAO basta: 'null'::jsonb, arrays
-- e escalares sao todos "nao nulos" para o SQL. 'null'::jsonb e o pior
-- caso — passaria por 5143 e seria devolvido no REPLAY como resultado
-- legitimo de uma operacao concluida.
--
-- R01..R07 exercitam o guard de complete_bulk_operation() (falha cedo,
-- mensagem nomeia o tipo). R08 exercita o CHECK DE TABELA por UPDATE
-- direto, provando que a defesa NAO depende de passar pela funcao.
--
-- R01..R06 reutilizam o MESMO claim: cada tentativa falha dentro do
-- proprio sub-bloco, a subtransacao e desfeita e a linha continua com
-- result_summary NULL — pronta para a proxima tentativa. R07 entao
-- completa esse mesmo claim, provando que as rejeicoes nao o
-- corromperam.
-- =================================================================
DO $blk$
DECLARE
    v_owner UUID; v_key UUID; v_id UUID; v_erro TEXT; v_r RECORD; v_val JSONB;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';
    v_key := gen_random_uuid();

    PERFORM pg_temp._as_claims(v_owner);

    SELECT * INTO v_r FROM public.claim_bulk_operation(
        'REGISTER_PHYSICAL_CARDS', v_key, 'hash-R', 'fp-R');
    v_id := v_r.operation_id;

    ---------------------------------------------------------------- R01
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, NULL::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R01 - SQL NULL e REJEITADO por complete_bulk_operation',
        v_erro IS NOT NULL AND position('nao pode ser NULL' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: nao pode ser NULL');

    ---------------------------------------------------------------- R02
    -- 'null'::jsonb NAO e SQL NULL: escapa do teste de R01 e do
    -- invariante de 5143. E a razao de existir a Query 5146.
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, 'null'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R02 - JSON null (''null''::jsonb, que NAO e SQL NULL) e REJEITADO',
        v_erro IS NOT NULL AND position('JSON object' in v_erro) > 0
                          AND position('recebido: null' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: JSON object / recebido: null');

    ---------------------------------------------------------------- R03
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, '[1,2,3]'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R03 - array JSON e REJEITADO',
        v_erro IS NOT NULL AND position('recebido: array' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: recebido: array');

    ---------------------------------------------------------------- R04
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, '"ok"'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R04 - escalar string e REJEITADO',
        v_erro IS NOT NULL AND position('recebido: string' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: recebido: string');

    ---------------------------------------------------------------- R05
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, '42'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R05 - escalar number e REJEITADO',
        v_erro IS NOT NULL AND position('recebido: number' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: recebido: number');

    ---------------------------------------------------------------- R06
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, 'true'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    PERFORM pg_temp._rec('R','R06 - escalar boolean e REJEITADO',
        v_erro IS NOT NULL AND position('recebido: boolean' in v_erro) > 0,
        COALESCE(left(v_erro,150),'NENHUM erro levantado'),
        'erro contendo: recebido: boolean');

    ---------------------------------------------------------------- R07
    -- O MESMO claim, intacto apos seis rejeicoes, aceita um object.
    v_erro := NULL;
    BEGIN
        PERFORM public.complete_bulk_operation(v_id, '{"created":2,"allocated":2}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_erro := SQLSTATE||' '||SQLERRM;
    END;
    SELECT b.result_summary INTO v_val
      FROM public.bulk_operation b WHERE b.id = v_id;

    PERFORM pg_temp._rec('R','R07 - JSON object e ACEITO e o MESMO claim segue integro apos as 6 rejeicoes',
        v_erro IS NULL AND v_val = '{"created":2,"allocated":2}'::jsonb,
        format('erro=[%s] result_summary=[%s]',
               COALESCE(left(v_erro,120),'nenhum'), COALESCE(v_val::text,'(nulo)')),
        'sem erro; result_summary = {"created":2,"allocated":2}');

    PERFORM pg_temp._as_admin();
EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp._as_admin();
    PERFORM pg_temp._rec('R','R-ABORT - grupo R abortou', FALSE,
        SQLSTATE||' '||left(SQLERRM,180), 'grupo R completo');
END $blk$;

-- R08 — CHECK DE TABELA, provado SEM passar pela funcao.
-- UPDATE direto e privilegiado: e o caminho que uma migration futura ou
-- uma sessao administrativa usaria. Se so a funcao validasse, este
-- UPDATE gravaria 'null'::jsonb em silencio.
DO $blk$
DECLARE v_owner UUID; v_id UUID;
BEGIN
    SELECT v INTO v_owner FROM _fx WHERE k='owner';

    INSERT INTO public.bulk_operation
        (owner_user_id, operation_type, idempotency_key, request_hash,
         preview_fingerprint, result_summary)
    VALUES (v_owner,'REGISTER_PHYSICAL_CARDS',gen_random_uuid(),'h-r08','fp-r08', NULL)
    RETURNING id INTO v_id;

    PERFORM pg_temp._expect_error('R','R08 - CHECK DE TABELA barra UPDATE direto com ''null''::jsonb, sem passar por complete_bulk_operation',
        format('UPDATE public.bulk_operation SET result_summary = ''null''::jsonb WHERE id = %L::uuid', v_id),
        'chk_bulk_operation_result_summary_object');
END $blk$;

-- =================================================================
-- GRUPO K — CONCORRENCIA REAL (DUAS SESSOES)
--
-- NAO automatizavel neste canal: exige duas sessoes persistentes e
-- simultaneas, com a transacao de A ABERTA enquanto B tenta o claim.
-- Medido em 2026-09-07: execute_sql nao preserva sessao/transacao entre
-- chamadas. Mesma classe de C04/R18 do 5818.
--
-- Gravados como NOT PROVEN (passed IS NULL). NUNCA converter em PASS.
-- Prova externa: CONCURRENCY-PROOF-BULK-CLAIM.sql, nesta pasta.
-- =================================================================
DO $blk$
BEGIN
    PERFORM pg_temp._rec('K','K01 - duas sessoes reais com a MESMA chave: a segunda BLOQUEIA no indice unico',
        NULL, 'canal nao sustenta duas sessoes simultaneas', 'B bloqueada por A via pg_blocking_pids');

    PERFORM pg_temp._rec('K','K02 - apos COMMIT de A, a sessao B recebe REPLAY (mesmo hash) ou CONFLICT (hash diferente)',
        NULL, 'depende de K01', 'B desbloqueia e nao insere linha nova');

    PERFORM pg_temp._rec('K','K03 - apos ROLLBACK de A, a sessao B consegue o claim (CLAIMED)',
        NULL, 'depende de K01', 'B insere e recebe CLAIMED');
END $blk$;

-- =================================================================
-- ZERO RESIDUO
-- =================================================================
DO $blk$
DECLARE v_base INTEGER; v_n INTEGER;
BEGIN
    SELECT n            INTO v_base FROM _bl;
    SELECT count(*)     INTO v_n    FROM public.bulk_operation;

    -- X01 — BASELINE. Medido na secao INFRAESTRUTURA, antes de
    -- qualquer escrita. Precisa ser 0: o harness escreve na tabela
    -- real, e o postcheck pos-ROLLBACK (CALL 3) so significa "zero
    -- residuo" se nao havia nada antes.
    PERFORM pg_temp._rec('X','X01 - BASELINE de bulk_operation, capturado ANTES de qualquer escrita, e ZERO',
        v_base = 0,
        format('baseline=%s', v_base),
        'baseline = 0');

    -- X02 — o harness ESCREVEU de fato.
    --
    -- Nao e cosmetico: se nenhuma linha tivesse sido criada, os grupos
    -- S06/T/C/R teriam falhado silenciosamente por fixture ausente em
    -- vez de por defeito real, e este caso denuncia isso.
    --
    -- Este caso NAO afirma que o ROLLBACK ocorreu — quando ele roda, o
    -- ROLLBACK ainda nao aconteceu. A prova de zero residuo REAL e o
    -- postcheck da CALL 3, fora deste arquivo.
    --
    -- NOTA (v1.3): a v1.2 tentava provar isso com
    -- `xmin = pg_current_xact_id()::xid`. Estava ERRADO —
    -- pg_current_xact_id() devolve o xid da transacao de TOPO, e as
    -- linhas deste harness sao inseridas dentro de blocos DO com
    -- EXCEPTION, que sao SUBTRANSACOES e carregam SUBXID. A comparacao
    -- reprovaria linhas legitimas.
    PERFORM pg_temp._rec('X','X02 - o harness ESCREVEU de fato (linhas > baseline); zero residuo REAL e provado no postcheck pos-ROLLBACK, NAO aqui',
        v_n > v_base,
        format('baseline=%s linhas_no_fim_do_harness=%s criadas_pelo_harness=%s',
               v_base, v_n, v_n - v_base),
        'linhas_no_fim_do_harness > baseline');
END $blk$;

-- =================================================================
-- RELATORIO FINAL — PROTOCOLO EM TRES CHAMADAS.
--   CALL 1: tudo desde BEGIN; ate o SELECT abaixo, INCLUSIVE.
--   CALL 2: ROLLBACK;
--   CALL 3: SELECT count(*) AS deve_ser_zero FROM public.bulk_operation;
--           Esperado 0. E a UNICA prova de zero residuo — nenhum caso
--           deste arquivo afirma que o ROLLBACK ocorreu.
--
-- passed=TRUE -> PASS | FALSE -> FAIL | NULL -> NOT PROVEN
--
-- GATE OFICIAL (v1.3): TOTAL 39 / PASS 36 / FAIL 0 / NOT PROVEN 3,
-- sendo os 3 NOT PROVEN EXATAMENTE K01, K02 e K03.
--
-- Aritmetica do gate (43 rotulos estaticos no arquivo, 4 deles
-- fail-only e inalcancaveis no caminho saudavel):
--     43 - 4 = 39 registros de runtime
--     39 - 3 NOT PROVEN (K) = 36 PASS
-- Qualquer `*-ABORT` presente = STOP.
-- =================================================================
SELECT
    COALESCE(grp, 'TOTAL')                                   AS grp,
    count(*)                                                 AS total,
    count(*) FILTER (WHERE passed IS TRUE)                   AS passed,
    count(*) FILTER (WHERE passed IS FALSE)                  AS failed,
    count(*) FILTER (WHERE passed IS NULL)                   AS not_proven,
    string_agg(case_label || ' >> ' || COALESCE(observed,''), ' || ')
        FILTER (WHERE passed IS FALSE)                       AS failing_cases,
    string_agg(case_label, ' || ')
        FILTER (WHERE passed IS NULL)                        AS not_proven_cases
FROM _v
GROUP BY ROLLUP (grp)
ORDER BY (grp IS NULL), grp;

ROLLBACK;
