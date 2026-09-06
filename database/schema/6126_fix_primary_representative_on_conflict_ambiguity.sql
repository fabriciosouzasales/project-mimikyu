/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6126 - Fix set_pokedex_position_primary_representative()
               ON CONFLICT Ambiguity (correção incremental, sem
               reescrever migration já executada)
Versão......: 1.0 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em resposta a
               COLLECTIONS-POKEDEX-FATIA-D-6126-STAGING-01, motivada por
               bug funcional real encontrado durante a execução da Seção 3
               de 6830 v1.5 — Caso 14; executada no banco real em
               IMPLEMENTATION-RESUME-02, postcheck confirmou zero
               divergência de assinatura/RETURNS TABLE/SECURITY DEFINER/
               search_path/ownership/ACL; Casos 14 e 15 revalidados PASS
               pós-fix (INSERT e UPDATE do UPSERT); promovida para
               database/schema/ em COLLECTIONS-POKEDEX-FATIA-D-
               PROMOTION-CLOSEOUT-01 — corpo SQL byte-idêntico ao
               executado, apenas cabeçalho Status/Versão/Data
               atualizados. Correção incremental sobre 6125 — NÃO
               foldada; 6125 permanece o arquivo original com o bug)

ATENÇÃO — BUG FUNCIONAL CONFIRMADO EM EXECUÇÃO REAL (não estrutural):
ao chamar set_pokedex_position_primary_representative(uuid) pela primeira
vez nesta sessão (Caso 14 de 6830 Seção 3), a função falhou com:

    ERROR: 42702: column reference "collection_id" is ambiguous
    CONTEXT: PL/pgSQL function
      public.set_pokedex_position_primary_representative(uuid)
      line 61 at RETURN QUERY

Causa raiz confirmada: a função já está com "SHOW plpgsql.variable_conflict"
= 'error' (confirmado nesta sessão, consistente com o resto do projeto).
A cláusula

    ON CONFLICT (collection_id, pokedex_position_id)

usa os nomes das colunas do PK sem qualificação — sob variable_conflict =
'error', esses nomes colidem com os OUT-parameters de mesmo nome do
RETURNS TABLE da própria função (collection_id, pokedex_position_id,
collection_allocation_id), levantando ambiguidade em tempo de execução.
É exatamente a mesma classe de bug que a correção 6123 (PAUSE-SQL-DIRECT-
AUDIT-01) já havia corrigido na cláusula RETURNING desta mesma família de
funções (6122) — mas a lista de conflito do ON CONFLICT desta função
específica (6125) ficou fora daquela rodada e não tinha sido exercitada
por nenhum teste estrutural anterior (só aparece ao chamar a função de
verdade, com uma linha pré-existente para colidir no UPSERT).

PK confirmada nesta sessão (pg_get_constraintdef):
    pk_collection_pokedex_position_primary_representative
    PRIMARY KEY (collection_id, pokedex_position_id)

Descrição...:
Migration incremental (CREATE OR REPLACE FUNCTION) para o objeto já
aplicado ao banco real (6125) que corrige exclusivamente a ambiguidade
acima. O arquivo 6125 permanece inalterado como registro exato do que foi
de fato executado; esta migration é quem corrige o comportamento ao vivo,
via CREATE OR REPLACE FUNCTION (mesma assinatura, sem DROP).

ÚNICA mudança funcional: troca de

    ON CONFLICT (collection_id, pokedex_position_id)

por

    ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative

Nenhum outro statement, comportamento, contrato ou otimização foi
alterado. Especificamente preservados sem qualquer mudança:
- assinatura (p_collection_allocation_id UUID);
- RETURNS TABLE (collection_id, pokedex_position_id,
  collection_allocation_id);
- SECURITY DEFINER;
- SET search_path = '';
- ownership (auth.uid());
- lock order Collection-first (FOR UPDATE em collection antes de
  collection_allocation, padrão 5046/5047/6123);
- checagem de lifecycle ACTIVE;
- revalidação de Assignment/Allocation (FOR UPDATE OF ca);
- semântica de UPSERT (DO UPDATE SET collection_allocation_id =
  EXCLUDED.collection_allocation_id);
- RETURNING já qualificada pelo nome da tabela (correção 6125 v1.2,
  PAUSE-SQL-DIRECT-AUDIT-01 item 2, mantida integralmente);
