/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2162 - Normalize Card Set Release Order (Pokémon)
Arquivo.....: 2162_normalize_card_set_release_order.sql
Versão......: 1.0
Status......: **CONFIRMADO EXECUTADO** — ledger 20260910025112
Criado em...: 2026-09-09, em CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-CORRECTION-01
Executado em: 2026-09-10, em CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-IMPLEMENTATION-02

Executada SEM alteração alguma em relação à versão auditada no GATE A —
nenhuma linha deste arquivo mudou entre a auditoria e a execução.

Permanece em `database/proposals/` por decisão explícita: é one-shot de DADOS,
não de estrutura. Não é promovida para `database/schema/` nem para
`database/migrations/` — mesmo precedente da Query `2160`
(`expansion.release_order`, ledger `20260909231838`).

Resultado (medido): 199 Card Sets Pokémon renumerados, faixa 1..28,
17 Expansions contíguas 1..N, zero release_order >= 1000.
Criado em (original)...: 2026-09-09

Objetivo....:
Substituir os `release_order` temporários (>= 1000) atribuídos pelo bootstrap
histórico (Lote A = 71, Lote B = 82) pela numeração definitiva de todos os
199 Card Sets Pokémon: contígua `1..N` por Expansion, com 1 = mais antigo.

Regra determinística (auditada e aprovada em
CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-AUDIT-01), nesta ordem:

  1. `release_date` ASC
  2. `set_type`: ENERGY (0) -> PROMO (1) -> REGULAR/SPECIAL (2)
  3. publicação principal antes do subset/gallery associado (lista explícita
     de 10 códigos, abaixo)
  4. `code` ASC em collation "C" (binária, estável, independente de locale)
     como desempate final determinístico

Sobre a regra 2: não é arbitrada. É a convenção que os 46 Card Sets curados
manualmente já exibem — SVE(1) -> SVP(2) -> SV1(3) em 2023-03-31; MEE -> MEP
-> ME1; BASEP antes de BASE1; SMP antes de SM1; DPP antes de DP1.

Sobre as regras 3 e 4: medido que COINCIDEM nos 10 pares (em collation "C",
EX10 < EXU, BW11 < RC, SM115 < SMA, SWSH9 < SWSH9TG, ...). A regra 3 é a
normativa (editorial) e a 4 é a implementação mecânica; a validação 921
confirma que a 4 nunca viola a 3.

Escopo......:
ESTRITO ao Game POKEMON, via `expansion.game_id`. Nenhuma linha de outro Game
é lida para escrita ou tocada.
NOTA DE HONESTIDADE: medido em 2026-09-09 que LORCANA tem ZERO Card Sets —
`card_set` inteira tem 199 linhas, todas Pokémon. O escopo por `game_id` é,
hoje, trivialmente satisfeito. Ele é mantido por disciplina e porque a
invariante de não-Pokémon (Seção 6) passa a ter valor no dia em que existir
um segundo Game com Card Sets. Não apresentar essa invariante como prova
forte enquanto o conjunto for vazio.

Vehículo....:
UM ÚNICO bloco `DO`. Um bloco `DO` é um único statement e portanto sua própria
transação: qualquer `RAISE EXCEPTION` desfaz TODAS as escritas por construção.
Medido no canal MCP: `execute_sql` não preserva sessão nem transação entre
chamadas, então não se usa BEGIN/COMMIT explícito aqui.

Two-pass obrigatório:
`uq_card_set_expansion_release_order` é `UNIQUE (expansion_id, release_order)`
e NÃO é DEFERRABLE (`condeferrable = f`, medido). Um UPDATE em massa direto
para os valores finais colidiria com valores ainda ocupados. `SET CONSTRAINTS
ALL DEFERRED` não tem efeito sobre constraint não-deferrable — também medido.
A técnica two-pass com faixa temporária disjunta é a mesma já comprovada na
Query `2160` (normalização de `expansion.release_order`, ledger
`20260909231838`).

Faixa temporária: `+ 10000`. Verificada livre no pré-flight — o máximo atual
em toda a tabela é 1026, e existem 0 linhas com `release_order >= 10000`.
Origem (<= 1026) e destino (>= 10001) são conjuntos disjuntos, então o passo 1
não pode colidir consigo mesmo.

