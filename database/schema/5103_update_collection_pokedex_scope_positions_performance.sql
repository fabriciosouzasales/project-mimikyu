/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5103 - Update collection_pokedex_scope_positions (v2.0 —
               remediação de performance)
Versão......: 2.0 (corrige incrementalmente 5101 v1.0)
Status......: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-06 (staging em COLLECTIONS-POKEDEX-FATIA-E-
               PERFORMANCE-REMEDIATION-STAGING-01, após BLOCKER de
               performance confirmado por 5815 v1.2 e análise de
               remediação em -PERFORMANCE-REMEDIATION-AUDIT-01,
               ALTERNATIVA B aprovada)

================================================================
MOTIVO — mesmo BLOCKER medido em 5100, presente aqui na CTE `satisfied`
================================================================
`collection_pokedex_scope_positions()` (5101 v1.0) foi medida por 5815
v1.2 exatamente nos mesmos estados de `collection_completion_summary()`
e exibiu o MESMO comportamento — inclusive tempos praticamente
idênticos, sinal de que o custo dominante é comum às duas funções:

  FULL_REFERENCE 1025 / 828 Allocations, positions FALSE .. ~1357 ms
  FULL_REFERENCE 1025 / 828 Allocations, positions TRUE ... ~1358 ms
  GENERATION_FILTERED 156 / 156, positions TRUE ..........   ~43 ms
  GENERATION_FILTERED 156 / 356, positions FALSE .........   ~96 ms

Observação relevante: o workload `positions TRUE` em high-density
devolve apenas 197 linhas e mesmo assim custa o mesmo que `positions
FALSE`, que devolve 1025 — ou seja, `p_only_missing` NÃO reduz o
trabalho, porque `satisfied` é integralmente computada antes.

CAUSA ESTRUTURAL (grafo de junção, não plano interno): na CTE
`satisfied` de 5101, `scope` e `public.collection_allocation` são
IRMÃOS — ambos ligados apenas a `target` pelo mesmo `collection_id`
constante, sem predicado direto entre si. O predicado que os
correlaciona (`a.pokedex_position_id = s.pokedex_position_id`) vive na
terceira relação. Custo medido: Theta(|Scope| x |Allocations|), com
constante estável de ~3,02 shared blocks por par (evidência completa no
cabeçalho de 5102 e em -PERFORMANCE-EXECUTION-01).

NOTA DE HONESTIDADE DE EVIDÊNCIA: INTERNAL PLAN VISIBILITY = NOT
OBSERVABLE. Nenhuma alegação é feita sobre nós de scan internos
efetivamente escolhidos pelo planner.

================================================================
DECISÃO — ALTERNATIVA B (aprovada em -REMEDIATION-STAGING-01)
================================================================
`satisfied` passa a ser calculada percorrendo APENAS
`collection_allocation -> collection_pokedex_position_assignment`,
sem qualquer referência ao Scope. A interseção com o Scope passa a
acontecer uma única vez, no LEFT JOIN do SELECT final — que já era a
forma da v1.0.

Complexidade esperada: Theta(|Allocations|) para montar `satisfied` +
Theta(|Scope| + |satisfied|) no LEFT JOIN = Theta(|Scope| + |Allocations|).

NENHUM ÍNDICE NOVO. Usa `ix_collection_allocation_collection` e a PK
única `collection_pokedex_position_assignment_pkey`, ambos já
existentes no banco live (inventário confirmado em
-REMEDIATION-AUDIT-01).

BENEFÍCIO COLATERAL: com `satisfied` deixando de referenciar `scope`,
o CTE `scope` passa a ser referenciado UMA ÚNICA VEZ (apenas no SELECT
final). Pela semântica do PostgreSQL, um CTE não-recursivo referenciado
uma só vez é elegível a inlining — o que remove também a barreira de
materialização que existia na v1.0 (onde `scope` era referenciado duas
vezes). Isto é um efeito esperado, não uma garantia: a medição em 5816
é quem decide.

