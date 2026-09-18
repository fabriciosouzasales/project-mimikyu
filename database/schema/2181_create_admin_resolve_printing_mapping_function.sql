/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2181 - Create admin_resolve_catalog_variant_import_printing_mapping()
Versão......: 2.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / RECONCILIADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Reconciliada: 2026-09-18 — BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01
              (v2.0: corpo terminal = migration 2197, ledger 20260914025324)
Origem......: v1.x — database/proposals/2026-09-12-card-variants-printing-routing/
              2181_create_admin_resolve_printing_mapping_function.sql
              v2.0 — database/migrations/2197_reconcile_variant_type_mapping_
              printing_lookup_for_scope.sql (histórico do ciclo de 2026-09-14)
Mandato.....: v1.x — CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§7, §20, §21)
               + STAGING-REVISION-01 (R4)
               + STAGING-CORRECTION-04 (§1, §2, §3, §4)

-------------------------------------------------------------------------------
ALTERAÇÕES DA VERSÃO 1.2 — STAGING-CORRECTION-04
-------------------------------------------------------------------------------
Três correções funcionais, apuradas em PHASE-B-FINAL-AUDIT-01. Mudança de
COMPORTAMENTO, por isso bump de versão explícito.

B-04 — ORIGIN-ROW BINDING (§1).
  A v1.1 recebia p_row_id e usava a linha APENAS para resolver Game,
  Fonte e job, e para gravar origin_row_id no log. O token informado
  nunca era confrontado com a raw_data dessa linha. Consequência: uma
  linha qualquer servia para ratificar um token qualquer — inclusive um
  que não existisse em lugar nenhum do corpus — e o campo origin_row_id
  do log era uma afirmação NÃO VERIFICADA.
  A v1.2 exige que o token normalizado exista EXATAMENTE na raw_data da
  linha de origem, por igualdade canônica. Sem LIKE, substring, prefixo,
  split ou fuzzy. A linha de origem volta a ser o que o nome diz:
  evidência editorial real da combinação.

B-05 — NO_CHANGE POR COMPOSIÇÃO EFETIVA (§2).
  A v1.1 lia m.traits_signature CRUA. Se o mapping ativo tivesse nascido
  na MESMA transação, o selo diferido ainda não teria disparado e a
  assinatura seria NULL; `NULL = v_signature` devolve NULL, o guard não
  disparava, e uma substituição por composição IDÊNTICA passava
  silenciosamente. Mesma classe do B-01, em outro ponto: o código voltava
  a tratar traits_signature como "a composição atual".
  A v1.2 usa a COMPOSIÇÃO EFETIVA — assinatura selada OU a N:N
  transacional ordenada —, o mesmo contrato semântico da Query 2176 v1.1.
  Header ACTIVE com composição efetiva vazia é estado estruturalmente
  inválido e falha fechado, nunca é tratado como "composição diferente".

B-06 — RECONCILIAÇÃO COMPLETA DAS ROWS ATINGIDAS (§3).
  A v1.1 só escrevia nas linhas que RESOLVIAM. Uma linha que estava VALID
  pelo mapping anterior e que, após a substituição, deixasse de resolver
  permanecia VALID com o printing_profile_id ANTIGO — identidade canônica
  obsoleta que o confirm (Query 2179) aceitaria sem reclamar, gerando uma
  card_variant com perfil que a própria decisão editorial acabara de
  invalidar.
  A v1.2 reconcilia TODAS as linhas atingidas em exatamente um de três
  estados terminais (A/B/C, descritos abaixo). Nenhuma linha atingida
  conserva chave obsoleta.

§4 — CONTADORES. rows_updated passa a significar estritamente "terminou
  VALID"; rows_still_pending, "terminou NEEDS_REVIEW". A soma é igual ao
  universo atingido, e isso é verificado em tempo de execução por um
  invariante interno fail-closed. Nenhuma linha rebaixada fica escondida
  num contador residual.