Coluna `updated_at`:
MUDA, e isso é esperado. `public.card_set` tem o trigger
`trg_card_set_set_updated_at -> set_updated_at()`. Qualquer UPDATE bump o
`updated_at`. A invariante da Seção 5 cobre TODAS as demais colunas
(`id`, `expansion_id`, `code`, `name`, `set_type`, `release_date`,
`base_set_size`, `total_set_size`, `logo_storage_path`, `created_at`) e
EXCLUI deliberadamente `release_order` (que é o alvo) e `updated_at` (que é
governança automática). Isso é declarado, não escondido.

Impacto no frontend: NENHUMA alteração de código necessária. Todos os
consumidores ordenam `release_order` DESCENDENTE (`web/lib/catalogo/queries.ts`,
linhas 433, 733, 742, 928) — semântica "maior = mais recente" preservada.
Hoje os 153 valores >= 1000 empurram os Sets do bootstrap indevidamente para o
topo; esta Query CORRIGE a exibição.

Resultado esperado:
  NOTICE  2162 OK: 199 Card Sets Pokemon renumerados. Faixa 1..28. 17 Expansions contiguas.

Como validar:
  database/proposals/2026-09-09-card-sets-finalization/921_validate_card_set_finalization.sql
===============================================================================
*/

DO $$
DECLARE
    -- Faixa temporária disjunta da faixa real (máximo atual = 1026).
    c_offset          constant integer := 10000;

    -- Regra 3 — subsets/galerias que devem vir DEPOIS da publicação principal
    -- quando empatam em release_date. Lista explícita e fechada.
    c_subsets         constant text[] := ARRAY[
        'EXU',        -- Unseen Forces Unown Collection  (depois de EX10)
        'RC',         -- Radiant Collection              (depois de BW11)
        'SMA',        -- Destinos Ocultos Cofre Brilhante(depois de SM115)
        'SWSH4.5SV',  -- Destinos Brilhantes Cofre Brilh.(depois de SWSH4.5)
        'CEL25CC',    -- Celebrações Coleção Clássica    (depois de CEL25)
        'SWSH9TG',    -- Galeria de Treinador            (depois de SWSH9)
        'SWSH10TG',   -- Galeria de Treinador            (depois de SWSH10)
        'SWSH11TG',   -- Galeria de Treinador            (depois de SWSH11)
        'SWSH12TG',   -- Galeria de Treinador            (depois de SWSH12)
        'SWSH12.5GG'  -- Galeria de Galar                (depois de SWSH12.5)
    ];

    c_total_esperado  constant integer := 199;
    c_exp_esperadas   constant integer := 17;

    v_game_id             uuid;
    v_total               integer;
    v_expansions          integer;
    v_afetadas            integer;
    v_ocupa_faixa_temp    integer;
    v_md5_antes           text;
    v_md5_depois          text;
    v_md5_outros_antes    text;
    v_md5_outros_depois   text;
    v_exp_nao_contiguas   integer;
    v_duplicados          integer;
    v_residuo_1000        integer;
    v_fora_da_regra       integer;
    v_faixa_max           integer;