================================================================
ESCOPO DESTA QUERY — o que muda e o que NÃO muda
================================================================
Correção INCREMENTAL sobre o corpo LIVE de 5101 v1.0 (confirmado por
leitura direta de `pg_get_functiondef` no banco `qjfutqujxrbzgrtkpgkg`
antes desta redação). `5101` permanece como artefato histórico e NUNCA
é reescrito.

ALTERADO — exclusivamente:
  1. CTE `satisfied`: deixa de fazer `target JOIN scope JOIN allocation
     JOIN assignment` e passa a fazer `target JOIN allocation JOIN
     assignment`, projetando `SELECT DISTINCT t.collection_id,
     a.pokedex_position_id`. Sem nenhuma referência a `scope`.
  2. A cláusula ON do LEFT JOIN do SELECT final ganha a igualdade de
     `collection_id`, já que `satisfied` agora carrega essa coluna:
        ON  sat.collection_id       = s.collection_id
        AND sat.pokedex_position_id = s.pokedex_position_id
     (na v1.0 o ON tinha apenas a segunda condição, porque `satisfied`
     projetava só `pokedex_position_id`).

PRESERVADO byte-a-byte em relação ao corpo LIVE de 5101 v1.0:
  - assinatura `(p_collection_id UUID, p_only_missing BOOLEAN DEFAULT FALSE)`;
  - RETURNS TABLE (pokedex_position_id, position_number, species_id,
    species_name VARCHAR(150), is_satisfied) — mesma ordem e tipos;
  - LANGUAGE sql; STABLE; SECURITY DEFINER; SET search_path = '';
  - CTE `target` (fronteira de autorização, integralmente);
  - CTE `scope` (UNION ALL FULL_REFERENCE / GENERATION_FILTERED,
    incluindo position_number, species_id e species_name);
  - a lista de projeção do SELECT final, incluindo
    `(sat.pokedex_position_id IS NOT NULL) AS is_satisfied`;
  - a cláusula `WHERE (NOT p_only_missing) OR sat.pokedex_position_id IS NULL`;
  - o `ORDER BY s.position_number, s.pokedex_position_id`;
  - REVOKE/GRANT (ACL), reemitidos idênticos.

================================================================
SEMÂNTICA INEGOCIÁVEL — preservada e por quê
================================================================
- Uma Position do Scope é satisfeita <=> existe >= 1 Assignment da
  MESMA Collection para aquela Position. Na v1.0 isso era obtido pelo
  triplo join dentro de `satisfied`; agora `satisfied` produz todas as
  Positions com Assignment na Collection e o LEFT JOIN restringe ao
  Scope. Conjunto resultante de `is_satisfied = true` provadamente
  idêntico.
- SPECIES_MATCH e USER_OVERRIDE contam igualmente: nenhum filtro em
  `assignment_basis`, exatamente como antes.
- Assignment FORA do Scope corrente: permanece fisicamente na tabela;
  entra em `satisfied`; NÃO aparece na saída, porque a saída é dirigida
  por `scope` (o LEFT JOIN parte de `scope`, nunca de `satisfied`).
  Não afeta `is_satisfied` de nenhuma Position do Scope, porque a
  junção exige igualdade de `pokedex_position_id`.
- Duplicatas na mesma Position: colapsadas pelo DISTINCT; a Position
  aparece uma única vez na saída, com `is_satisfied = true`. A junção
  permanece 1:1 (o Scope não repete `pokedex_position_id` dentro de uma
  Collection, e `satisfied` é DISTINCT), portanto nenhuma linha é
  duplicada na saída — invariante que a v1.0 também garantia.
- `p_only_missing`: comportamento inalterado.
- Primary Representative, `card_primary_species`, `physical_card`,
  `card_variant`: nunca consultados. O contrato congelado de 5 campos
  permanece sem qualquer dado de UX.
