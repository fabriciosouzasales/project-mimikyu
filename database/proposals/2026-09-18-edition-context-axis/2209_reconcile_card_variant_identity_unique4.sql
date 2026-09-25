-- ============================================================================
-- Query 2209 — Identidade de card_variant em QUATRO componentes
-- Status: EXECUTADA / LIVE VALIDATED · Versão 2.0 (a executada)
--
-- CLOSEOUT (BATCH10-2209-LIVE-VALIDATION-CLOSEOUT-01, 2026-09-25)
--   Executada 1x em 2026-09-25 (~18:03Z) via Supabase MCP `execute_sql`,
--   imediatamente apos JIT PRECHECK read-only 15/15 gates + gate_pass = true.
--   Identidade EXATAMENTE executada (antes deste bloco de comentario):
--     git blob 390848500603325b545c944184ac51fb45aeee16
--     md5      4a10e6528d82562c22103bfccf8cad45 · 7.075 B · 0 CR · 117 LF
--   Depois da execucao este arquivo recebeu SOMENTE comentarios; nenhum
--   token executavel mudou (inclusive o literal do COMMENT ON CONSTRAINT).
--   POSTCHECK LIVE: uq_card_variant_identity presente como indice
--   (OID 221012) e como constraint contype='u', convalidated, nao
--   deferrable, UNIQUE NULLS NOT DISTINCT (card_id, variant_type_id,
--   printing_profile_id, edition_context_profile_id); indice unique/valid/
--   ready/live, indnullsnotdistinct, nao parcial, sem expressao,
--   1.515.520 B. As duas antigas (uq_card_variant_card_type_no_printing
--   OID 151290 e uq_card_variant_card_type_printing OID 151291) seguem
--   presentes e saudaveis. card_variant 24.893 · EC nao-nulo 0 · duplicidade
--   UNIQUE(4) 0/0 · 11 indices, 0 invalidos · owner/RLS/ACL preservados ·
--   zero lock/transacao residual. Ledger 2209 = 0 (rastreabilidade: o MCP
--   nao escreve no ledger; mesma classe de 2214/2224/2217/2218/2223).
--
--   ESTADO ENTRE 2209 E 2215 (invariante): TRES garantias UNIQUE ativas
--   simultaneamente — a nova UNIQUE(4) e as duas antigas. As antigas
--   continuam MAIS restritivas: duas Variants que diferem so em Edition
--   Context AINDA sao rejeitadas. Nenhum instante sem protecao de identidade.
--   A nova identidade ESTA INSTALADA, mas so passa a ser a UNICA autoridade
--   fisica apos a Query 2215 (nao executada, nao autorizada). FREEZE
--   permanece obrigatorio ate la.
--
-- v2.0 (GATE-A-FINAL-CORRECTION-01):
--   C1 os DROPs dos indices antigos estavam COMENTADOS — a identidade nova
--      nao tinha efeito. Migraram para a Query 2215, executavel e auditavel.
--   C2 CONCURRENTLY REMOVIDO. Decisao: indice normal sob FREEZE.
--
-- ESTADO ATUAL (medido no LIVE, 2026-09-18)
--   uq_card_variant_card_type_no_printing (card_id, variant_type_id)
--       WHERE printing_profile_id IS NULL
--   uq_card_variant_card_type_printing    (card_id, variant_type_id, printing_profile_id)
--       WHERE printing_profile_id IS NOT NULL
--   Somados: 1.536 kB sobre 24.893 linhas (tabela total 9.064 kB).
--
-- ESTADO PROPOSTO — UMA constraint de quatro componentes
--   UNIQUE NULLS NOT DISTINCT
--     (card_id, variant_type_id, printing_profile_id, edition_context_profile_id)
--
-- POR QUE NULLS NOT DISTINCT E NÃO QUATRO ÍNDICES PARCIAIS
--   Com dois eixos nuláveis, a cobertura por predicado exige 4 índices
--   (NULL/NULL, NULL/NOT NULL, NOT NULL/NULL, NOT NULL/NOT NULL).
--   O modo de falha dos dois desenhos é diferente em natureza:
--     · 4 índices parciais: um predicado escrito errado abre um buraco
--       SILENCIOSO — nada falha, duplicatas entram e só aparecem depois.
--     · UNIQUE(4) NULLS NOT DISTINCT: não há predicado para errar.
--   Além disso, um índice único serve os prefixos (card_id),
--   (card_id, variant_type_id) e (card_id, variant_type_id, printing_profile_id),
--   enquanto os parciais não servem nenhum sem o predicado.
--
--   PostgreSQL LIVE: 17.6 on aarch64. NULLS NOT DISTINCT disponível desde 15.
--
-- ORDEM DE COLUNAS — deliberada
--   card_id primeiro: toda consulta de UI parte da Card. Isso torna a UNIQUE
--   utilizável como índice de leitura e permite avaliar a remoção futura de
--   ix_card_variant_card_id (NÃO removido aqui — ver harness).
--
-- POR QUE SEM `CONCURRENTLY` — decisao da GATE-A-FINAL-CORRECTION-01
--   A. CREATE UNIQUE INDEX normal, sob o FREEZE da etapa 0 do rollout.
--      CORRECAO (closeout 2026-09-25) — o texto original dizia que o passo
--      "NAO bloqueia leitura"; isso so vale para o CREATE. Locks reais:
--        CREATE UNIQUE INDEX                      -> ShareLock: bloqueia
--                                                    escrita, permite leitura.
--        ALTER TABLE ... ADD CONSTRAINT UNIQUE    -> AccessExclusiveLock ate
--          USING INDEX                               o COMMIT: bloqueia
--                                                    TAMBEM a leitura.
--      Por isso o precheck de concorrencia (zero sessao/lock/transacao)
--      e obrigatorio antes da execucao. Volume real:
--      24.893 linhas / 9.064 kB — construcao na casa de centenas de ms. Sob
--      FREEZE nao ha escrita concorrente a bloquear. Roda DENTRO de transacao
--      => compativel com apply_migration => revertivel com o resto do passo.
--   B. CONCURRENTLY, fora de transacao. Nao roda em apply_migration (25001).
--      ZERO precedente em database/schema/ e database/migrations/. Deixa
--      indice INVALID se falhar, exigindo limpeza manual. Nao transacional.
--   ESCOLHIDA: **A**. O unico beneficio de B — nao bloquear escrita — e
--   irrelevante sob FREEZE, e B introduz um modo de execucao inedito no
--   projeto sem ganho. B so se justificaria com tabela grande ou sistema que
--   nao pode parar; nenhuma das duas condicoes vale aqui.
--
-- SEQUENCIA OBRIGATORIA — sem janela desprotegida
--   1. (esta Query) CREATE UNIQUE INDEX + ADD CONSTRAINT USING INDEX.
--      Ao fim deste passo convivem TRES garantias: as duas antigas e a nova.
--      Conviver e SEGURO — as antigas sao MAIS restritivas que a nova, logo
--      nada indevido entra. Mas tambem significa que a nova ainda NAO tem
--      efeito pratico: duas Variants que diferem so em Edition Context
--      continuam sendo rejeitadas pelas antigas.
--   2. Query 2215 — DROP das duas antigas, cada uma precedida de prova de que
--      uq_card_variant_identity existe, e UNIQUE e indisvalid = true.
--   3. Query 2215 PASSO 3 — prova de que SOMENTE a nova permanece.
--   Em nenhum instante a tabela fica sem constraint de identidade.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ATOMICIDADE — a propriedade que este arquivo mais precisa
-- ----------------------------------------------------------------------------
-- O comentario abaixo sempre afirmou "uma unica chamada, transacional".
-- Ate a TRANSACTION-BOUNDARY-CORRECTION-02 isso era uma AFIRMACAO, nao uma
-- GARANTIA: nao havia BEGIN/COMMIT, e a atomicidade dependia do executor.
--
-- Por que aqui importa mais do que em qualquer outro arquivo do pacote:
--   CREATE UNIQUE INDEX uq_card_variant_identity   <- cria o indice
--   ALTER TABLE ... ADD CONSTRAINT ... USING INDEX <- PROMOVE o indice a
--                                                     constraint, CONSUMINDO-O
-- Falha ENTRE os dois deixaria `uq_card_variant_identity` existindo como
-- INDICE ORFAO — sem constraint, invisivel para quem procura por
-- pg_constraint, e bloqueando a reexecucao do arquivo por colisao de nome.
-- A Query 2215 exige `uq_card_variant_identity` como CONSTRAINT valida antes
-- de dropar as duas antigas; um orfao nao satisfaz esse gate, e o pacote
-- travaria num estado que nenhum artefato sabe desfazer.
--
-- Com BEGIN/COMMIT: ou existem indice E constraint, ou nao existe nenhum dos
-- dois. Nao ha terceiro estado. As duas UNIQUE antigas permanecem intactas em
-- qualquer cenario de falha — a tabela nunca fica sem identidade.
BEGIN;