- ACL (REVOKE ALL FROM PUBLIC/anon, GRANT EXECUTE TO authenticated) —
  não retocada nesta migration, permanece como já concedida por 6125.

clear_pokedex_position_primary_representative() NÃO é tocada por esta
migration — não usa ON CONFLICT e não apresentou nenhum erro na auditoria
desta rodada.

Pré-requisitos:
- Query 6117/6118/6119/6120/6121/6122/6123/6124/6125 já aplicadas ao
  projeto qjfutqujxrbzgrtkpgkg (confirmado via pg_get_functiondef e
  pg_get_constraintdef nesta sessão).
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.set_pokedex_position_primary_representative(
    p_collection_allocation_id UUID
)
RETURNS TABLE (
    collection_id UUID,
    pokedex_position_id UUID,
    collection_allocation_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_collection_id       UUID;
    v_pokedex_position_id UUID;
    v_lifecycle_status    TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'authentication required';
    END IF;

    IF p_collection_allocation_id IS NULL THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_MISSING_PARAMETER: p_collection_allocation_id é obrigatório.';
    END IF;

    -- Leitura inicial (sem lock) só para descobrir qual Collection travar
    -- primeiro (PAUSE, item 3).
    SELECT ca.collection_id
      INTO v_collection_id
      FROM public.collection_pokedex_position_assignment a
      JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
      JOIN public.collection col ON col.id = ca.collection_id
     WHERE a.collection_allocation_id = p_collection_allocation_id
       AND col.owner_user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: nenhuma Assignment do chamador para este collection_allocation_id.';
    END IF;

    -- Lock real de Collection PRIMEIRO — ownership revalidada na própria
    -- WHERE do FOR UPDATE (padrão 5046/5047).
    SELECT col.lifecycle_status
      INTO v_lifecycle_status
      FROM public.collection col
     WHERE col.id = v_collection_id
       AND col.owner_user_id = auth.uid()
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: nenhuma Assignment do chamador para este collection_allocation_id.';
    END IF;

    IF v_lifecycle_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_COLLECTION_ARCHIVED: collection is archived.';
    END IF;

    -- Só DEPOIS do lock de Collection, revalida e trava a própria
    -- Assignment/Allocation (ordem: Collection -> Allocation).
    SELECT a.pokedex_position_id
      INTO v_pokedex_position_id
      FROM public.collection_pokedex_position_assignment a
      JOIN public.collection_allocation ca ON ca.id = a.collection_allocation_id
     WHERE a.collection_allocation_id = p_collection_allocation_id
       AND ca.collection_id = v_collection_id
     FOR UPDATE OF ca;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SET_POKEDEX_POSITION_PRIMARY_REPRESENTATIVE_ASSIGNMENT_NOT_FOUND: Assignment removida concorrentemente.';
    END IF;

    -- RETURNING qualificada pelo nome da tabela (PAUSE, item 2, 6125 v1.2 —
    -- mantida sem mudança). ÚNICA correção desta migration: ON CONFLICT
    -- passa a referenciar o PK pelo nome da constraint em vez da lista de
    -- colunas sem qualificação, eliminando a ambiguidade 42702 contra os
    -- OUT-parameters de mesmo nome do RETURNS TABLE (6126).
    RETURN QUERY
    INSERT INTO public.collection_pokedex_position_primary_representative
        (collection_id, pokedex_position_id, collection_allocation_id)
    VALUES (v_collection_id, v_pokedex_position_id, p_collection_allocation_id)
    ON CONFLICT ON CONSTRAINT pk_collection_pokedex_position_primary_representative
    DO UPDATE SET collection_allocation_id = EXCLUDED.collection_allocation_id
    RETURNING
        collection_pokedex_position_primary_representative.collection_id,
        collection_pokedex_position_primary_representative.pokedex_position_id,
        collection_pokedex_position_primary_representative.collection_allocation_id;
END;
$$;

COMMENT ON FUNCTION public.set_pokedex_position_primary_representative(UUID) IS
    'Define (ou substitui) o Primary Representative de uma Position, a partir de uma Assignment existente do chamador. UPSERT na PK (collection_id, pokedex_position_id), referenciada pelo nome da constraint (correção 6126 — ON CONFLICT por lista de colunas era ambíguo contra os OUT-parameters do RETURNS TABLE sob plpgsql.variable_conflict=error). Replace é o mesmo caminho que set. Nunca afeta completion (LDM-181).';

COMMIT;
