// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/cli-validation.ts
// REVISION-03 (Bloco 5, Operational Safety) — validação PURA de modo de
// execução do CLI (scripts/run-pokemon-catalog-sourcing.ts). Extraído para
// este módulo (em vez de morar só no script) para que a suíte de testes
// offline (pokemon-catalog-sourcing.test.ts) possa exercitá-lo sem precisar
// importar de scripts/ — mod.ts (barrel deste diretório) já não é importado
// pelo script sem puxar @supabase/supabase-js, e o test file evita esse
// import por construção (ver pokemon-catalog-sourcing.test.ts).
//
// Contrato exigido pela auditoria física: "exatamente um modo entre
// fixture-check/dry-run/apply" — nunca zero (nenhuma ação especificada) nem
// mais de um (combinação ambígua de flags).

export interface CliModeArgs {
  fixtureCheck: boolean;
  dryRun: boolean;
  apply: boolean;
}

export interface CliModeValidation {
  ok: boolean;
  detail?: string;
}

export function validateExactlyOneMode(args: CliModeArgs): CliModeValidation {
  const selectedCount = [args.fixtureCheck, args.dryRun, args.apply].filter(
    Boolean,
  ).length;

  if (selectedCount === 0) {
    return {
      ok: false,
      detail:
        "Nenhum modo especificado — use exatamente um entre --fixture-check, --dry-run, --apply.",
    };
  }
  if (selectedCount > 1) {
    return {
      ok: false,
      detail:
        "Mais de um modo especificado simultaneamente — use exatamente um entre --fixture-check, --dry-run, --apply.",
    };
  }
  return { ok: true };
}