-------------------------------------------------------------------------------
ESTADOS TERMINAIS DE UMA LINHA ATINGIDA (v1.2, §3)
-------------------------------------------------------------------------------
Toda linha do universo atingido termina em EXATAMENTE um destes:

  A. Printing RESOLVIDO e Variant Type residual RESOLVIDO
     validation_status = VALID
     normalized_data   = variant_type_id correto
                       + printing_profile_id explícito (JSON null ou UUID)

  B. Printing RESOLVIDO, Variant Type residual NÃO resolvido
     validation_status = NEEDS_REVIEW
     normalized_data   = variant_type_id REMOVIDO
                       + printing_profile_id explícito (JSON null ou UUID)

  C. Printing NÃO RESOLVIDO
     (INACTIVE_MAPPING, INVALID_PRINTING_MAPPING, INACTIVE_TRAIT,
      NO_PROFILE, INACTIVE_PROFILE e qualquer estado futuro de Printing)
     validation_status = NEEDS_REVIEW
     normalized_data   = variant_type_id REMOVIDO
                       + printing_profile_id REMOVIDO

Razão do C: sem Printing resolvido o RESIDUAL não é identidade canônica
confiável — manter um variant_type_id derivado dele seria preservar uma
conclusão tirada de premissa inválida.

A classificação testa PERTENCIMENTO ao par aceito
('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE'), nunca enumeração
fechada dos estados de erro: estados novos caem automaticamente em C.

match_status NÃO ganha semântica nova aqui. Ele continua sendo recalculado
pelo confirm (Query 2179) contra o catálogo real, e esta RPC não o toca.

-------------------------------------------------------------------------------
EXCLUSÃO DELIBERADA E DOCUMENTADA DO UNIVERSO ATINGIDO (§4)
-------------------------------------------------------------------------------
O universo atingido é restrito a linhas com
validation_status IN ('VALID','NEEDS_REVIEW').

Linhas em 'PENDING' (ainda não validadas pelo pipeline) e em 'INVALID'
(rejeitadas por outro motivo) NÃO são reavaliadas por esta RPC: promovê-las
a VALID ou rebaixá-las a NEEDS_REVIEW seria atribuir a uma decisão de
Impressão um efeito sobre um eixo que ela não julgou. Elas não entram em
nenhum dos dois contadores. Hoje o LIVE tem zero linhas nesses dois
estados; a restrição é de contrato, não de conveniência.

-------------------------------------------------------------------------------
Alterações da versão 1.1 (STAGING-REVISION-01, BLOCKER R4):
- catalog_admin_action_log passa a usar contrato PRÓPRIO:
      action      = CARD_PRINTING_EXTERNAL_MAPPING_CREATED
      entity_type = CARD_PRINTING_EXTERNAL_MAPPING
  A v1.0 reusava o par de CARD_VARIANT_TYPE_EXTERNAL_MAPPING com
  metadata.domain = 'PRINTING'. NÃO APROVADO: o par reusado pertence a
  outra entidade, e guardar a identidade da entidade dentro do JSON
  quebra toda consulta que filtre por entity_type. Ver Query 2185.
- metadata.domain REMOVIDO — virou redundante e mentiroso assim que o
  entity_type passou a ser correto.
- metadata.rows_updated renomeado para rows_revalidated: a operação não
  "atualiza linhas", ela REVALIDA linhas de staging contra o mapping
  novo. O nome antigo colidia semanticamente com o rows_updated de
  outras ações do log.
- GUARD DE DEPENDÊNCIA no topo: esta Query recusa-se a criar a função se
  a CHECK do log ainda não aceitar a action nova. Torna a ordem
  2185 -> 2181 auto-verificável, independentemente da ordem numérica.
- A "decisão em aberto" do rodapé foi FECHADA.

Descrição resumida:
Operacao editorial atomica do eixo Printing: cria (ou SUBSTITUI) o
mapping de um token externo e propaga cross-job.

Descrição:
E a irma da Query 2180 no outro eixo. Enquanto a 2180 resolve
ACABAMENTO, esta resolve IMPRESSAO.

    admin_resolve_catalog_variant_import_printing_mapping(
        p_row_id    UUID,     -- linha que originou a decisao editorial
        p_raw_field TEXT,     -- 'subtype' ou 'stamp'
        p_token     TEXT,     -- token externo, forma bruta
        p_trait_ids UUID[]    -- conjunto COMPLETO de traits
    )