- Contrato externo: inalterado. Nenhum consumer quebra.

Segurança: inalterada. Toda a fronteira de autorização continua vivendo
em `target` — primeiro passo, `auth.uid() IS NOT NULL` explícito,
ownership reconstituído manualmente, `mode = 'REFERENCE_BASED'`,
`completion_policy = 'REFERENCE_POSITION'`, `reference_kind = 'POKEDEX'`.
`satisfied` depende inteiramente de `target` já filtrado e não alcança
Collection de outro Owner. Nenhuma subquery revalida owner, como antes.

Não-enumeração preservada: Collection inexistente, de outro Owner,
`mode` diferente de REFERENCE_BASED ou `completion_policy` diferente de
REFERENCE_POSITION -> `target` produz 0 linhas -> a função inteira
retorna 0 linhas, nunca erro.

Pré-requisitos:
- Query 5101 (v1.0) aplicada — esta Query a substitui via
  CREATE OR REPLACE.
- Query 5102 (mesma rodada) — mesma decisão de remediação aplicada ao
  ramo REFERENCE_POSITION de collection_completion_summary().
- Query 6117 - Collection Pokedex Position Assignment Table.

VALIDAÇÃO OBRIGATÓRIA ANTES DE QUALQUER APLICAÇÃO LIVE:
`5816_performance_ab_fatia_e_reference_position_completion.sql` —
equivalência semântica CURRENT vs CANDIDATE em todos os estados,
seguida da comparação A/B de performance. Além disso, `5814` v1.3
(87 casos) deve ser reexecutado inalterado como regressão funcional.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO / LIVE / PROMOVIDO.

Corpo vivo de `collection_pokedex_scope_positions()` no banco real desde
2026-09-06
(`COLLECTIONS-POKEDEX-FATIA-E-PERFORMANCE-REMEDIATION-IMPLEMENTATION-01`),
substituindo `5101` v1.0. Equivalencia semantica CURRENT vs CANDIDATE
provada antes da aplicacao por `5816` v1.1 (A/B transacional com gate
fail-closed) — 13/13 CANDIDATE PASS. Regressao funcional: `5814` v1.3
reexecutado inalterado — 86/87, sendo o unico FAIL o POSTCHECK-2c (id 8),
falso-positivo textual causado por `_` como wildcard em `ILIKE` sobre
tokens presentes apenas em COMENTARIOS deste arquivo; substituido por
`5817` v1.0 (1/1 PASS, comparacao literal com `position()` sobre o source
com comentarios removidos). Performance final medida por `5815` v1.2
contra as funcoes live: 13 HEALTHY / 0 ATTENTION / 0 BLOCKER. Promovido
em `COLLECTIONS-POKEDEX-FATIA-E-CLOSEOUT-01`; cabecalho reconciliado em
`COLLECTIONS-POKEDEX-FATIA-E-FINAL-DOC-CORRECTION-01`, sem alterar um
unico byte do corpo executavel.
================================================================
*/

