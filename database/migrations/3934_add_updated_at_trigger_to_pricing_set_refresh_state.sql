-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22.
-- Testada em BEGIN/ROLLBACK (trigger criado + UPDATE no-op comprovando updated_at avancando)
-- antes da aplicacao real.
--
-- Corrige divergencia encontrada no "Piloto pequeno" do dispatcher Set (P15, migration
-- 3933): as RPCs open_/checkpoint_/close_pricing_set_refresh_attempt fazem UPDATE em
-- pricing_set_refresh_state mas nunca tocam updated_at -- diferente do padrao ja usado por
-- pricing_sync_run (trg_pricing_sync_run_set_updated_at, ver comentario da migration 3933),
-- pricing_set_refresh_state (migration 3930, criacao da tabela) nunca ganhou o trigger
-- equivalente.
--
-- Correcao minima e nao-invasiva: reaproveita a funcao set_updated_at() ja existente e usada
-- por outras tabelas do projeto (pricing_source, card_condition, pricing_sync_run, etc.) --
-- nenhuma das 3 RPCs 3933 e alterada. O trigger dispara em QUALQUER UPDATE na tabela, entao
-- cobre estruturalmente tanto os UPDATEs das RPCs quanto qualquer escrita direta futura.
--
-- Grants: nenhum grant novo necessario -- CREATE TRIGGER nao concede nem exige privilegio
-- adicional sobre a tabela; RLS da tabela nao e afetada (trigger BEFORE UPDATE roda antes das
-- policies, mas nao altera nenhuma policy existente).

CREATE TRIGGER trg_pricing_set_refresh_state_updated_at
  BEFORE UPDATE ON public.pricing_set_refresh_state
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

COMMENT ON TRIGGER trg_pricing_set_refresh_state_updated_at ON public.pricing_set_refresh_state IS
  'Mantem updated_at coerente com qualquer UPDATE na tabela -- corrige divergencia encontrada no piloto pequeno do dispatcher Set (2026-08-22), onde as RPCs 3933 atualizavam a linha sem tocar updated_at.';
