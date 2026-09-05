/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5085 - Alter Collection Reference: Widen reference_kind for POKEDEX
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-
               MODELING-AUDIT-01, aplicado em 2026-09-05 via
               COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01)

Descrição...:
Alarga chk_collection_reference_kind (Query 5049) para aceitar também
'POKEDEX', exatamente pelo mecanismo já anunciado no cabeçalho de 5049:
"alargável por DROP+ADD CONSTRAINT quando collection_pokedex_reference
existir, nunca pré-declarando um valor sem tabela correspondente" —
mesmo padrão incremental já usado por chk_collection_mode (5030→5060)
e chk_collection_completion_policy (5067→5078).

collection_pokedex_reference (Query 5087) é criada em seguida nesta
mesma pasta de staging — este arquivo apenas alarga o discriminador do
supertipo; nenhuma linha de dado é afetada (collection_reference tem 0
linhas hoje, confirmado por auditoria read-only em 2026-09-05).

Aplicação real (COLLECTIONS-POKEDEX-FATIA-B-IMPLEMENTATION-01): aplicada
via apply_migration/MCP do Supabase (projeto qjfutqujxrbzgrtkpgkg), uma
Query por vez, na ordem exata 5085→5099, sem alteração de SQL. Postcheck
físico independente (COLLECTIONS-POKEDEX-FATIA-B-CANONICAL-PROMOTION-01)
confirmou chk_collection_reference_kind aceitando exatamente
('CARD_SET', 'POKEDEX'). Zero resíduo (0 linhas em collection_reference
após os testes funcionais, executados em BEGIN/ROLLBACK).

STATUS DESTA QUERY: CONFIRMADO EXECUTADO.
================================================================
*/

BEGIN;

ALTER TABLE public.collection_reference
    DROP CONSTRAINT chk_collection_reference_kind;

ALTER TABLE public.collection_reference
    ADD CONSTRAINT chk_collection_reference_kind
    CHECK (reference_kind IN ('CARD_SET', 'POKEDEX'));

COMMIT;