-------------------------------------------------------------------------------
ATOMICIDADE — O CONJUNTO COMPLETO OU NADA
-------------------------------------------------------------------------------
p_trait_ids recebe o conjunto INTEIRO. Nao existe "adicionar um trait a
um mapping existente": mapping selado e imutavel (Query 2174).

Por que isso importa, concretamente:

    shadowless-red-cheek -> SHADOWLESS + RED_CHEEK

Se SHADOWLESS entrasse primeiro e a propagacao rodasse antes de
RED_CHEEK, as rows resolveriam para o Profile SHADOWLESS — semanticamente
ERRADO. Aqui isso e impossivel: cabecalho, composicao e propagacao
acontecem na MESMA transacao, e nada e visivel antes do COMMIT.

-------------------------------------------------------------------------------
O SELO E DEFERIDO — E POR ISSO A PROPAGACAO NAO PODE LE-LO
-------------------------------------------------------------------------------
trg_card_printing_external_mapping_seal e CONSTRAINT TRIGGER DEFERRABLE
INITIALLY DEFERRED: traits_signature so e gravada no COMMIT.

Ou seja, DENTRO desta transacao o cabecalho novo ainda tem
traits_signature NULL. A propagacao NAO pode depender dele.

Onde isso e resolvido: na Query 2176 v1.1, e SOMENTE la.

    A afirmacao acima era FALSA ate a STAGING-CORRECTION-03. A 2176 v1.0
    lia `m.traits_signature` e, por isso, a propagacao desta RPC
    classificava TODAS as rows atingidas como
    NEEDS_REVIEW_INACTIVE_MAPPING e devolvia rows_revalidated = 0, sem
    erro nenhum. Era o BLOCKER B-01.

    A 2176 v1.1 passou a usar a ASSINATURA EFETIVA — selada OU a
    composicao atual da N:N —, e a decidir EXISTENCIA por m.id. Agora a
    afirmacao e literalmente verdadeira.

FONTE UNICA. Esta RPC NAO reimplementa resolucao de composicao: ela
insere a N:N e chama internal.compute_variant_residual_signature(). O
array v_signature calculado aqui serve apenas para validar o payload
(distincao, ordenacao, duplicata) e para gravar a composicao — nunca
como caminho paralelo de resolucao.

Regressao coberta por: Query 2824, Secao S14 (propagacao real, exige
rows_revalidated = 1) e Secao S27 (contrato temporal testado direto).

-------------------------------------------------------------------------------
SUBSTITUICAO EDITORIAL
-------------------------------------------------------------------------------
    1. SELECT ... FOR UPDATE do ativo atual do token, se existir;
    2. UPDATE antigo SET is_active = FALSE;
    3. INSERT novo cabecalho ACTIVE com supersedes_mapping_id;
    4. INSERT composicao completa;
    5. propagar;
    6. COMMIT -> selo + visibilidade atomica.

O passo 2 vem ANTES do 3 de proposito: inverter faria o INSERT colidir
com o proprio ativo que se pretende aposentar
(uq_card_printing_external_mapping_active_token).

Concorrencia: duas transacoes substituindo o mesmo token disputam a
MESMA linha do indice parcial. Uma comita, a outra recebe
unique_violation. Merge acidental e impossivel — inclusive com conjuntos
disjuntos.

-------------------------------------------------------------------------------
FRONTEIRA — REGISTRADA E NAO ATRAVESSADA
-------------------------------------------------------------------------------
Esta funcao reavalia SOMENTE rows STAGED, incluindo as que ja estavam
VALID pelo mapping anterior.

NENHUMA card_variant ja persistida e criada, alterada ou removida.
Se uma correcao de mapping implicar que uma card_variant confirmada
ficou com o perfil errado, isso e OUTRO procedimento editorial
explicito — reconciliacao de catalogo —, nunca efeito colateral daqui.

--------------------------------------------------------------
LOOKUP SOURCE_SET-AWARE (v2.0, incorporado da 2197)
--------------------------------------------------------------
Desde a v2.0 esta RPC não resolve mais o Variant Type de uma linha
por conta própria: ela consome internal.lookup_variant_type_for_row()
(Query 2192 v2.0), o PONTO ÚNICO do banco onde a precedência de
escopo existe.

  PRECEDÊNCIA, DE UM NÍVEL, SEM CASCATA:
      scoped (external_set_id da linha)  >  global (NULL)  >  NEEDS_REVIEW

