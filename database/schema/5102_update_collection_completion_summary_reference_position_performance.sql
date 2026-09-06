/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5102 - Update collection_completion_summary (v5.0 — remediação
               de performance do ramo REFERENCE_POSITION)
Versão......: 5.0 (corrige incrementalmente 5100 v4.0)
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-
               PERFORMANCE-REMEDIATION-STAGING-01, após BLOCKER de
               performance confirmado por 5815 v1.2 e análise de
               remediação em -PERFORMANCE-REMEDIATION-AUDIT-01,
               ALTERNATIVA B aprovada)

================================================================
MOTIVO — BLOCKER de performance medido (5815 v1.2)
================================================================
A execução real de 5815 v1.2 mediu o ramo REFERENCE_POSITION de
`collection_completion_summary()` (5100 v4.0) e de
`collection_pokedex_scope_positions()` (5101 v1.0) sobre a Pokédex
NATIONAL real (1025 Positions):

  FULL_REFERENCE 1025 / 828 Allocations ...  ~1357 ms / ~2,56 M shared hit
  FULL_REFERENCE 1025 / 878 Allocations ...  ~1454 ms / ~2,71 M shared hit
  GENERATION_FILTERED 156 / 156 ..........  ~44 ms  / ~73,7 k shared hit
  GENERATION_FILTERED 156 / 356 ..........  ~96 ms  / ~167,7 k shared hit

Normalizando os buffers pelo produto |Scope| x |Allocations|, a razão é
constante em ~3,02 blocks por par, estável em quatro estados
independentes que variam em duas ordens de grandeza (desvio < 0,5%):

  1025 x 828 = 848 700  ->  2 557 414 blocks  ->  3,013 / par
  1025 x 878 = 899 650  ->  2 713 214 blocks  ->  3,016 / par
   156 x 156 =  24 336  ->     73 677 blocks  ->  3,028 / par
   156 x 356 =  55 536  ->    167 745 blocks  ->  3,020 / par

Ou seja: o custo medido cresce com o PRODUTO |Scope| x |Allocations
da Collection|, não com a soma.

CAUSA ESTRUTURAL (grafo de junção, não plano interno):
No `reference_position_numer` de 5100, `reference_position_scope` e
`public.collection_allocation` são IRMÃOS — ambos se ligam apenas a
`reference_position_target` pelo mesmo `collection_id` constante, e
NÃO existe predicado direto entre eles. O único predicado que os
correlaciona (`a.pokedex_position_id = s.pokedex_position_id`) vive
numa TERCEIRA relação, `collection_pokedex_position_assignment`.
Qualquer ordem de junção precisa, em algum momento, combinar Scope e
Allocations; a forma atual não força nem favorece a única ordem que
evita o produto.

NOTA DE HONESTIDADE DE EVIDÊNCIA: o plano interno destas funções NÃO é
observável a partir do `Function Scan` externo do EXPLAIN (registrado
em -PERFORMANCE-EXECUTION-01 como INTERNAL PLAN VISIBILITY = NOT
OBSERVABLE). A afirmação acima é sobre a FUNÇÃO DE CUSTO MEDIDA e
sobre o GRAFO DE JUNÇÃO DO CÓDIGO — nenhuma alegação é feita sobre
nós de scan internos efetivamente escolhidos pelo planner.

================================================================
DECISÃO — ALTERNATIVA B (aprovada em -REMEDIATION-STAGING-01)
================================================================
Pré-calcular as Positions satisfeitas da Collection percorrendo
`collection_allocation -> collection_pokedex_position_assignment`
(sem tocar o Scope), e SOMENTE DEPOIS intersectar esse conjunto com o
Scope corrente.

Complexidade esperada: Theta(|Allocations|) para montar o conjunto
satisfeito + Theta(|Scope| + |satisfeitas|) para intersectar — ou seja
Theta(|Scope| + |Allocations|) no lugar de Theta(|Scope| x |Allocations|).

NENHUM ÍNDICE NOVO. Os dois access paths necessários já existem no
banco live e foram confirmados por inventário direto:
  - `ix_collection_allocation_collection` sobre
    collection_allocation(collection_id) — resolve "as Allocations
    desta Collection";
  - `collection_pokedex_position_assignment_pkey`, UNIQUE sobre
    collection_pokedex_position_assignment(collection_allocation_id)
    — resolve "o Assignment desta Allocation" em uma sonda, e garante
    no máximo 1 Assignment por Allocation.

