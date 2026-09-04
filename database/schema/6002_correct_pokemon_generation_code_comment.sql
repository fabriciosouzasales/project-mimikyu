/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6002 - Correção Documental do Comentário de
               pokemon_generation.code
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (aplicado em 2026-09-04,
               COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01)

Descrição...:
Correção documental pontual (achado de auditoria externa). O
COMMENT ON COLUMN aplicado pela Query 6000 para pokemon_generation.code
afirmava que o código segue "formato GENERATION_<algarismo romano>",
dando a entender que o banco valida especificamente algarismo romano.
Isso não é verdade: o CHECK estrutural real
(ck_pokemon_generation_code_format, Query 6000) é genérico —
CHECK (code ~ '^[A-Z][A-Z0-9_]*$') — e nunca validou algarismo romano
especificamente. GENERATION_I, GENERATION_II, GENERATION_III... é
convenção canônica de nomenclatura (decisão congelada,
COLLECTIONS-PHYSICAL-INCREMENT-02G-IMPLEMENTATION-01), não uma regra
estrutural imposta pelo CHECK.

Esta Query corrige apenas o texto do comentário armazenado no banco
(COMMENT ON COLUMN) — não altera a constraint, o tipo, o default nem
qualquer outro aspecto estrutural de pokemon_generation.code. A Query
6000 (CONFIRMADO EXECUTADO) não foi reescrita retroativamente — ver
nota de correção documental apensada ao final do próprio arquivo 6000.

Pré-requisitos:
- Query 6000 - Create Pokemon Generation Table.
===============================================================================
*/

BEGIN;

COMMENT ON COLUMN public.pokemon_generation.code IS
    'Código técnico estável, convenção canônica GENERATION_I, GENERATION_II, GENERATION_III... (ex.: GENERATION_I). O CHECK estrutural (ck_pokemon_generation_code_format) é genérico (^[A-Z][A-Z0-9_]*$) — não valida algarismo romano especificamente; a sequência romana é convenção de nomenclatura, não regra imposta pelo banco. Imutável (protegido por trigger de governança, Query 6001).';

COMMIT;

-- ================================================================
-- Confirmado executado (2026-09-04, via apply_migration/MCP do
-- Supabase, projeto qjfutqujxrbzgrtkpgkg,
-- COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01).
-- Postcheck confirmou o novo texto em pg_description. Nenhuma
-- constraint, trigger, índice ou dado alterado.
-- ================================================================