É determinística por construção — os dois índices parciais da Query
2140 v2.0 garantem no máximo dois candidatos, e a ordenação é total
sobre eles. NÃO há desempate por timestamp, display_order, is_active
ou id.

Consequência prática para o eixo Impressão: uma linha cujo
acabamento foi reinterpretado por um mapping SOURCE_SET passa a ser
avaliada com esse Variant Type, e não com o global — o que mantém os
dois eixos (acabamento e impressão) coerentes entre si. Sem isso, a
ratificação de Impressão poderia propagar sobre um acabamento que o
escopo já havia substituído.

O restante do contrato editorial de Impressão (raw_field, traits,
auditoria própria, origin-row binding, composição efetiva) permanece
INALTERADO — a mudança da v2.0 é apenas de onde vem o Variant Type.

Regras de Negócio:
- Admin-only, primeira instrucao.
- raw_field restrito a 'subtype'/'stamp'.
- Variant Type da linha resolvido por internal.lookup_variant_type_
  for_row(), com precedencia scoped > global > NEEDS_REVIEW.
- p_trait_ids nao pode ser vazio nem conter NULL nem duplicatas.
- Todos os traits precisam existir, ser do mesmo Game e estar ATIVOS.
- Token normalizado por normalize_external_catalog_value().
- VALID so quando Variant Type E Printing estao ambos resolvidos.
- Nenhuma criacao automatica de Print Profile.

Pré-requisitos:
- Query 2172/2173/2174 - mapping, composicao e guards.
- Query 2176 - compute_variant_residual_signature().
- Query 2185 - Widen Catalog Admin Action Log for Printing Mapping
  (OBRIGATÓRIA E ANTERIOR — verificada pelo guard abaixo).

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial da RPC editorial de Impressão (2026-09-12).**
        Reusava o par de action/entity_type de Variant Type. Substituída
        antes da execução pelo BLOCKER R4. |
| 1.1 | **Contrato próprio de auditoria + guard de dependência (2026-09-12).**
        action/entity_type próprios (Query 2185), metadata.domain removido,
        rows_updated renomeado para rows_revalidated. Substituída antes da
        execução pela STAGING-CORRECTION-04. |
| 1.2 | **Origin-row binding, composição efetiva e reconciliação terminal
        A/B/C (2026-09-12).** Fecha B-04, B-05 e B-06. Esta é a versão
        executada e confirmada no banco físico na PHASE B da frente
        CARD-VARIANTS — PRINTING-ROUTING. Promovida de database/proposals/
        para database/schema/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