Alternativas descartadas (ver -REMEDIATION-AUDIT-01):
  - EXISTS dirigido pelo Scope: NÃO corrige a assintótica com os
    índices atuais — ou revarre |Allocations| por Position (mesmo
    produto), ou entra por `idx_..._position_id` e passa a depender do
    volume GLOBAL de Assignments daquela Position em todas as
    Collections do banco (pior em produção).
  - Índice composto: impossível resolver por índice apenas, porque as
    duas colunas que precisariam ser combinadas
    (`collection_allocation.collection_id` e
    `collection_pokedex_position_assignment.pokedex_position_id`)
    vivem em TABELAS DIFERENTES. Só funcionaria denormalizando
    `collection_id` na tabela de Assignment — coluna nova, backfill,
    trigger e invariante novo, colidindo com o contrato de Assignment
    imutável fechado na Fatia D. Blast radius alto e desnecessário.

================================================================
ESCOPO DESTA QUERY — o que muda e o que NÃO muda
================================================================
Esta é uma correção INCREMENTAL sobre o corpo LIVE de 5100 v4.0
(confirmado por leitura direta de `pg_get_functiondef` no banco
`qjfutqujxrbzgrtkpgkg` antes desta redação). `5100` permanece como
artefato histórico e NUNCA é reescrito.

ALTERADO — exclusivamente o cálculo do numerator REFERENCE_POSITION:
  1. CTE NOVA `reference_position_satisfied`: conjunto DISTINCT de
     (collection_id, pokedex_position_id) das Assignments cujas
     Allocations pertencem à Collection. NÃO referencia o Scope.
  2. `reference_position_numer` deixa de ser
     `scope JOIN allocation JOIN assignment` (com o predicado de
     posição no terceiro join) e passa a ser a INTERSEÇÃO EXPLÍCITA
     `reference_position_scope JOIN reference_position_satisfied`
     por (collection_id, pokedex_position_id).

PRESERVADO byte-a-byte em relação ao corpo LIVE de 5100 v4.0:
  - assinatura `(p_collection_id UUID)`;
  - RETURNS TABLE (os 7 campos, mesma ordem e tipos);
  - LANGUAGE sql; STABLE; SECURITY DEFINER; SET search_path = '';
  - CTE `target` (fronteira de autorização CARD_SET);
  - `standard_denom`; `standard_numer`;
  - `master_denom`; `master_numer`;
  - `reference_position_target` (fronteira de autorização POKEDEX);
  - `reference_position_scope` (UNION ALL FULL_REFERENCE /
    GENERATION_FILTERED);
  - `reference_position_denom`;
  - o UNION ALL de 3 branches em `denom` e em `numer`;
  - o SELECT final (incluindo o tratamento de zero-denominator);
  - REVOKE/GRANT (ACL), reemitidos idênticos.

O agregado `count(DISTINCT s.pokedex_position_id)` é mantido LITERAL,
apesar de a nova forma tornar a junção 1:1 (o Scope não tem
`pokedex_position_id` repetido dentro de uma Collection, e
`reference_position_satisfied` já é DISTINCT). Manter o agregado
idêntico maximiza a segurança semântica ao custo de um passo de
deduplicação sobre no máximo |Scope| linhas — irrelevante em 1025.

================================================================
SEMÂNTICA INEGOCIÁVEL — preservada e por quê
================================================================
- numerator = Scope corrente INTERSECT Assignments da mesma
  Collection. Na forma anterior isso era obtido implicitamente pelo
  triplo join; agora é uma interseção literal. Os dois conjuntos são
  provadamente iguais: `scope JOIN ca JOIN a` sob
  `a.pokedex_position_id = s.pokedex_position_id` produz exatamente
  as Positions do Scope que possuem >= 1 Assignment na Collection —
  que é a definição de `scope INTERSECT satisfied`.
- SPECIES_MATCH e USER_OVERRIDE contam igualmente: nenhum filtro em
  `assignment_basis`, exatamente como antes.
- Assignment FORA do Scope: permanece fisicamente na tabela; entra em
  `reference_position_satisfied` mas é eliminado na interseção com
  `reference_position_scope`; nunca entra no numerator; nunca entra no
  denominator (`reference_position_denom` não foi tocado).