-- Uma unica chamada, transacional, sob FREEZE.
CREATE UNIQUE INDEX uq_card_variant_identity
    ON public.card_variant (card_id, variant_type_id, printing_profile_id, edition_context_profile_id)
    NULLS NOT DISTINCT;

ALTER TABLE public.card_variant
    ADD CONSTRAINT uq_card_variant_identity
    UNIQUE USING INDEX uq_card_variant_identity;

-- NOTA DE CLOSEOUT (2026-09-25): o literal abaixo diz "Substitui ..." as duas
-- antigas. Isso so e verdade APOS a Query 2215. Depois da 2209 as tres
-- garantias coexistem e as antigas continuam mais restritivas. O literal NAO
-- foi alterado: e parte do statement executado (e do COMMENT gravado no LIVE).
COMMENT ON CONSTRAINT uq_card_variant_identity ON public.card_variant IS
'Identidade canonica de Card Variant em quatro componentes: acabamento (variant_type), tiragem (printing_profile), contexto de edicao (edition_context_profile). NULLS NOT DISTINCT porque NULL significa "sem esse eixo" — um valor, nao desconhecido. Substitui uq_card_variant_card_type_no_printing e uq_card_variant_card_type_printing.';

COMMIT;

-- ============================================================================
-- OS DROPS NAO ESTAO AQUI — E DELIBERADO, E ERA UM BLOCKER NA v1.0.
--   uq_card_variant_card_type_no_printing e uq_card_variant_card_type_printing
--   sao removidos pela **Query 2215**, que antes de cada DROP prova que
--   uq_card_variant_identity existe, e UNIQUE e esta valida.
--   **2209 sem 2215 NAO entrega o eixo**: as antigas continuariam rejeitando
--   duas Variants que diferem somente em edition_context_profile_id.
-- ============================================================================

-- ============================================================================
-- PRESERVADO INTACTO (não tocar)
--   uq_card_variant_card_order            (card_id, variant_order)
--   uq_card_variant_one_default_per_card  (card_id) WHERE is_default
--   uq_card_variant_id_card               (id, card_id)  -- FK composta de 5104
-- ============================================================================