BEGIN
    ---------------------------------------------------------------------------
    -- SEÇÃO 1 — PRÉ-FLIGHT
    ---------------------------------------------------------------------------
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN
        RAISE EXCEPTION '2162_PREFLIGHT_GAME_AUSENTE: Game POKEMON não encontrado.';
    END IF;

    SELECT count(*), count(DISTINCT c.expansion_id)
      INTO v_total, v_expansions
    FROM public.card_set c
    JOIN public.expansion e ON e.id = c.expansion_id
    WHERE e.game_id = v_game_id;

    IF v_total <> c_total_esperado THEN
        RAISE EXCEPTION
            '2162_PREFLIGHT_TOTAL: esperados % Card Sets Pokemon, encontrados %. O universo mudou — reauditar antes de renumerar.',
            c_total_esperado, v_total;
    END IF;

    IF v_expansions <> c_exp_esperadas THEN
        RAISE EXCEPTION
            '2162_PREFLIGHT_EXPANSIONS: esperadas % Expansions com Card Set, encontradas %.',
            c_exp_esperadas, v_expansions;
    END IF;

    -- Faixa temporária precisa estar livre em TODA a tabela, não só no escopo.
    SELECT count(*) INTO v_ocupa_faixa_temp
    FROM public.card_set
    WHERE release_order >= c_offset;

    IF v_ocupa_faixa_temp > 0 THEN
        RAISE EXCEPTION
            '2162_PREFLIGHT_FAIXA_TEMP_OCUPADA: % linha(s) já usam release_order >= %. Escolher outro offset.',
            v_ocupa_faixa_temp, c_offset;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 2 — SNAPSHOT DE INVARIÂNCIA (ANTES)
    -- Todas as colunas exceto release_order (alvo) e updated_at (trigger).
    ---------------------------------------------------------------------------
    SELECT md5(coalesce(string_agg(linha, '|' ORDER BY linha), ''))
      INTO v_md5_antes
    FROM (
        SELECT c.id::text || '~' || c.expansion_id::text || '~' || c.code || '~' || c.name
               || '~' || c.set_type || '~' || c.release_date::text
               || '~' || c.base_set_size::text || '~' || c.total_set_size::text
               || '~' || coalesce(c.logo_storage_path, '<null>')
               || '~' || c.created_at::text AS linha
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
    ) s;

    -- Linhas de outros Games: invariante INCLUI release_order (nada pode mudar).
    -- Hoje esse conjunto é VAZIO (LORCANA tem 0 Card Sets) — ver nota do cabeçalho.
    SELECT md5(coalesce(string_agg(linha, '|' ORDER BY linha), ''))
      INTO v_md5_outros_antes
    FROM (
        SELECT c.id::text || '~' || c.release_order::text || '~' || c.code AS linha
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id <> v_game_id
    ) s;

    ---------------------------------------------------------------------------
    -- SEÇÃO 3 — PASSO 1: deslocar para a faixa temporária disjunta.
    ---------------------------------------------------------------------------
    UPDATE public.card_set c
       SET release_order = c.release_order + c_offset
      FROM public.expansion e
     WHERE e.id = c.expansion_id
       AND e.game_id = v_game_id;

    GET DIAGNOSTICS v_afetadas = ROW_COUNT;
    IF v_afetadas <> c_total_esperado THEN
        RAISE EXCEPTION
            '2162_PASSO1_ROWCOUNT: esperadas % linhas deslocadas, obtidas %.',
            c_total_esperado, v_afetadas;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 4 — PASSO 2: gravar o valor definitivo.
    -- A ordenação depende só de release_date/set_type/code — colunas intocadas
    -- pelo passo 1 —, então o alvo é o mesmo antes e depois do deslocamento.
    ---------------------------------------------------------------------------
    WITH alvo AS (
        SELECT c.id,
               row_number() OVER (
                   PARTITION BY c.expansion_id
                   ORDER BY c.release_date,
                            CASE c.set_type
                                WHEN 'ENERGY' THEN 0
                                WHEN 'PROMO'  THEN 1
                                ELSE 2
                            END,
                            (c.code = ANY (c_subsets)),
                            c.code COLLATE "C"
               ) AS ro_novo
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
    )
    UPDATE public.card_set c
       SET release_order = a.ro_novo
      FROM alvo a
     WHERE a.id = c.id;

    GET DIAGNOSTICS v_afetadas = ROW_COUNT;
    IF v_afetadas <> c_total_esperado THEN
        RAISE EXCEPTION
            '2162_PASSO2_ROWCOUNT: esperadas % linhas renumeradas, obtidas %.',
            c_total_esperado, v_afetadas;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 5 — INVARIÂNCIA: nenhuma outra coluna mudou.
    ---------------------------------------------------------------------------
    SELECT md5(coalesce(string_agg(linha, '|' ORDER BY linha), ''))
      INTO v_md5_depois
    FROM (
        SELECT c.id::text || '~' || c.expansion_id::text || '~' || c.code || '~' || c.name
               || '~' || c.set_type || '~' || c.release_date::text
               || '~' || c.base_set_size::text || '~' || c.total_set_size::text
               || '~' || coalesce(c.logo_storage_path, '<null>')
               || '~' || c.created_at::text AS linha
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
    ) s;

    IF v_md5_depois IS DISTINCT FROM v_md5_antes THEN
        RAISE EXCEPTION
            '2162_INVARIANTE_COLUNAS: alguma coluna além de release_order/updated_at mudou. md5 antes=% depois=%.',
            v_md5_antes, v_md5_depois;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 6 — INVARIÂNCIA: outros Games intocados.
    -- Conjunto hoje VAZIO — invariante mantida por disciplina, sem valor
    -- probatório enquanto LORCANA não tiver Card Sets.
    ---------------------------------------------------------------------------
    SELECT md5(coalesce(string_agg(linha, '|' ORDER BY linha), ''))
      INTO v_md5_outros_depois
    FROM (
        SELECT c.id::text || '~' || c.release_order::text || '~' || c.code AS linha
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id <> v_game_id
    ) s;

    IF v_md5_outros_depois IS DISTINCT FROM v_md5_outros_antes THEN
        RAISE EXCEPTION
            '2162_INVARIANTE_OUTROS_GAMES: Card Sets de outro Game foram alterados.';
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 7 — CONTIGUIDADE 1..N POR EXPANSION.
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_exp_nao_contiguas
    FROM (
        SELECT c.expansion_id
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
        GROUP BY c.expansion_id
        HAVING min(c.release_order) <> 1
            OR max(c.release_order) <> count(*)
            OR count(DISTINCT c.release_order) <> count(*)
    ) g;

    IF v_exp_nao_contiguas > 0 THEN
        RAISE EXCEPTION
            '2162_CONTIGUIDADE: % Expansion(s) sem sequência 1..N contígua.',
            v_exp_nao_contiguas;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 8 — UNICIDADE (expansion_id, release_order).
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_duplicados
    FROM (
        SELECT c.expansion_id, c.release_order
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
        GROUP BY c.expansion_id, c.release_order
        HAVING count(*) > 1
    ) d;

    IF v_duplicados > 0 THEN
        RAISE EXCEPTION '2162_UNICIDADE: % par(es) (expansion_id, release_order) duplicado(s).', v_duplicados;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 9 — ZERO RESÍDUO TEMPORÁRIO.
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_residuo_1000
    FROM public.card_set c
    JOIN public.expansion e ON e.id = c.expansion_id
    WHERE e.game_id = v_game_id
      AND c.release_order >= 1000;

    IF v_residuo_1000 > 0 THEN
        RAISE EXCEPTION '2162_RESIDUO_TEMPORARIO: % linha(s) ainda com release_order >= 1000.', v_residuo_1000;
    END IF;

    ---------------------------------------------------------------------------
    -- SEÇÃO 10 — A REGRA FOI DE FATO APLICADA.
    -- Recalcula a ordenação e exige igualdade linha a linha com o gravado.
    ---------------------------------------------------------------------------
    SELECT count(*) INTO v_fora_da_regra
    FROM (
        SELECT c.id, c.release_order,
               row_number() OVER (
                   PARTITION BY c.expansion_id
                   ORDER BY c.release_date,
                            CASE c.set_type
                                WHEN 'ENERGY' THEN 0
                                WHEN 'PROMO'  THEN 1
                                ELSE 2
                            END,
                            (c.code = ANY (c_subsets)),
                            c.code COLLATE "C"
               ) AS esperado
        FROM public.card_set c
        JOIN public.expansion e ON e.id = c.expansion_id
        WHERE e.game_id = v_game_id
    ) r
    WHERE r.release_order <> r.esperado;

    IF v_fora_da_regra > 0 THEN
        RAISE EXCEPTION '2162_REGRA: % linha(s) divergem da regra determinística.', v_fora_da_regra;
    END IF;

    SELECT max(c.release_order) INTO v_faixa_max
    FROM public.card_set c
    JOIN public.expansion e ON e.id = c.expansion_id
    WHERE e.game_id = v_game_id;

    RAISE NOTICE
        '2162 OK: % Card Sets Pokemon renumerados. Faixa 1..%. % Expansions contiguas.',
        c_total_esperado, v_faixa_max, c_exp_esperadas;
END
$$;
