/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6115 - Create resolve_card_primary_species_bulk() Function
Versão......: 1.2
Status......: PROPOSTA — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em
               COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-REVISION-01;
               revisado em ...-REVISION-02; revisado em
               ...-GATE-4-FIX-01)

Correção v1.1 (REVISION-02) — dois ajustes obrigatórios antes do
Gate 4, REVISION-01 mantida conceitualmente aprovada:

1. SOURCE DRIFT / CONFLICT. A v1.0 permitia que esta função
   sobrescrevesse uma resolução AUTOMATIC_DEXID existente quando a
   evidência reprocessada apontava para uma Species DIFERENTE
   (tratado como "reprocessamento legítimo"). Fabrício determinou que
   isso é exatamente o cenário que não pode acontecer silenciosamente:
   se a TCGdex mudar o dado a montante, esta função NUNCA pode trocar
   a Species canônica sozinha — mesmo quando a resolução anterior
   também era automática. Esse branch agora NUNCA escreve; classifica
   como CONFLICT (contador e detail próprios) e preserva a linha
   existente intacta. Só admin_resolve_card_primary_species() (Query
   6114) pode alterar uma Species já resolvida quando há conflito —
   reforça a garantia central desta Fatia ("MMKYU mantém a decisão
   canônica final") também para o caso automático-vs-automático, não
   só editorial-vs-automático. Consequência aceita e citada
   explicitamente pelo mandato: com este fechamento, bulk automático
   comprovadamente NUNCA substitui uma Species existente por outra —
   a rastreabilidade atual (linha própria, sem catalog_admin_action_log
   para o caminho automático) permanece suficiente por construção, não
   por lacuna.
2. BULK GUARD. p_evidence_batch agora tem um limite máximo explícito
   de itens, verificado ANTES de qualquer processamento — a chamada
   inteira é rejeitada (RAISE EXCEPTION) se excedido, nunca um
   truncamento silencioso. Valor: 10000, idêntico e alinhado ao guard
   operacional já em produção no mesmo domínio de Collections
   (`c_max_variant_ids`, Query 5079/5813, aplicado a
   apply_master_set_scope_diff()) — mesmo racional: proteção de
   tamanho de payload/tempo de transação, não uma decisão de domínio;
   maior lote real observado nesta Fatia é 6435 Cards Pokémon ativas
   (auditoria da rodada AUDIT-01), abaixo do limite com folga.

Correção v1.2 (GATE-4-FIX-01) — fecha o único blocker apontado pela
auditoria GATE-4: details não diferenciava SAME_SPECIES nem
EDITORIAL_PROTECTED, ambos colapsados dentro de unchanged_count sem
nenhum sinal individual — diferente de CONFLICT, que já carregava
existing_species_id/candidate_species_id. Os dois branches do algoritmo
de gravação que já pertenciam ao bucket UNCHANGED (nenhum passou a
escrever; nenhum contador mudou de nome ou semântica) ganharam entrada
própria em details:
- SAME_SPECIES: evidência nova concorda com a Species já registrada
  (qualquer basis) — caso verdadeiramente inerte, sem divergência.
- EDITORIAL_PROTECTED: evidência automática nova DIVERGE de uma
  resolução EDITORIAL_RECONCILIATION vigente, mas é suprimida por
  design (MMKYU mantém a decisão canônica final) — inclui
  existing_species_id/candidate_species_id, mesmo formato de CONFLICT,
  para permitir ao chamador decidir se escala a Card para reconciliação
  via admin_resolve_card_primary_species() (Query 6114).
Mudança estritamente aditiva em details — nenhuma regra de resolução,
o guard de 10000, o invariante "bulk nunca faz UPDATE", ou qualquer
outra Query desta Fatia (2159/6112/6113/6114) foram tocados.

Descrição...:
Único caminho de escrita em lote (automática) para card_primary_
species (Query 6112) — serve tanto BACKFILL do catálogo já existente
quanto resolução INCREMENTAL ao final da importação de um novo Set
(mandato desta rodada, itens A/B). SERVICE_ROLE ONLY, mesmo padrão
exato de public.open_pokemon_catalog_sourcing_run() (Query 6103):
SECURITY DEFINER, sem is_admin() (a própria posse da service_role key
já é o controle de acesso — não há sessão de usuário autenticado num
caller service_role, auth.uid() seria NULL), REVOKE de PUBLIC/anon/
authenticated, GRANT EXECUTE só a service_role.

Diferente do pipeline de Pokémon Catalog Sourcing (6100-6111), esta
função é síncrona e sem estado — não precisa de uma tabela de "run"
própria: cada chamada é auto-contida, recebe toda a evidência já
buscada pelo chamador (nenhuma chamada HTTP externa acontece aqui) e
retorna contadores + detalhe no mesmo round-trip. Não escreve em
catalog_admin_action_log (ver racional no cabeçalho de 6112 v1.1) —
a rastreabilidade de cada decisão automática vive na própria linha
resultante (source_evidence + resolved_at).

CONTRATO DE ENTRADA — p_evidence_batch (JSONB, array de objetos):
[
  {
    "card_id": "<uuid>",
    "tcgdex_dex_ids": [<int>, ...],       -- bruto, como observado
                                            -- na TCGdex (pode ser
                                            -- vazio, [] ou ausente)
    "catalog_import_row_id": "<uuid>"|null -- opcional, best-effort
  },
  ...
]
Nenhum outro formato é aceito. Um item malformado (card_id ausente,
tcgdex_dex_ids não é array) conta como FAILED para aquele item —
nunca aborta o lote inteiro.

ALGORITMO DE DECISÃO POR ITEM (mandato item 2, "AUTOMATIC_DEXID"):
1. Deduplica tcgdex_dex_ids (DISTINCT) → v_distinct_dex_ids.
2. Zero elementos distintos → evidência insuficiente → UNRESOLVED.
3. Exatamente 1 elemento distinto → candidato único. Resolve contra
   pokemon_species.national_dex_number:
   - Não encontrado → UNRESOLVED (dexId não mapeia para nenhuma
     Species conhecida — problema de dado, mas continua "evidência
     insuficiente para decisão automática", nunca "falha").
   - Encontrado → prossegue para a etapa de gravação (abaixo).
4. Mais de 1 elemento distinto → AMBIGUOUS. Nunca escolhido
   arbitrariamente (mandato item 4, "não transformar ambiguidades em
   escolhas automáticas") — nenhuma linha é criada nem tocada.

ETAPA DE GRAVAÇÃO (quando exatamente 1 Species é resolvida — fechada
em REVISION-02):
- Sem linha existente para o card_id → INSERT AUTOMATIC_DEXID →
  RESOLVED.
- Linha existente com MESMO pokemon_species_id (qualquer basis) →
  idempotente, nenhuma escrita (evita touch de updated_at/resolved_at
  sem mudança real) → UNCHANGED. Sem escrita, evidência e resolved_at
  permanecem exatamente como estavam.
- Linha existente com resolution_basis = EDITORIAL_RECONCILIATION E
  pokemon_species_id DIFERENTE → NUNCA sobrescrita (mandato original
  da Fatia C, escopo item 4: "MMKYU mantém a decisão canônica final")
  → UNCHANGED.
- Linha existente com resolution_basis = AUTOMATIC_DEXID E
  pokemon_species_id DIFERENTE da nova evidência única → NUNCA
  sobrescrita (REVISION-02: fechamento do gap "source drift" — uma
  mudança de dado na TCGdex nunca troca a Species canônica sozinha,
  mesmo quando a resolução anterior também era automática) → CONFLICT,
  com detail explícito (species antiga e nova). Só admin_resolve_
  card_primary_species() (Query 6114) pode resolver este conflito.

INVARIANTE EXPLÍCITO — NENHUMA ESCRITA AUTOMÁTICA JAMAIS TROCA UMA
SPECIES JÁ RESOLVIDA POR OUTRA (REVISION-02): esta função só faz
INSERT (linha nova) ou não escreve nada. Nunca faz UPDATE de
pokemon_species_id. Isso vale tanto para degradação de evidência (0 ou
>1 dexIds distintos numa Card já resolvida — outcome UNRESOLVED/
AMBIGUOUS, linha intacta) quanto para uma evidência única, porém
divergente, contra uma resolução AUTOMATIC_DEXID existente (outcome
CONFLICT, linha intacta). Consequência direta: bulk automático
comprovadamente nunca substitui uma Species existente por outra —
por isso a rastreabilidade atual (linha própria, sem
catalog_admin_action_log para o caminho automático) é suficiente,
não uma lacuna.

Isolamento por item: cada item roda dentro de seu próprio bloco
EXCEPTION — um erro específico (ex.: card_id inexistente, categoria
diferente de POKEMON, tipo inválido em tcgdex_dex_ids) nunca aborta os
demais itens do lote, mesmo padrão de admin_confirm_catalog_import()
(Query 2082). Contado como FAILED, com o detalhe da mensagem de erro.

IDEMPOTÊNCIA E REPROCESSAMENTO (mandato item 4, fechado em
REVISION-02): reexecutar a mesma chamada (mesmo p_evidence_batch)
produz sempre o mesmo estado final sem erro e sem duplicar trabalho —
esta função NUNCA executa UPDATE (REVISION-02 removeu o único branch
que fazia); o único efeito colateral possível é um INSERT condicionado
a "linha ainda não existe". Reexecutar contra uma Card já resolvida
(mesma Species ou não) é sempre um no-op em termos de escrita —
RESOLVED só ocorre uma vez, na primeira vez que aquela Card recebe
evidência resolvível; toda chamada seguinte com a mesma evidência
resulta em UNCHANGED, e uma chamada com evidência DIFERENTE resulta em
CONFLICT (nunca numa segunda escrita). Backfill pode rodar em blocos
(chunks) de até c_max_batch_size itens, em qualquer ordem, quantas
vezes for necessário, sem efeito colateral cumulativo.

CONTRATO DE RETORNO (REVISION-02 adiciona conflict_count; GATE-4-FIX-01
amplia a granularidade de details dentro do bucket UNCHANGED):
- resolved_count, unchanged_count, unresolved_count, ambiguous_count,
  conflict_count, failed_count: contadores agregados desta chamada.
- details (JSONB, array): omite apenas RESOLVED (INSERT bem-sucedido,
  sem nenhuma ambiguidade a reportar) — todo outro outcome, incluindo
  os dois sub-casos de UNCHANGED, tem entrada própria —
  {"card_id", "outcome", "reason"}, com CONFLICT e o sub-caso
  EDITORIAL_PROTECTED de UNCHANGED incluindo também
  "existing_species_id" e "candidate_species_id" para dar ao chamador
  o suficiente para decidir se vale escalar a Card para reconciliação
  editorial (Query 6114). Reasons reconhecidos: NO_DEX_ID_EVIDENCE/
  DEX_ID_NOT_FOUND_IN_SPECIES_CATALOG (UNRESOLVED),
  MULTIPLE_DISTINCT_DEX_IDS (AMBIGUOUS), SAME_SPECIES/
  EDITORIAL_PROTECTED (UNCHANGED), AUTOMATIC_SOURCE_DRIFT (CONFLICT),
  mensagem livre de SQLERRM (FAILED). Não existe fila de reconciliação
  dedicada: a consulta natural para "Cards Pokémon pendentes de Primary
  Species" já é derivável por ausência de linha em card_primary_species
  (LEFT JOIN/NOT EXISTS contra card WHERE category = POKEMON); uma fila
  de "Cards em CONFLICT" ou "Cards em EDITORIAL_PROTECTED" é derivável
  de forma equivalente por uma leitura pontual do retorno desta função
  pelo chamador — sem necessidade de tabela nova — ver README.

BULK GUARD (REVISION-02): p_evidence_batch não pode exceder
c_max_batch_size = 10000 itens — verificado por jsonb_array_length()
ANTES de qualquer processamento. Acima do limite, a chamada inteira é
rejeitada com RAISE EXCEPTION (ERRCODE invalid_parameter_value) — o
chamador deve dividir em lotes menores, nunca depender de truncamento
implícito. Mesmo valor e mesmo racional do guard operacional já em
produção no domínio (`c_max_variant_ids`, Query 5079).

INTEGRAÇÃO FUTURA COM IMPORT-CARD (mandato item 5 — NÃO implementada
nesta rodada): o Edge Function import-catalog-cards deve chamar esta
função como ÚLTIMA etapa, DEPOIS que Set Mapping/Card Import/Images já
tiverem sido confirmados (fora da mesma transação de admin_confirm_
catalog_import()), envolvida em seu próprio try/catch — qualquer falha
ou exceção aqui NUNCA deve propagar para o resultado da importação da
Card/Set. p_evidence_batch pode ser montado diretamente da resposta
TCGdex já obtida em memória pelo próprio Edge Function (TcgdexCardDetail.
dexId), pareada com o resulting_card_id devolvido por admin_confirm_
catalog_import() — não depende de catalog_import_row sobreviver.

COMPORTAMENTO DE BACKFILL (mandato item 1 — NÃO executado nesta
rodada): um script/Edge Function futuro lê card_id + raw_data->>'dexId'
de catalog_import_row para as 5675 Cards com evidência sobrevivente
hoje, monta p_evidence_batch no mesmo formato e chama esta função (em
um ou mais lotes). As 760 Cards sem nenhuma evidência sobrevivente
(ver README, "Riscos") permanecem UNRESOLVED — candidatas a
reconciliação 100% editorial via Query 6114, não a este caminho.

Pré-requisitos:
- Query 6112/6113 - Create Card Primary Species Table/Triggers.
- Query 6010 - Create Pokemon Species Table (national_dex_number).
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.resolve_card_primary_species_bulk(
    p_evidence_batch JSONB
)
RETURNS TABLE (
    resolved_count INTEGER,
    unchanged_count INTEGER,
    unresolved_count INTEGER,
    ambiguous_count INTEGER,
    conflict_count INTEGER,
    failed_count INTEGER,
    details JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Guard operacional de payload, NÃO arquitetural — mesmo racional e
    -- mesmo valor de c_max_variant_ids (Query 5079/5813). Maior lote real
    -- observado nesta Fatia: 6435 Cards Pokémon ativas.
    c_max_batch_size CONSTANT INTEGER := 10000;

    v_item RECORD;
    v_distinct_dex_ids INTEGER[];
    v_species_id UUID;
    v_existing public.card_primary_species%ROWTYPE;
    v_existing_found BOOLEAN;
    v_category_code TEXT;
    v_evidence JSONB;
    v_batch_size INTEGER;
    v_resolved_count INTEGER := 0;
    v_unchanged_count INTEGER := 0;
    v_unresolved_count INTEGER := 0;
    v_ambiguous_count INTEGER := 0;
    v_conflict_count INTEGER := 0;
    v_failed_count INTEGER := 0;
    v_details JSONB := '[]'::JSONB;
BEGIN
    IF p_evidence_batch IS NULL OR jsonb_typeof(p_evidence_batch) <> 'array' THEN
        -- Entrada vazia/malformada: nunca aborta o chamador (mandato item 5,
        -- "falha/ausência não pode invalidar a importação") — devolve um
        -- resultado zerado em vez de RAISE.
        RETURN QUERY SELECT 0, 0, 0, 0, 0, 0, '[]'::JSONB;
        RETURN;
    END IF;

    v_batch_size := jsonb_array_length(p_evidence_batch);
    IF v_batch_size > c_max_batch_size THEN
        -- Rejeita a chamada INTEIRA antes de processar qualquer item —
        -- nunca um truncamento silencioso. Mandato REVISION-02, item 2.
        RAISE EXCEPTION 'RESOLVE_CARD_PRIMARY_SPECIES_BULK_PAYLOAD_TOO_LARGE: p_evidence_batch excede o guard operacional (% > %) — divida em lotes menores.', v_batch_size, c_max_batch_size
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    FOR v_item IN
        SELECT * FROM jsonb_to_recordset(p_evidence_batch) AS x(
            card_id UUID,
            tcgdex_dex_ids JSONB,
            catalog_import_row_id UUID
        )
    LOOP
        BEGIN
            IF v_item.card_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_CARD_ID';
            END IF;

            SELECT cc.code INTO v_category_code
            FROM public.card c
            JOIN public.card_category cc ON cc.id = c.category_id
            WHERE c.id = v_item.card_id;

            IF v_category_code IS NULL THEN
                RAISE EXCEPTION 'CARD_NOT_FOUND';
            END IF;
            IF v_category_code <> 'POKEMON' THEN
                RAISE EXCEPTION 'NOT_POKEMON_CATEGORY';
            END IF;

            IF v_item.tcgdex_dex_ids IS NULL OR jsonb_typeof(v_item.tcgdex_dex_ids) <> 'array' THEN
                v_distinct_dex_ids := ARRAY[]::INTEGER[];
            ELSE
                SELECT COALESCE(array_agg(DISTINCT elem::INTEGER), ARRAY[]::INTEGER[])
                INTO v_distinct_dex_ids
                FROM jsonb_array_elements_text(v_item.tcgdex_dex_ids) AS elem;
            END IF;

            SELECT * INTO v_existing
            FROM public.card_primary_species
            WHERE card_id = v_item.card_id
            FOR UPDATE;
            v_existing_found := FOUND;

            IF array_length(v_distinct_dex_ids, 1) IS NULL THEN
                -- Zero evidência (array vazio ou ausente).
                v_unresolved_count := v_unresolved_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object('card_id', v_item.card_id, 'outcome', 'UNRESOLVED', 'reason', 'NO_DEX_ID_EVIDENCE')
                );
                CONTINUE;
            END IF;

            IF array_length(v_distinct_dex_ids, 1) > 1 THEN
                -- Mais de um dexId distinto: nunca escolhido automaticamente.
                v_ambiguous_count := v_ambiguous_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object('card_id', v_item.card_id, 'outcome', 'AMBIGUOUS', 'reason', 'MULTIPLE_DISTINCT_DEX_IDS')
                );
                CONTINUE;
            END IF;

            -- Exatamente 1 dexId distinto a partir daqui.
            SELECT id INTO v_species_id
            FROM public.pokemon_species
            WHERE national_dex_number = v_distinct_dex_ids[1];

            IF v_species_id IS NULL THEN
                v_unresolved_count := v_unresolved_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object('card_id', v_item.card_id, 'outcome', 'UNRESOLVED', 'reason', 'DEX_ID_NOT_FOUND_IN_SPECIES_CATALOG')
                );
                CONTINUE;
            END IF;

            v_evidence := jsonb_build_object(
                'source', 'TCGDEX',
                'tcgdex_dex_ids', v_item.tcgdex_dex_ids,
                'resolved_dex_id', v_distinct_dex_ids[1],
                'catalog_import_row_id', v_item.catalog_import_row_id,
                'observed_at', NOW()
            );

            IF NOT v_existing_found THEN
                -- Nenhuma linha existente: primeira resolução automática.
                INSERT INTO public.card_primary_species (
                    card_id, pokemon_species_id, resolution_basis, source_evidence, resolved_at
                ) VALUES (
                    v_item.card_id, v_species_id, 'AUTOMATIC_DEXID', v_evidence, NOW()
                );
                v_resolved_count := v_resolved_count + 1;

            ELSIF v_existing.pokemon_species_id = v_species_id THEN
                -- Idempotente: mesma Species já registrada (qualquer basis) —
                -- nenhuma escrita, evidência/resolved_at permanecem intactos.
                -- GATE-4-FIX-01: entrada própria em details (antes ausente),
                -- para diferenciar de EDITORIAL_PROTECTED abaixo — os dois
                -- só incrementavam unchanged_count, sem nenhum sinal distinto.
                v_unchanged_count := v_unchanged_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object(
                        'card_id', v_item.card_id,
                        'outcome', 'UNCHANGED',
                        'reason', 'SAME_SPECIES'
                    )
                );

            ELSIF v_existing.resolution_basis = 'EDITORIAL_RECONCILIATION' THEN
                -- Decisão humana nunca é sobrescrita por resolução automática.
                -- GATE-4-FIX-01: entrada própria em details (antes ausente) —
                -- a evidência automática nova DIVERGE da decisão editorial
                -- vigente, mas é suprimida por design; sem este detalhe o
                -- chamador não tinha como distinguir este caso do idempotente
                -- SAME_SPECIES acima, nem sinalizar a divergência para
                -- eventual reconciliação via admin_resolve_card_primary_
                -- species() (Query 6114).
                v_unchanged_count := v_unchanged_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object(
                        'card_id', v_item.card_id,
                        'outcome', 'UNCHANGED',
                        'reason', 'EDITORIAL_PROTECTED',
                        'existing_species_id', v_existing.pokemon_species_id,
                        'candidate_species_id', v_species_id
                    )
                );

            ELSE
                -- REVISION-02: AUTOMATIC_DEXID pré-existente, evidência única
                -- porém DIFERENTE (source drift) — NUNCA sobrescrita
                -- automaticamente. Classificado como CONFLICT; só
                -- admin_resolve_card_primary_species() (Query 6114) pode
                -- alterar a Species canônica já resolvida a partir daqui.
                v_conflict_count := v_conflict_count + 1;
                v_details := v_details || jsonb_build_array(
                    jsonb_build_object(
                        'card_id', v_item.card_id,
                        'outcome', 'CONFLICT',
                        'reason', 'AUTOMATIC_SOURCE_DRIFT',
                        'existing_species_id', v_existing.pokemon_species_id,
                        'candidate_species_id', v_species_id
                    )
                );
            END IF;

        EXCEPTION WHEN OTHERS THEN
            v_failed_count := v_failed_count + 1;
            v_details := v_details || jsonb_build_array(
                jsonb_build_object('card_id', v_item.card_id, 'outcome', 'FAILED', 'reason', SQLERRM)
            );
        END;
    END LOOP;

    RETURN QUERY SELECT
        v_resolved_count, v_unchanged_count, v_unresolved_count,
        v_ambiguous_count, v_conflict_count, v_failed_count, v_details;
END;
$$;

COMMENT ON FUNCTION public.resolve_card_primary_species_bulk(JSONB) IS
    'Resolução automática em lote de Card Primary Species (backfill + importação incremental). Guard de payload em 10000 itens (rejeita a chamada inteira acima disso). Deduplica dexIds, nunca escolhe ambíguo, nunca sobrescreve decisão editorial nem outra resolução automática divergente (CONFLICT), idempotente/reprocessável. SERVICE_ROLE ONLY. Não escreve em catalog_admin_action_log.';

REVOKE ALL ON FUNCTION public.resolve_card_primary_species_bulk(JSONB)
    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.resolve_card_primary_species_bulk(JSONB)
    TO service_role;

COMMIT;
