/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5310 - Create collection_completion_summary_shared() (interna)
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (V1-12, autorização
              expressa do proprietário; ledger 20261030142433 `5310_create_collection_completion_summary_shared_function`).
              Idêntica ao arquivo de database/proposals/2026-10-30-v1-12-collection-sharing/
              (só este bloco Status difere); texto do ledger ≡ arquivo da proposta inteiro (md5).
              Validação: 5861 v1.3 51/51 PASS.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Progresso da coleção para leitura compartilhada (titular, VIEWER ou
público). Mesma matemática de collection_completion_summary() v6.0 (5188,
LIVE md5(prosrc)=27ccf51208b270822f01fe5188de06a1) — STANDARD_SET,
MASTER_SET e REFERENCE_POSITION —, com UMA diferença: a fronteira de
autorização dos dois ramos ("owner_user_id = auth.uid()") é substituída por
"collection_share_role(c.id) IS NOT NULL" (5302).

Por que uma cópia e não alterar 5188: a 5188 é contrato do titular, usado
por get_my_collections e pelas páginas da coleção; mexer nela para abrir
leitura a terceiros ampliaria a superfície de um contrato existente. A
cópia fica interna (sem EXECUTE para ninguém) e só a 5312 a chama.

Regras de Negócio:
- Sem acesso → zero linhas (idêntico a coleção inexistente).
- DEVER DE ESPELHO: qualquer mudança futura na matemática da 5188 precisa
  ser repetida aqui. A 5861 (caso S-PROG) confere, para o titular, que as
  duas funções devolvem exatamente o mesmo resultado.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_completion_summary_shared(p_collection_id UUID)
RETURNS TABLE (
    collection_id UUID,
    completion_policy TEXT,
    total_positions BIGINT,
    satisfied_positions BIGINT,
    missing_positions BIGINT,
    progress_percentage NUMERIC,
    is_complete BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        SELECT c.id AS collection_id, c.completion_policy AS completion_policy, ccsr.card_set_id AS card_set_id
        FROM public.collection c
        JOIN public.collection_reference cr ON cr.collection_id = c.id
        JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND public.collection_share_role(c.id) IS NOT NULL
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy IN ('STANDARD_SET', 'MASTER_SET')
    ),
    standard_denom AS (
        SELECT t.collection_id, t.completion_policy, count(card.id) AS total_positions
        FROM target t
        LEFT JOIN public.card card ON card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id, t.completion_policy
    ),
    standard_numer AS (
        SELECT t.collection_id, count(DISTINCT card.id) AS satisfied_positions
        FROM target t
        JOIN public.collection_allocation ca ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
        JOIN public.card card ON card.id = cv.card_id AND card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id
    ),
    master_target AS (
        SELECT t.collection_id, t.completion_policy, t.card_set_id,
               ARRAY(SELECT f.variant_type_id FROM public.collection_master_set_finish f
                     WHERE f.collection_id = t.collection_id) AS variant_type_ids
        FROM target t
        WHERE t.completion_policy = 'MASTER_SET'
    ),
    master_positions AS (
        SELECT mt.collection_id, p.card_id, p.variant_type_id
        FROM master_target mt
        CROSS JOIN LATERAL public.master_set_positions(mt.card_set_id, mt.variant_type_ids) p
    ),
    master_owned AS (
        SELECT DISTINCT cv.card_id, cv.variant_type_id
        FROM master_target mt
        JOIN public.collection_allocation ca ON ca.collection_id = mt.collection_id
        JOIN public.physical_card pc ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv ON cv.id = pc.card_variant_id
    ),
    master_denom AS (
        SELECT mt.collection_id, mt.completion_policy, count(mp.card_id) AS total_positions
        FROM master_target mt
        LEFT JOIN master_positions mp ON mp.collection_id = mt.collection_id
        GROUP BY mt.collection_id, mt.completion_policy
    ),
    master_numer AS (
        SELECT mp.collection_id, count(*) AS satisfied_positions
        FROM master_positions mp
        WHERE EXISTS (
            SELECT 1 FROM master_owned o
            WHERE o.card_id = mp.card_id
              AND (mp.variant_type_id IS NULL OR o.variant_type_id = mp.variant_type_id)
        )
        GROUP BY mp.collection_id
    ),
    reference_position_target AS (
        SELECT c.id AS collection_id, c.completion_policy AS completion_policy, cr.id AS reference_id,
               cpr.pokedex_id AS pokedex_id, cpr.scope_kind AS scope_kind
        FROM public.collection c
        JOIN public.collection_reference cr ON cr.collection_id = c.id AND cr.reference_kind = 'POKEDEX'
        JOIN public.collection_pokedex_reference cpr ON cpr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND public.collection_share_role(c.id) IS NOT NULL
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'REFERENCE_POSITION'
    ),
    reference_position_scope AS (
        SELECT t.collection_id, pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp ON pp.pokedex_id = t.pokedex_id
        WHERE t.scope_kind = 'FULL_REFERENCE'
        UNION ALL
        SELECT t.collection_id, pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp ON sp.id = pp.species_id
        JOIN public.collection_pokedex_scope_generation spg
          ON spg.collection_reference_id = t.reference_id AND spg.generation_id = sp.generation_id
        WHERE t.scope_kind = 'GENERATION_FILTERED'
    ),
    reference_position_denom AS (
        SELECT t.collection_id, t.completion_policy, count(s.pokedex_position_id) AS total_positions
        FROM reference_position_target t
        LEFT JOIN reference_position_scope s ON s.collection_id = t.collection_id
        GROUP BY t.collection_id, t.completion_policy
    ),
    reference_position_satisfied AS (
        SELECT DISTINCT t.collection_id, a.pokedex_position_id
        FROM reference_position_target t
        JOIN public.collection_allocation ca ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a ON a.collection_allocation_id = ca.id
    ),
    reference_position_numer AS (
        SELECT s.collection_id, count(DISTINCT s.pokedex_position_id) AS satisfied_positions
        FROM reference_position_scope s
        JOIN reference_position_satisfied sat
          ON sat.collection_id = s.collection_id AND sat.pokedex_position_id = s.pokedex_position_id
        GROUP BY s.collection_id
    ),
    denom AS (
        SELECT * FROM standard_denom
        UNION ALL SELECT * FROM master_denom
        UNION ALL SELECT * FROM reference_position_denom
    ),
    numer AS (
        SELECT * FROM standard_numer
        UNION ALL SELECT * FROM master_numer
        UNION ALL SELECT * FROM reference_position_numer
    )
    SELECT
        d.collection_id,
        d.completion_policy,
        d.total_positions,
        COALESCE(n.satisfied_positions, 0) AS satisfied_positions,
        d.total_positions - COALESCE(n.satisfied_positions, 0) AS missing_positions,
        CASE WHEN d.total_positions = 0 THEN 0.00
             ELSE round((COALESCE(n.satisfied_positions, 0)::NUMERIC / d.total_positions::NUMERIC) * 100, 2)
        END AS progress_percentage,
        CASE WHEN d.total_positions = 0 THEN FALSE
             ELSE COALESCE(n.satisfied_positions, 0) = d.total_positions
        END AS is_complete
    FROM denom d
    LEFT JOIN numer n ON n.collection_id = d.collection_id;
$$;

REVOKE ALL ON FUNCTION public.collection_completion_summary_shared(UUID) FROM PUBLIC, anon, authenticated;
