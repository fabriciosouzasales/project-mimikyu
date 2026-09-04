/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6701 - Revoke EXECUTE das Trigger Functions do
               Pokémon Catalog Foundation
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (aplicado em 2026-09-04,
               COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01)

Descrição...:
Correção transversal (mesmo padrão já usado em Query 3053/3091 —
numericamente após o último Query do módulo, 6700, mas conceitualmente
não pertence ao bloco de nenhuma entidade específica). Achado de
auditoria externa: as 9 trigger functions criadas pelas Queries 6001
(pokemon_generation), 6011 (pokemon_species) e 6021
(pokemon_species_external_reference) não tiveram EXECUTE revogado de
PUBLIC/anon/authenticated no momento de sua criação — divergindo do
padrão já estabelecido em Collections para trigger functions
disparadas só pelo próprio trigger (ex.: Query 5032/5033/5042/5045,
"REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated").

Por padrão, o PostgreSQL concede EXECUTE a PUBLIC na criação de toda
função nova, salvo REVOKE explícito. Nenhuma das 9 funções abaixo é
projetada para ser chamada diretamente por client role — são
exclusivamente disparadas pelos triggers trg_010_/020_/030_ das
Queries 6001/6011/6021, sob a identidade do owner da tabela. Confirmado
por consulta real a pg_proc/has_function_privilege() antes desta
correção: as 9 funções tinham proacl NULL (default) e
has_function_privilege('anon'/'authenticated', ..., 'EXECUTE') = true.

Como 6001/6011/6021 já estão CONFIRMADO EXECUTADO (Princípio da Fonte
Canônica — nunca reescrever silenciosamente histórico físico já
aplicado), esta correção é uma Query nova e independente, não uma
edição retroativa dos três arquivos originais. O comportamento das
triggers em si (normalize_/govern_/touch_updated_at) não muda — apenas
o privilégio de chamada direta por role client-facing é removido.

Pré-requisitos:
- Query 6001 - Pokemon Generation Triggers.
- Query 6011 - Pokemon Species Triggers.
- Query 6021 - Pokemon Species External Reference Triggers.
===============================================================================
*/

BEGIN;

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_generation() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokemon_generation() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokemon_generation_updated_at() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_species() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokemon_species() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokemon_species_updated_at() FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_species_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokemon_species_external_reference() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokemon_species_external_reference_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01).
-- Postcheck confirmou has_function_privilege('anon'/'authenticated',
-- ..., 'EXECUTE') = false para as 9 funções após esta correção; os
-- triggers trg_010_/020_/030_ continuam ativos e funcionais (disparo
-- por trigger não depende de EXECUTE de client role).
-- ================================================================