- Duplicatas na mesma Position: a PK única de Assignment garante 1
  Assignment por Allocation; N Physical Cards duplicadas produzem N
  Assignments com o MESMO `pokedex_position_id`, colapsados pelo
  DISTINCT de `reference_position_satisfied` a uma única linha. Uma
  Position continua contando UMA vez.
- Primary Representative: nunca consultado (LDM-182/184 são de outra
  fatia).
- `card_primary_species`, `physical_card`, `card_variant`: nunca
  consultados por este ramo.
- STANDARD_SET e MASTER_SET: intocados, byte-a-byte.
- Contrato externo: inalterado. Nenhum consumer quebra.

Segurança: inalterada. A fronteira de autorização continua sendo o
PRIMEIRO passo de cada target CTE, com `auth.uid() IS NOT NULL`
explícito e ownership reconstituído manualmente, nunca `is_admin()`.
`reference_position_satisfied` depende inteiramente de
`reference_position_target` já filtrado — não revalida nem relaxa
nada, e não alcança nenhuma Collection de outro Owner.

Não-enumeração preservada: Collection inexistente, de outro Owner, ou
com policy incompatível -> `reference_position_target` produz 0 linhas
-> o ramo inteiro produz 0 linhas, nunca erro.

Pré-requisitos:
- Query 5100 (v4.0) aplicada — esta Query a substitui via
  CREATE OR REPLACE.
- Query 6117 - Collection Pokedex Position Assignment Table.
- Query 5046 - allocate_physical_cards_to_collection().