CREATE OR REPLACE FUNCTION public.collection_pokedex_scope_positions(
    p_collection_id UUID,
    p_only_missing  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    pokedex_position_id UUID,
    position_number      INTEGER,
    species_id           UUID,
    species_name         VARCHAR(150),
    is_satisfied         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    WITH target AS (
        -- Fronteira de autorização: primeiro passo da query, antes de
        -- qualquer tabela do Catálogo Pokémon. Mesma fronteira,
        -- byte-a-byte, do ramo REFERENCE_POSITION de 5102. Nenhuma
        -- subquery posterior revalida owner. INALTERADA em v2.0.
        SELECT
            c.id                 AS collection_id,
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

    -- Positions do Scope corrente (LDM-177), acrescidas dos campos de
    -- exibição exigidos pelo contrato (position_number, species_id,
    -- species_name). UNION ALL de dois ramos mutuamente exclusivos por
    -- construção (scope_kind é valor único por Reference).
    -- INALTERADA em v2.0.
    --
    -- Nota v2.0: com `satisfied` deixando de referenciar este CTE,
    -- `scope` passa a ser referenciado uma única vez (apenas no SELECT
    -- final) e torna-se elegível a inlining pelo PostgreSQL.
    scope AS (
        SELECT
            t.collection_id,
            pp.id               AS pokedex_position_id,
            pp.position_number  AS position_number,
            pp.species_id       AS species_id,
            sp.canonical_name   AS species_name
        FROM target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        WHERE t.scope_kind = 'FULL_REFERENCE'

        UNION ALL

        SELECT
            t.collection_id,
            pp.id               AS pokedex_position_id,
            pp.position_number  AS position_number,
            pp.species_id       AS species_id,
            sp.canonical_name   AS species_name
        FROM target t
        JOIN public.pokedex_position pp
            ON pp.pokedex_id = t.pokedex_id
        JOIN public.pokemon_species sp
            ON sp.id = pp.species_id
        JOIN public.collection_pokedex_scope_generation spg
            ON spg.collection_reference_id = t.reference_id
           AND spg.generation_id = sp.generation_id
        WHERE t.scope_kind = 'GENERATION_FILTERED'
    ),

    -- ============================================================
    -- ALTERADA em v2.0 (ALTERNATIVA B) — Positions satisfeitas da
    -- Collection, calculadas SEM referência ao Scope (LDM-179/180/181).
    --
    -- Antes (5101 v1.0): target JOIN scope JOIN collection_allocation
    -- JOIN assignment, com scope e allocation como irmãos sem predicado
    -- entre si — custo medido Theta(|Scope| x |Allocations|).
    --
    -- Agora: target -> collection_allocation (por collection_id, via
    -- ix_collection_allocation_collection) -> assignment (por
    -- collection_allocation_id, via a PK única da tabela — 1 sonda, no
    -- máximo 1 Assignment por Allocation). Theta(|Allocations|).
    --
    -- A interseção com o Scope acontece UMA ÚNICA VEZ, no LEFT JOIN do
    -- SELECT final — que já era a forma da v1.0. É esse LEFT JOIN, e
    -- não esta CTE, que torna invisível qualquer Assignment fora do
    -- Scope corrente: ele permanece fisicamente preservado na tabela,
    -- entra neste conjunto, e simplesmente nunca casa com nenhuma linha
    -- de `scope`.
    --
    -- Nenhum filtro em assignment_basis: SPECIES_MATCH e USER_OVERRIDE
    -- contam igualmente. Nunca consulta Primary Representative,
    -- card_primary_species, physical_card ou card_variant.
    --
    -- DISTINCT colapsa duplicatas: N Physical Cards distintas
    -- satisfazendo a MESMA Position produzem N Assignments com o mesmo
    -- pokedex_position_id, e uma única linha aqui — mantendo o LEFT
    -- JOIN final 1:1 e a saída sem linhas duplicadas.
    -- ============================================================
    satisfied AS (
        SELECT DISTINCT
            t.collection_id,
            a.pokedex_position_id
        FROM target t
        JOIN public.collection_allocation ca
            ON ca.collection_id = t.collection_id
        JOIN public.collection_pokedex_position_assignment a
            ON a.collection_allocation_id = ca.id
    )
    SELECT
        s.pokedex_position_id,
        s.position_number,
        s.species_id,
        s.species_name,
        (sat.pokedex_position_id IS NOT NULL) AS is_satisfied
    FROM scope s
    LEFT JOIN satisfied sat
        ON sat.collection_id        = s.collection_id
       AND sat.pokedex_position_id  = s.pokedex_position_id
    WHERE (NOT p_only_missing) OR sat.pokedex_position_id IS NULL
    ORDER BY
        s.position_number,
        s.pokedex_position_id;
$$;

REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.collection_pokedex_scope_positions(uuid, boolean) TO authenticated;
