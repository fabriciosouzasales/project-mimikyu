/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2181 - Create admin_resolve_catalog_variant_import_printing_mapping()
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§7, §20, §21)
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

Regras de Negócio:
- Admin-only, primeira instrucao.
- raw_field restrito a 'subtype'/'stamp'.
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
===============================================================================
*/

BEGIN;

-- =========================================================================
-- GUARD DE DEPENDÊNCIA — a ordem de aplicação é a ordem das FASES do
-- README, não a ordem numérica. Este guard torna a única dependência
-- real (2185 antes de 2181) auto-verificável: sem ele, a função seria
-- criada com sucesso e só falharia na primeira chamada editorial real,
-- em produção, no meio de uma transação de resolução.
-- =========================================================================
DO $dep$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_constraint c
         WHERE c.conrelid = 'public.catalog_admin_action_log'::regclass
           AND c.conname = 'ck_catalog_admin_action_log_action_valid'
           AND position('CARD_PRINTING_EXTERNAL_MAPPING_CREATED' IN pg_get_constraintdef(c.oid)) > 0
    ) THEN
        RAISE EXCEPTION 'PRINTING_MAPPING_RPC_MISSING_ACTION_LOG_CONTRACT: catalog_admin_action_log ainda não aceita CARD_PRINTING_EXTERNAL_MAPPING_CREATED. Aplicar a Query 2185 ANTES desta. STOP.';
    END IF;