VALIDAÇÃO OBRIGATÓRIA ANTES DE QUALQUER APLICAÇÃO LIVE:
`5816_performance_ab_fatia_e_reference_position_completion.sql` —
prova de equivalência semântica CURRENT vs CANDIDATE em todos os
estados, seguida de comparação A/B de performance. Além disso, `5814`
v1.3 (87 casos) deve ser reexecutado inalterado como regressão
funcional.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Corpo vivo de `collection_completion_summary()` no banco real desde
2026-09-06
(`COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01`),
substituindo `5100` v4.0. Equivalencia semantica CURRENT vs CANDIDATE
provada antes da aplicacao por `5816` v1.1 (A/B transacional com gate
fail-closed) — 13/13 CANDIDATE PASS. Regressao funcional: `5814` v1.3
reexecutado inalterado — 86/87, sendo o unico FAIL o POSTCHECK-2c (id 8),
falso-positivo textual confirmado e substituido por `5817` v1.0 (1/1
PASS). Performance final medida por `5815` v1.2 contra as funcoes live:
13 HEALTHY / 0 ATTENTION / 0 BLOCKER. Promovido em
`COLLECTIONS-POKEDEX-FATIA-E-CLOSEOUT-01`; cabecalho reconciliado em
`COLLECTIONS-POKEDEX-FATIA-E-FINAL-DOC-CORRECTION-01`, sem alterar um
unico byte do corpo executavel.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_completion_summary(
    p_collection_id UUID
)
RETURNS TABLE (
    collection_id       UUID,
    completion_policy   TEXT,
    total_positions     BIGINT,
    satisfied_positions BIGINT,
    missing_positions   BIGINT,
    progress_percentage NUMERIC,
    is_complete          BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: primeiro passo da query, antes de
        -- qualquer tabela do Catálogo Editorial. SECURITY DEFINER
        -- bypassa RLS, então ownership é reconstituído manualmente
        -- aqui — nunca iniciar por card/card_variant e checar
        -- ownership depois.
        SELECT
            c.id                AS collection_id,
            c.completion_policy AS completion_policy,
            ccsr.card_set_id    AS card_set_id
        FROM public.collection c
        JOIN public.collection_reference cr
            ON cr.collection_id = c.id
        JOIN public.collection_card_set_reference ccsr
            ON ccsr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy IN ('STANDARD_SET', 'MASTER_SET')
    ),

    -- Ramo STANDARD_SET (inalterado de 5070 v2.0/5083 v3.0/5100 v4.0):
    -- denominador = Card do Card Set referenciado; numerador = Card
    -- satisfeita por qualquer Variant daquela Card alocada à Collection.
    standard_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(card.id) AS total_positions
        FROM target t
        LEFT JOIN public.card card
            ON card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id, t.completion_policy
    ),
    standard_numer AS (
        SELECT
            t.collection_id,
            count(DISTINCT card.id) AS satisfied_positions
        FROM target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
        JOIN public.card_variant cv
            ON cv.id = pc.card_variant_id
        JOIN public.card card
            ON card.id = cv.card_id
           AND card.card_set_id = t.card_set_id
        WHERE t.completion_policy = 'STANDARD_SET'
        GROUP BY t.collection_id
    ),

    -- Ramo MASTER_SET (inalterado de 5083 v3.0/5100 v4.0): denominador
    -- = Adopted Scope; numerador = Variant do Scope com correspondência
    -- EXATA de Physical Card alocada (LDM-19/LDM-20/LDM-21).
    master_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(s.card_variant_id) AS total_positions
        FROM target t
        LEFT JOIN public.collection_master_set_scope s
            ON s.collection_id = t.collection_id
        WHERE t.completion_policy = 'MASTER_SET'
        GROUP BY t.collection_id, t.completion_policy
    ),
    master_numer AS (
        SELECT
            t.collection_id,
            count(DISTINCT s.card_variant_id) AS satisfied_positions
        FROM target t
        JOIN public.collection_master_set_scope s
            ON s.collection_id = t.collection_id
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.physical_card pc
            ON pc.id = ca.physical_card_id
           AND pc.card_variant_id = s.card_variant_id   -- correspondência EXATA de Variant
        WHERE t.completion_policy = 'MASTER_SET'
        GROUP BY t.collection_id
    ),

    -- ============================================================
    -- Ramo REFERENCE_POSITION (Fatia E). Independente de `target`
    -- (CARD_SET-específico) por desenho explícito (FATIA-E-MODELING-
    -- REVISION-01, item 2).
    -- ============================================================

    -- Fronteira de autorização própria deste ramo — mesma disciplina
    -- de `target`, mas contra o subtipo POKEDEX. INALTERADA em v5.0.
    reference_position_target AS (
        SELECT
            c.id                 AS collection_id,
            c.completion_policy  AS completion_policy,
            cr.id                AS reference_id,
            cpr.pokedex_id       AS pokedex_id,
            cpr.scope_kind       AS scope_kind
        FROM public.collection c
        JOIN public.collection_reference cr
            ON cr.collection_id = c.id
           AND cr.reference_kind = 'POKEDEX'
        JOIN public.collection_pokedex_reference cpr
            ON cpr.collection_reference_id = cr.id
        WHERE c.id = p_collection_id
          AND (select auth.uid()) IS NOT NULL          -- defesa explícita, nunca is_admin()
          AND c.owner_user_id = (select auth.uid())    -- ownership reconstituído manualmente
          AND c.mode = 'REFERENCE_BASED'
          AND c.completion_policy = 'REFERENCE_POSITION'
    ),

    -- Positions do Scope corrente (LDM-177). UNION ALL de dois ramos
    -- mutuamente exclusivos por construção (scope_kind é valor único
    -- por Collection Pokédex Reference) — nenhuma duplicidade possível.
    -- INALTERADA em v5.0.
    reference_position_scope AS (
        SELECT
            t.collection_id,
            pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        WHERE t.scope_kind = 'FULL_REFERENCE'

        UNION ALL

        SELECT
            t.collection_id,
            pp.id AS pokedex_position_id
        FROM reference_position_target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        JOIN public.collection_pokedex_scope_generation spg
            ON spg.collection_reference_id = t.reference_id
           AND spg.generation_id = sp.generation_id
        WHERE t.scope_kind = 'GENERATION_FILTERED'
    ),

    -- Denominador: contagem de Positions do Scope corrente. Shape
    -- idêntico a standard_denom/master_denom. LEFT JOIN preserva
    -- zero-denominator (Scope vazio -> total_positions = 0) sem CASE
    -- adicional, mesmo padrão dos outros dois ramos.
    -- INALTERADA em v5.0.
    reference_position_denom AS (
        SELECT
            t.collection_id,
            t.completion_policy,
            count(s.pokedex_position_id) AS total_positions
        FROM reference_position_target t
        LEFT JOIN reference_position_scope s
            ON s.collection_id = t.collection_id
        GROUP BY t.collection_id, t.completion_policy
    ),

    -- ============================================================
    -- NOVA em v5.0 (ALTERNATIVA B) — Positions satisfeitas da
    -- Collection, calculadas SEM referência ao Scope.
    --
    -- Caminho: reference_position_target -> collection_allocation
    -- (por collection_id, via ix_collection_allocation_collection)
    -- -> collection_pokedex_position_assignment (por
    -- collection_allocation_id, via a PK única da tabela — 1 sonda,
    -- no máximo 1 Assignment por Allocation).
    -- Custo esperado: Theta(|Allocations da Collection|).
    --
    -- O DISTINCT colapsa duplicatas: N Physical Cards distintas
    -- satisfazendo a MESMA Position produzem N Assignments com o mesmo
    -- pokedex_position_id, e uma única linha aqui.
    --
    -- Assignments FORA do Scope corrente entram neste conjunto — e são
    -- eliminados na interseção logo abaixo. Permanecem fisicamente
    -- preservados na tabela, exatamente como antes.
    --
    -- Nenhum filtro em assignment_basis: SPECIES_MATCH e USER_OVERRIDE
    -- contam igualmente. Nunca consulta Primary Representative,
    -- card_primary_species, physical_card ou card_variant.
    -- ============================================================
    reference_position_satisfied AS (
        SELECT DISTINCT
            t.collection_id,
            a.pokedex_position_id
        FROM reference_position_target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
    ),

    -- ============================================================
    -- ALTERADA em v5.0 (ALTERNATIVA B) — numerator como INTERSEÇÃO
    -- EXPLÍCITA entre o Scope corrente e as Positions satisfeitas.
    --
    -- Antes (5100 v4.0): reference_position_scope JOIN
    -- collection_allocation JOIN collection_pokedex_position_assignment,
    -- com scope e allocation como irmãos sem predicado entre si — custo
    -- medido Theta(|Scope| x |Allocations|).
    --
    -- Agora: os dois conjuntos já estão prontos e a interseção é uma
    -- junção 1:1 por (collection_id, pokedex_position_id) —
    -- Theta(|Scope| + |satisfeitas|).
    --
    -- Conjunto resultante PROVADAMENTE idêntico: as Positions do Scope
    -- que possuem >= 1 Assignment na Collection.
    --
    -- count(DISTINCT ...) mantido literal em relação a v4.0 por
    -- segurança semântica (a junção já é 1:1; o DISTINCT é redundante
    -- mas inofensivo sobre no máximo |Scope| linhas).
    -- ============================================================
    reference_position_numer AS (
        SELECT
            s.collection_id,
            count(DISTINCT s.pokedex_position_id) AS satisfied_positions
        FROM reference_position_scope s
        JOIN reference_position_satisfied sat
            ON sat.collection_id        = s.collection_id
           AND sat.pokedex_position_id  = s.pokedex_position_id
        GROUP BY s.collection_id
    ),

    denom AS (
        SELECT * FROM standard_denom
        UNION ALL
        SELECT * FROM master_denom
        UNION ALL
        SELECT * FROM reference_position_denom
    ),
    numer AS (
        SELECT * FROM standard_numer
        UNION ALL
        SELECT * FROM master_numer
        UNION ALL
        SELECT * FROM reference_position_numer
    )
    SELECT
        d.collection_id,
        d.completion_policy,
        d.total_positions,
        COALESCE(n.satisfied_positions, 0) AS satisfied_positions,
        d.total_positions - COALESCE(n.satisfied_positions, 0) AS missing_positions,
        CASE
            WHEN d.total_positions = 0 THEN 0.00
            ELSE round(
                (COALESCE(n.satisfied_positions, 0)::NUMERIC / d.total_positions::NUMERIC) * 100,
                2
            )
        END AS progress_percentage,
        CASE
            WHEN d.total_positions = 0 THEN FALSE
            ELSE COALESCE(n.satisfied_positions, 0) = d.total_positions
        END AS is_complete
    FROM denom d
    LEFT JOIN numer n ON n.collection_id = d.collection_id;
$$;

REVOKE ALL ON FUNCTION public.collection_completion_summary(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_completion_summary(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_completion_summary(uuid) TO authenticated;