| 2.0 | **Lookup de Impressão ciente de escopo (2026-09-18, BULK-STP-01-
        CANONICAL-RECONCILIATION-IMPLEMENTATION-01).** Fold-in do estado
        terminal introduzido pela migration **`2196`/`2197`** (ledger
        `20260914025324`): a resolução do eixo Impressão passa a respeitar o
        escopo `GLOBAL` vs `SOURCE_SET` do mapping de acabamento, coerente com
        `external_set_id` (Query 2140 v2.0). A migration `2197` permanece em
        `database/migrations/` como histórico. |
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(
    p_row_id     UUID,
    p_raw_field  TEXT,
    p_token      TEXT,
    p_trait_ids  UUID[]
)
RETURNS TABLE(
    mapping_id            UUID,
    superseded_mapping_id UUID,
    rows_updated          INTEGER,
    rows_still_pending    INTEGER,
    jobs_affected         INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $printing$
DECLARE
    c_max_traits CONSTANT INTEGER := 20;

    v_row public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_token TEXT;
    v_signature UUID[];
    v_active_sig UUID[];
    v_old_mapping_id UUID;
    v_new_mapping_id UUID;
    v_rows_updated INTEGER;
    v_rows_pending INTEGER;
    v_jobs_affected INTEGER;
    v_touched_total INTEGER;
    v_reconciled_total INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de impressão.';
    END IF;

    IF p_row_id IS NULL OR p_raw_field IS NULL OR p_token IS NULL OR p_trait_ids IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_MISSING_ARGS: p_row_id, p_raw_field, p_token e p_trait_ids são obrigatórios.';
    END IF;

    IF p_raw_field NOT IN ('subtype', 'stamp') THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_FIELD: p_raw_field deve ser subtype ou stamp (recebido: %). type e foil são acabamento e nunca são roteados para Impressão.', p_raw_field;
    END IF;

    IF array_ndims(p_trait_ids) <> 1 THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_ARRAY_SHAPE: p_trait_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_trait_ids);
    END IF;

    IF cardinality(p_trait_ids) = 0 THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_EMPTY_TRAITS: p_trait_ids veio vazio. Mapeamento parcial não é permitido — informe o conjunto completo de Características de Impressão.';
    END IF;

    IF cardinality(p_trait_ids) > c_max_traits THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_TOO_MANY_TRAITS: % traits, acima do teto de % por token.', cardinality(p_trait_ids), c_max_traits;
    END IF;

    IF EXISTS (SELECT 1 FROM unnest(p_trait_ids) t WHERE t IS NULL) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_NULL_TRAIT: p_trait_ids contém NULL.';
    END IF;

    v_signature := ARRAY(SELECT DISTINCT t FROM unnest(p_trait_ids) t ORDER BY t);

    IF cardinality(v_signature) <> cardinality(p_trait_ids) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_DUPLICATE_TRAIT: p_trait_ids contém a mesma Característica de Impressão mais de uma vez.';
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_ROW_NOT_FOUND: nenhuma linha encontrada para o id informado (%).', p_row_id;
    END IF;

    SELECT j.source INTO v_job_source FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;
    IF v_job_source IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_JOB_NOT_FOUND: não foi possível resolver o job desta linha.';
    END IF;

    SELECT e.game_id INTO v_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = v_row.card_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_GAME_NOT_FOUND: não foi possível resolver o Game desta linha.';
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = v_job_source;
    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_SOURCE_NOT_FOUND: nenhuma Fonte encontrada para o código % do job desta linha.', v_job_source;
    END IF;

    IF (SELECT count(*) FROM public.card_printing_trait t
         WHERE t.id = ANY (v_signature) AND t.game_id = v_game_id AND t.is_active)
       <> cardinality(v_signature) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_TRAITS: uma ou mais Características de Impressão não existem, pertencem a outro Game ou estão inativas.';
    END IF;

    v_token := public.normalize_external_catalog_value(p_token);
    IF btrim(v_token) = '' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_EMPTY_TOKEN: o token normalizado ficou vazio (recebido: %).', p_token;
    END IF;

    IF p_raw_field = 'subtype' THEN
        IF public.normalize_external_catalog_value(v_row.raw_data ->> 'subtype')
           IS DISTINCT FROM v_token THEN
            RAISE EXCEPTION 'PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND: o token % (normalizado: %) não é o subtype da linha de origem %. A linha informada precisa conter exatamente esta combinação — ela é a evidência editorial da decisão.',
                p_token, v_token, p_row_id;
        END IF;
    ELSE
        IF jsonb_typeof(v_row.raw_data -> 'stamp') IS DISTINCT FROM 'array'
           OR NOT EXISTS (
               SELECT 1
                 FROM jsonb_array_elements_text(v_row.raw_data -> 'stamp') e
                WHERE public.normalize_external_catalog_value(e) = v_token
           ) THEN
            RAISE EXCEPTION 'PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND: o token % (normalizado: %) não está no array stamp da linha de origem %. A linha informada precisa conter exatamente este token — ela é a evidência editorial da decisão.',
                p_token, v_token, p_row_id;
        END IF;
    END IF;

    SELECT m.id INTO v_old_mapping_id
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game_id
       AND m.asset_source_id = v_asset_source_id
       AND m.raw_field = p_raw_field
       AND m.normalized_token = v_token
       AND m.is_active
     FOR UPDATE;

    IF v_old_mapping_id IS NOT NULL THEN
        SELECT COALESCE(
                   m.traits_signature,
                   ARRAY(SELECT mt.trait_id
                           FROM public.card_printing_external_mapping_trait mt
                          WHERE mt.mapping_id = m.id
                          ORDER BY mt.trait_id))
          INTO v_active_sig
          FROM public.card_printing_external_mapping m
         WHERE m.id = v_old_mapping_id;

        IF v_active_sig IS NULL OR cardinality(v_active_sig) = 0 THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_ACTIVE_COMPOSITION: o mapeamento ativo % deste token está com composição efetiva vazia — estado estruturalmente inválido. Corrigir a integridade do mapeamento antes de substituí-lo.', v_old_mapping_id;
        END IF;

        IF v_active_sig = v_signature THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_NO_CHANGE: o mapeamento ativo deste token já tem exatamente esta composição.';
        END IF;
    END IF;

    IF v_old_mapping_id IS NOT NULL THEN
        UPDATE public.card_printing_external_mapping
           SET is_active = FALSE
         WHERE id = v_old_mapping_id;
    END IF;

    INSERT INTO public.card_printing_external_mapping
        (game_id, asset_source_id, raw_field, normalized_token, external_token,
         is_active, supersedes_mapping_id)
    VALUES
        (v_game_id, v_asset_source_id, p_raw_field, v_token, p_token,
         TRUE, v_old_mapping_id)
    RETURNING id INTO v_new_mapping_id;

    INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT v_new_mapping_id, t, v_game_id FROM unnest(v_signature) t;

    WITH touched AS (
        SELECT r.id, r.job_id, j.card_set_id, s.*
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        CROSS JOIN LATERAL internal.compute_variant_residual_signature(
            r.raw_data, v_game_id, v_asset_source_id
        ) s
        WHERE j.status = 'STAGED'
          AND j.source = v_job_source
          AND j.card_set_id IN (
              SELECT cs2.id FROM public.card_set cs2
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
              WHERE e2.game_id = v_game_id
          )
          AND r.decision_status = 'PENDING'
          AND r.validation_status IN ('VALID', 'NEEDS_REVIEW')
          AND (
              (p_raw_field = 'subtype'
               AND public.normalize_external_catalog_value(r.raw_data ->> 'subtype') = v_token)
              OR
              (p_raw_field = 'stamp'
               AND jsonb_typeof(r.raw_data -> 'stamp') = 'array'
               AND EXISTS (
                   SELECT 1 FROM jsonb_array_elements_text(r.raw_data -> 'stamp') e
                    WHERE public.normalize_external_catalog_value(e) = v_token
               ))
          )
    ),
    classified AS (
        SELECT t.id,
               t.job_id,
               t.printing_profile_id,
               lk.variant_type_id,
               CASE
                 WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                      THEN 'C'
                 WHEN lk.variant_type_id IS NOT NULL
                      THEN 'A'
                 ELSE 'B'
               END AS outcome
        FROM touched t
        LEFT JOIN LATERAL (
            SELECT internal.lookup_variant_type_for_row(
                       v_game_id, v_asset_source_id, t.card_set_id,
                       t.residual_type, t.residual_foil,
                       t.residual_subtype, t.residual_stamp
                   ) AS variant_type_id
        ) lk ON TRUE
    ),
    updated AS (
        UPDATE public.catalog_variant_import_row r
        SET normalized_data =
                CASE c.outcome
                    WHEN 'A' THEN
                        jsonb_set(
                            jsonb_set(r.normalized_data,
                                      '{variant_type_id}',
                                      to_jsonb(c.variant_type_id::TEXT), true),
                            '{printing_profile_id}',
                            CASE WHEN c.printing_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                            true)
                    WHEN 'B' THEN
                        jsonb_set(
                            r.normalized_data - 'variant_type_id',
                            '{printing_profile_id}',
                            CASE WHEN c.printing_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                            true)
                    ELSE
                        (r.normalized_data - 'variant_type_id') - 'printing_profile_id'
                END,
            validation_status =
                CASE c.outcome WHEN 'A' THEN 'VALID' ELSE 'NEEDS_REVIEW' END
        FROM classified c
        WHERE r.id = c.id
        RETURNING r.id, r.job_id, c.outcome
    )
    SELECT
        (SELECT count(*) FROM updated WHERE outcome = 'A'),
        (SELECT count(*) FROM updated WHERE outcome IN ('B', 'C')),
        (SELECT count(DISTINCT job_id) FROM updated),
        (SELECT count(*) FROM touched),
        (SELECT count(*) FROM updated)
      INTO v_rows_updated, v_rows_pending, v_jobs_affected,
           v_touched_total, v_reconciled_total;

    IF v_reconciled_total IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
            v_touched_total, v_reconciled_total;
    END IF;

    IF (v_rows_updated + v_rows_pending) IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
            v_rows_updated, v_rows_pending, v_touched_total;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_PRINTING_EXTERNAL_MAPPING_CREATED',
            'CARD_PRINTING_EXTERNAL_MAPPING', v_new_mapping_id,
            jsonb_build_object(
                'game_id', v_game_id, 'asset_source_id', v_asset_source_id,
                'raw_field', p_raw_field, 'external_token', p_token, 'normalized_token', v_token,
                'trait_ids', to_jsonb(v_signature),
                'supersedes_mapping_id', v_old_mapping_id,
                'origin_row_id', p_row_id,
                'rows_revalidated', v_rows_updated,
                'rows_still_pending', v_rows_pending,
                'jobs_affected', v_jobs_affected
            )
        );

    RETURN QUERY SELECT v_new_mapping_id, v_old_mapping_id,
                        v_rows_updated, v_rows_pending, v_jobs_affected;
