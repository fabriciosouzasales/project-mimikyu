/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2253 - Portão de operações pontuais (oneshot_operation_gate)
Status......: CONFIRMADO EXECUTADO (2026-10-10; 2253 + 2253b grant)
Origem......: database/proposals/2026-10-10-me55-30th-celebration/README.md

Por quê
  A Edge Function import-classic-collection-assets roda sem entrada do chamador
  e só age se o portão estiver habilitado; ela consome o portão (enabled -> false)
  atomicamente antes de qualquer download. Habilitar = UPDATE manual por SQL.
  Só service_role lê/escreve; anon/authenticated sem grant; RLS ligada sem policy.

Uso registrado
  CLASSIC_COLLECTION_ASSETS_2026_10_10 — consumido 2026-10-10 13:53 UTC,
  resultado {IMPORTADA: 55} gravado em result.
===============================================================================
*/
CREATE TABLE IF NOT EXISTS public.oneshot_operation_gate (
  code text PRIMARY KEY CHECK (btrim(code) <> ''),
  enabled boolean NOT NULL DEFAULT false,
  enabled_at timestamptz,
  consumed_at timestamptz,
  result jsonb
);
ALTER TABLE public.oneshot_operation_gate ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.oneshot_operation_gate FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.oneshot_operation_gate IS
  'Portão de operações pontuais executadas por Edge Function (2026-10-10). Só service_role lê/escreve; a função consome o portão (enabled -> false) antes de agir.';

-- 2253b
GRANT SELECT, UPDATE ON public.oneshot_operation_gate TO service_role;
