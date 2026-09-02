/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5032 - Create Collection Structural Identity Trigger
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-31 (aplicado em 2026-09-01,
               COLLECTIONS-PHYSICAL-INCREMENT-02B-IMPLEMENTATION-01;
               estendida em 2026-09-01, aplicada em 2026-09-02, via
               Query 5044, COLLECTIONS-PHYSICAL-INCREMENT-02C-
               IMPLEMENTATION-01)

Descrição...:
Garante estruturalmente que owner_user_id e game_id são imutáveis após
a criação da Collection — Ownership Transfer não existe ainda (C-12
SUPERSEDED em 2026-08-30, sem mecanismo modelado no V1; ver C-156) e
Game é conceitualmente imutável (C-35: "definido na criação e é
imutável durante todo o ciclo de vida"). Um único trigger BEFORE UPDATE
protege os dois campos — não depende de nenhuma RPC nunca aceitar
esses campos como parâmetro de update; mesmo que uma RPC futura
cometesse esse erro, esta garantia rejeitaria a escrita de qualquer
forma.

Só BEFORE UPDATE (não INSERT — não existe OLD para comparar na
criação). SECURITY DEFINER por consistência com o padrão de funções de
validação do domínio já usado no incremento anterior (Query 5023's
trigger equivalente para Storage), embora esta função não precise ler
nenhuma tabela sob RLS além da própria linha em NEW/OLD.

CHECK não pode comparar OLD/NEW — por isso esta garantia exige um
trigger, não uma constraint declarativa (ao contrário de
chk_collection_mode/visibility/reference_locked_at, que são valores
absolutos).

CORREÇÃO DE SEGURANÇA (COLLECTIONS-PHYSICAL-INCREMENT-02B-
IMPLEMENTATION-01, Fase 6). O Supabase Advisor (get_advisors, tipo
security) apontou WARN "Public Can Execute SECURITY DEFINER Function":
esta função de trigger nunca teve EXECUTE revogado de PUBLIC/anon —
diferente de todas as RPCs do incremento (5034-5039), que sempre
tiveram REVOKE explícito, este trigger function (junto com o de 5033)
ficou exposto em /rest/v1/rpc/validate_collection_structural_identity,
chamável diretamente por anon/authenticated fora do contexto de
trigger. Corrigido com REVOKE EXECUTE explícito — o disparo via
CREATE TRIGGER não depende de EXECUTE concedido a nenhuma role.

EXTENSÃO (Query 5044, COLLECTIONS-PHYSICAL-INCREMENT-02C-
IMPLEMENTATION-01). Estende esta função (CREATE OR REPLACE, mesma
trigger já criada abaixo — nenhum CREATE TRIGGER adicional) com a
proteção de collection.started_at (Query 5043), em vez de criar uma
trigger nova e isolada — a função já é BEFORE UPDATE ... FOR EACH ROW
genérica em collection. Duas regras, semanticamente distintas de
owner_user_id/game_id (sempre imutáveis desde a criação) porque
started_at é mutável exatamente uma vez: (1) já definido, qualquer
tentativa de mudar (inclusive voltar a NULL) é rejeitada; (2) ainda
NULL, só pode ser definido se existir pelo menos uma Collection
Allocation real para a Collection e o valor proposto corresponder
exatamente a MIN(collection_allocation.created_at) — impede qualquer
timestamp inventado por RPC, só o materializador (Query 5045) escreve,
e mesmo esse escritor é reauditado aqui contra a fonte de verdade real
a cada UPDATE.

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

CREATE FUNCTION public.validate_collection_structural_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_min_allocated_at TIMESTAMPTZ;
BEGIN
    IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
        RAISE EXCEPTION 'owner_user_id é imutável';
    END IF;

    IF NEW.game_id IS DISTINCT FROM OLD.game_id THEN
        RAISE EXCEPTION 'game_id é imutável';
    END IF;

    IF OLD.started_at IS NOT NULL AND NEW.started_at IS DISTINCT FROM OLD.started_at THEN
        RAISE EXCEPTION 'started_at é imutável após definido';
    END IF;

    IF OLD.started_at IS NULL AND NEW.started_at IS NOT NULL THEN
        SELECT MIN(ca.created_at) INTO v_min_allocated_at
        FROM public.collection_allocation ca
        WHERE ca.collection_id = NEW.id;

        IF v_min_allocated_at IS NULL THEN
            RAISE EXCEPTION 'started_at não pode ser definido sem nenhuma Collection Allocation existente';
        END IF;

        IF NEW.started_at IS DISTINCT FROM v_min_allocated_at THEN
            RAISE EXCEPTION 'started_at deve corresponder exatamente à primeira Collection Allocation (MIN(created_at))';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_collection_validate_structural_identity
    BEFORE UPDATE ON public.collection
    FOR EACH ROW
    EXECUTE FUNCTION public.validate_collection_structural_identity();

REVOKE EXECUTE ON FUNCTION public.validate_collection_structural_identity() FROM PUBLIC, anon, authenticated;
