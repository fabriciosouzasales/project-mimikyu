/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5094 - Create check_collection_pokedex_scope_presence() Helper
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, renumerada em REVISION-01; aplicado em
               2026-09-05 via COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Helper compartilhado por Queries 5096 e 5097 (mesmo papel que
check_master_set_scope_presence(), 5075, tem para o par 5076/5077) —
único lugar que sabe "o que significa" um scope de Pokédex estar
consistente com sua contagem de Generations filtradas.

Sempre reconsulta o estado CORRENTE de collection_pokedex_reference no
momento em que é chamado — nunca decide a partir de NEW/OLD do evento
que o disparou (que serve só como correlation key), mesma disciplina
de 5075: torna o enforcement correto mesmo quando a mesma Reference
muda scope_kind mais de uma vez na mesma transação, ou quando o
conjunto de Generations passa por um instante vazio dentro de uma
transação que termina não-vazio (troca completa de filtro via Query
5099, DELETE total + INSERT total).

Invariante verificada:
- scope_kind = 'GENERATION_FILTERED' -> >= 1 linha em
  collection_pokedex_scope_generation para esta Reference.
- scope_kind = 'FULL_REFERENCE' -> exatamente 0 linhas.

Se a própria collection_pokedex_reference já não existe (DELETE CASCADE
da Collection, ou removida na mesma transação), nada a checar — mesmo
padrão "a linha pai ainda existe?" de 5057/5075.

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou a função presente, EXECUTE revogado de PUBLIC/anon/
authenticated. Validado funcionalmente via as duas RPCs que a invocam
(5098/5099), dentro de BEGIN/ROLLBACK. Zero resíduo.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

CREATE FUNCTION public.check_collection_pokedex_scope_presence(p_collection_reference_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_scope_kind        TEXT;
    v_generation_count  INT;
BEGIN
    SELECT cpr.scope_kind INTO v_scope_kind
    FROM public.collection_pokedex_reference cpr
    WHERE cpr.collection_reference_id = p_collection_reference_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT count(*) INTO v_generation_count
    FROM public.collection_pokedex_scope_generation cpsg
    WHERE cpsg.collection_reference_id = p_collection_reference_id;

    IF v_scope_kind = 'GENERATION_FILTERED' AND v_generation_count = 0 THEN
        RAISE EXCEPTION 'Collection Pokedex Reference with scope_kind = GENERATION_FILTERED must have at least one selected Generation';
    END IF;

    IF v_scope_kind = 'FULL_REFERENCE' AND v_generation_count > 0 THEN
        RAISE EXCEPTION 'Collection Pokedex Reference with scope_kind = FULL_REFERENCE cannot have any Generation filter row (found %)', v_generation_count;
    END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_collection_pokedex_scope_presence(uuid)
    FROM PUBLIC, anon, authenticated;

COMMIT;