END;
$dep$;

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(
    p_row_id UUID,
    p_raw_field TEXT,
    p_token TEXT,
    p_trait_ids UUID[]
)
RETURNS TABLE (
    mapping_id UUID,
    superseded_mapping_id UUID,
    rows_updated INTEGER,
    rows_still_pending INTEGER,
    jobs_affected INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    c_max_traits CONSTANT INTEGER := 20;

    v_row public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_token TEXT;
    v_signature UUID[];
    v_active_sig UUID[];                 -- (v1.2/B-05) composicao EFETIVA do ativo
    v_old_mapping_id UUID;
    v_new_mapping_id UUID;
    v_rows_updated INTEGER;
    v_rows_pending INTEGER;
    v_jobs_affected INTEGER;
    v_touched_total INTEGER;             -- (v1.2/§4) invariante de contagem
    v_reconciled_total INTEGER;          -- (v1.2/§4) invariante de contagem
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

    -- Validacao pura de payload, antes de qualquer lock.
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

    -- Conjunto canonico: distinto e ordenado. Duplicata no payload e
    -- rejeitada explicitamente em vez de silenciosamente colapsada.
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

    -- Traits: existencia, same-Game e ATIVIDADE. Trait inativo nao pode
    -- entrar num mapping novo — seria criar routing que ja nasce levando
    -- a NEEDS_REVIEW.
    IF (SELECT count(*) FROM public.card_printing_trait t
         WHERE t.id = ANY (v_signature) AND t.game_id = v_game_id AND t.is_active)
       <> cardinality(v_signature) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_TRAITS: uma ou mais Características de Impressão não existem, pertencem a outro Game ou estão inativas.';
    END IF;

    v_token := public.normalize_external_catalog_value(p_token);
    IF btrim(v_token) = '' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_EMPTY_TOKEN: o token normalizado ficou vazio (recebido: %).', p_token;
    END IF;

    -- =================================================================
    -- ORIGIN-ROW BINDING (v1.2 / B-04)
    --
    -- A linha de origem tem que ser EVIDENCIA REAL da combinacao que
    -- esta sendo ratificada. Sem esta prova, p_row_id seria apenas um
    -- portador de contexto (Game/Fonte) e o origin_row_id gravado no
    -- action log seria uma afirmacao NAO VERIFICADA.
    --
    -- Comparacao por IGUALDADE do valor CANONICO normalizado, nos dois
    -- lados. Nunca LIKE, substring, prefixo, split ou fuzzy — pelo mesmo
    -- motivo que a Query 2176 nao os usa: '1st-edition-error' nao e
    -- '1st-edition', e nenhuma heuristica pode decidir que e.
    --
    -- POSICAO DESTE BLOCO E CONTRATUAL: ele vem DEPOIS das validacoes
    -- puras de payload (EMPTY_TRAITS, DUPLICATE_TRAIT, NULL_TRAIT,
    -- TOO_MANY_TRAITS, INVALID_FIELD) e ANTES do lock. Payload invalido
    -- continua sendo rejeitado sem que a origem seja sequer consultada —
    -- contrato do qual a Secao S13b da Query 2824 depende.
    -- =================================================================
    IF p_raw_field = 'subtype' THEN
        IF public.normalize_external_catalog_value(v_row.raw_data ->> 'subtype')
           IS DISTINCT FROM v_token THEN
            RAISE EXCEPTION 'PRINTING_MAPPING_ORIGIN_TOKEN_NOT_FOUND: o token % (normalizado: %) não é o subtype da linha de origem %. A linha informada precisa conter exatamente esta combinação — ela é a evidência editorial da decisão.',
                p_token, v_token, p_row_id;
        END IF;
    ELSE
        -- p_raw_field = 'stamp' (o dominio ja foi restrito acima).
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

    -- =================================================================
    -- PASSO 1 — lock do ativo atual, se existir.
    -- =================================================================
    SELECT m.id INTO v_old_mapping_id
      FROM public.card_printing_external_mapping m
     WHERE m.game_id = v_game_id
       AND m.asset_source_id = v_asset_source_id
       AND m.raw_field = p_raw_field
       AND m.normalized_token = v_token
       AND m.is_active
     FOR UPDATE;

    -- =================================================================
    -- NO_CHANGE POR COMPOSICAO EFETIVA (v1.2 / B-05)
    --
    -- A v1.1 lia m.traits_signature CRUA. O selo e DEFERIDO: se o ativo
    -- tiver nascido nesta MESMA transacao, a assinatura ainda e NULL e
    -- `NULL = v_signature` devolve NULL — o guard nao dispara e uma
    -- substituicao por composicao IDENTICA passa silenciosamente.
    --
    -- Composicao EFETIVA = assinatura selada OU, quando ela ainda for
    -- NULL, a N:N transacional ordenada. Mesmo contrato semantico da
    -- Query 2176 v1.1. Aqui NAO se resolve perfil nem se reimplementa
    -- roteamento: so se le a composicao atual do mapping existente.
    -- =================================================================
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

        -- Header ACTIVE com composicao efetiva vazia e estado
        -- ESTRUTURALMENTE INVALIDO — nao e "composicao diferente".
        -- Fail-closed: nao substituir por cima de um estado que nao
        -- deveria existir.
        IF v_active_sig IS NULL OR cardinality(v_active_sig) = 0 THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_INVALID_ACTIVE_COMPOSITION: o mapeamento ativo % deste token está com composição efetiva vazia — estado estruturalmente inválido. Corrigir a integridade do mapeamento antes de substituí-lo.', v_old_mapping_id;
        END IF;

        -- Substituir por um conjunto IDENTICO seria ruido editorial puro.
        IF v_active_sig = v_signature THEN
            RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_NO_CHANGE: o mapeamento ativo deste token já tem exatamente esta composição.';
        END IF;
    END IF;

    -- =================================================================
    -- PASSO 2 — aposenta o antigo ANTES de inserir o novo.
    -- =================================================================
    IF v_old_mapping_id IS NOT NULL THEN
        UPDATE public.card_printing_external_mapping
           SET is_active = FALSE
         WHERE id = v_old_mapping_id;
    END IF;

    -- =================================================================
    -- PASSO 3 — cabecalho novo ACTIVE.
    -- =================================================================
    INSERT INTO public.card_printing_external_mapping
        (game_id, asset_source_id, raw_field, normalized_token, external_token,
         is_active, supersedes_mapping_id)
    VALUES
        (v_game_id, v_asset_source_id, p_raw_field, v_token, p_token,
         TRUE, v_old_mapping_id)
    RETURNING id INTO v_new_mapping_id;

    -- =================================================================
    -- PASSO 4 — composicao COMPLETA.
    -- =================================================================
    INSERT INTO public.card_printing_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT v_new_mapping_id, t, v_game_id FROM unnest(v_signature) t;

    -- =================================================================
    -- PASSO 5 — propagacao cross-job COM RECONCILIACAO COMPLETA
    --           (v1.2 / B-06)
    --
    -- compute_variant_residual_signature() ja enxerga o mapping novo
    -- (mesma transacao) via card_printing_external_mapping_trait — e NAO
    -- via traits_signature, que so sera gravada no COMMIT.
    --
    -- Reavalia rows STAGED do mesmo Game+Fonte, inclusive as que ja
    -- estavam VALID pelo mapping anterior. TODAS as atingidas sao
    -- reconciliadas: a v1.1 so escrevia nas que RESOLVIAM, e por isso
    -- uma row que deixasse de resolver conservava VALID + o perfil
    -- ANTIGO — identidade canonica obsoleta que o confirm aceitaria.
    -- =================================================================
    WITH touched AS (
        SELECT r.id, r.job_id, s.*
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
          -- EXCLUSAO DELIBERADA E DOCUMENTADA (ver cabecalho):
          -- PENDING e INVALID nao sao reavaliadas por uma decisao de
          -- Impressao. Elas nao entram em nenhum dos dois contadores.
          AND r.validation_status IN ('VALID', 'NEEDS_REVIEW')
          -- Atingidas pelo TOKEN: e o escopo minimo correto.
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
    -- Classificacao em A / B / C. O LEFT JOIN permite distinguir
    -- "Variant Type nao encontrado" (B) de "Printing nao resolvido" (C);
    -- o CASE e avaliado em ordem, entao C tem precedencia sobre B.
    -- O par aceito e testado por PERTENCIMENTO: qualquer estado futuro
    -- de Printing cai em C automaticamente.
    classified AS (
        SELECT t.id,
               t.job_id,
               t.printing_profile_id,
               vm.variant_type_id,
               CASE
                 WHEN t.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
                      THEN 'C'
                 WHEN vm.variant_type_id IS NOT NULL
                      THEN 'A'
                 ELSE 'B'
               END AS outcome
        FROM touched t
        LEFT JOIN public.card_variant_type_external_mapping vm
          ON vm.game_id = v_game_id
         AND vm.asset_source_id = v_asset_source_id
         AND vm.normalized_type = t.residual_type
         AND COALESCE(vm.normalized_foil, '')    = COALESCE(t.residual_foil, '')
         AND COALESCE(vm.normalized_subtype, '') = COALESCE(t.residual_subtype, '')
         AND COALESCE(vm.normalized_stamp, '{}'::TEXT[]) = COALESCE(t.residual_stamp, '{}'::TEXT[])
    ),
    updated AS (
        UPDATE public.catalog_variant_import_row r
        SET normalized_data =
                CASE c.outcome
                    -- A: Printing e Variant Type resolvidos.
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
                    -- B: Printing resolvido, Variant Type nao. O
                    -- variant_type_id antigo e REMOVIDO; o perfil
                    -- resolvido permanece explicito.
                    WHEN 'B' THEN
                        jsonb_set(
                            r.normalized_data - 'variant_type_id',
                            '{printing_profile_id}',
                            CASE WHEN c.printing_profile_id IS NULL
                                 THEN 'null'::JSONB
                                 ELSE to_jsonb(c.printing_profile_id::TEXT) END,
                            true)
                    -- C: Printing nao resolvido. O residual deixa de ser
                    -- identidade canonica confiavel — as DUAS chaves saem.
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

    -- INVARIANTE DE CONTAGEM (§4). Toda row atingida termina em
    -- exatamente um estado terminal, e os dois contadores particionam o
    -- universo. Se isto falhar, alguma row escapou da reconciliacao —
    -- fail-closed, nunca silenciar num contador residual.
    IF v_reconciled_total IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_RECONCILIATION_GAP: % linha(s) atingidas, % reconciliadas. Alguma linha ficou sem estado terminal definido.',
            v_touched_total, v_reconciled_total;
    END IF;

    IF (v_rows_updated + v_rows_pending) IS DISTINCT FROM v_touched_total THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_PRINTING_MAPPING_COUNTER_GAP: rows_revalidated (%) + rows_still_pending (%) <> universo atingido (%).',
            v_rows_updated, v_rows_pending, v_touched_total;
    END IF;

    -- Contrato PRÓPRIO de auditoria (Query 2185). entity_id = id do
    -- mapping NOVO: ele e a entidade criada. A substituicao esta
    -- integralmente descrita aqui — nao ha evento separado de
    -- SUPERSEDED porque nao ha ato separado: tudo acontece nesta
    -- transacao.
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
$$;

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_printing_mapping(UUID, TEXT, TEXT, UUID[]) TO authenticated;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION, REVOKE, GRANT.
--
-- catalog_admin_action_log (contrato FECHADO na v1.1):
--   action      = CARD_PRINTING_EXTERNAL_MAPPING_CREATED
--   entity_type = CARD_PRINTING_EXTERNAL_MAPPING
--   entity_id   = id do mapping novo
--   Ambos criados pela Query 2185, obrigatoriamente ANTERIOR.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing (BLOCO I / GATE-A):
--     Secao S13 — H13, duplicata e conjunto vazio (comportamental);
--                 e a ORDEM: payload invalido falha ANTES do origin binding
--     Secao S14 — H27, substituicao nao toca card_variant;
--                 NO_CHANGE antes do selo diferido (B-05)
--     Secao S19 — R4, contrato de auditoria
--     Secao S28 — B-06 (reconciliacao terminal A/B/C) e
--                 OB1..OB6 (origin-row binding, B-04)
-- ============================================================================