END;
$printing$;

-- ACL preservada por CREATE OR REPLACE. Os REVOKE/GRANT da Query
-- 2181 NÃO são repetidos aqui, pelo mesmo motivo da Query 2190:
-- repeti-los mascararia uma eventual perda de ACL que o postcheck
-- precisa ser capaz de detectar.


-- ---------------------------------------------------------------------------
-- SEGURANÇA. Reincorporado da Query 2181 v1.2: a migration 2197, por ser
-- reconciliação de corpo (CREATE OR REPLACE), não repetia os grants — eles já
-- existiam no LIVE. Numa INSTALAÇÃO LIMPA, porém, a função nasceria sem
-- REVOKE/GRANT explícitos, o que divergiria do LIVE (EXECUTE só para
-- authenticated, nenhum grant para anon/PUBLIC).
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) TO authenticated;

COMMIT;

/*
================================================================
VERIFICAÇÃO — reexecutável, read-only
================================================================
GATE-B, ANTES de aplicar este arquivo:

    SELECT md5(p.prosrc) = '2063b34d552766ff8cb220c9c6099f40' AS baseline_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping';

Se baseline_ok = FALSE, a função mudou entre o staging e a
aplicação: **STOP** e rebasear o diff. O harness 2826 carrega o
caso AA dedicado a esta checagem.

GATE-B, DEPOIS de aplicar:

    SELECT md5(p.prosrc) = 'b98f96a287f7c4d270c4239433bb6f2c' AS resultado_ok,
           length(p.prosrc) = 12524                           AS tamanho_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname = 'admin_resolve_catalog_variant_import_printing_mapping';

Ambos TRUE ⟹ o corpo aplicado é exatamente o prosrc anterior com
os quatro diffs declarados, e nada mais. É prova de diff exaustivo
por igualdade de hash — não por leitura visual.
================================================================
CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). As duas checagens
acima foram rodadas de verdade: baseline_ok = TRUE antes, resultado_ok = TRUE
e tamanho_ok = TRUE depois. Cópia mantida em proposals/ como evidência
histórica do ciclo.
================================================================
*/

-- ================================================================
-- CONFIRMADO EXECUTADO / LIVE.
--
-- Esta Query CANÔNICA foi reconciliada em 2026-09-18
-- (BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01): o corpo passou a
-- representar o ESTADO TERMINAL LIVE, provado equivalente por
-- md5(prosrc) normalizado contra pg_get_functiondef do Supabase
-- (projeto qjfutqujxrbzgrtkpgkg).
--
-- NÃO foi reexecutada contra o LIVE — fold-in canônico é alteração de
-- arquivo, não execução (database/README.md, "Queries CANÔNICA vs. MIGRATION").
-- As migrations que introduziram cada camada seguem preservadas em
-- database/migrations/ como histórico.
-- ================================================================
