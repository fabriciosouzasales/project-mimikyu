/*
Project Mimikyu
Script administrativo standalone: run-pokemon-catalog-sourcing
POKEMON-CATALOG-SOURCING-INITIAL-LOAD-EXECUTOR-STAGING-01 (2026-09-04).

Caller Deno standalone do Pokémon Catalog Sourcing (PokéAPI) — ver contrato
canônico completo em docs/06a-pokemon-catalog-sourcing.md. Mesmo precedente
estrutural de scripts/sync-ptax-fx-rate.ts / scripts/sync-justtcg-pricing.ts:
roda localmente, sob demanda, com a Service Role Key do projeto, nunca é
implantado no Supabase ("Ferramenta administrativa: script Deno standalone
(fora do banco)" — Seção 15 do contrato).

Toda a lógica de negócio (aquisição PokéAPI, normalização, cross-check
nacional obrigatório, montagem/ordenação determinística do snapshot,
orquestração DRY_RUN/APPLY) mora em
supabase/functions/_shared/pokemon-catalog-sourcing/ — este arquivo é só o
ADAPTER MANUAL: lê variáveis de ambiente, cria o cliente Supabase real,
constrói o SnapshotStore em disco e chama runDryRun()/runApply(). Nenhuma
lógica de negócio é duplicada aqui.

Sourcing foundation física (6090-6110) já CONFIRMADO EXECUTADO E PROMOVIDO —
este executor é a peça que falta para acionar a carga real via PokéAPI
(POKEMON-CATALOG-SOURCING-INITIAL-LOAD), NENHUMA das duas chamadas reais foi
feita nesta rodada de staging (nem PokéAPI, nem Supabase) — ver relatório de
entrega da rodada para o diagnóstico completo.

Uso:

  # Validação offline (sempre segura — nenhuma rede, nenhuma escrita no
  # Supabase; roda a bateria completa de testes do núcleo compartilhado,
  # ver pokemon-catalog-sourcing.test.ts):
  deno run --allow-env scripts/run-pokemon-catalog-sourcing.ts --fixture-check

  # DRY_RUN real (aquisição PokéAPI real + PLAN real no Supabase; NENHUMA
  # escrita canônica — Seção 9, "Zero escrita canônica"):
  deno run --allow-net --allow-env --allow-read --allow-write \
    scripts/run-pokemon-catalog-sourcing.ts --dry-run [--concurrency=5]

  # APPLY real (exige o run_id/run_code de um DRY_RUN COMPLETED anterior;
  # ZERO chamadas HTTP à PokéAPI — reutiliza EXATAMENTE o snapshot local
  # salvo pelo DRY_RUN, Seção 10):
  deno run --allow-net --allow-env --allow-read --allow-write \
    scripts/run-pokemon-catalog-sourcing.ts --apply \
    --preflight-run-id=<uuid> --preflight-run-code=<RUN-AAAAMMDD-NNNNNNNN>

Credencial: SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY, exclusivamente por
variável de ambiente, nunca argumento de linha de comando, nunca logada —
sanitize() (núcleo compartilhado) redige qualquer JWT/Bearer/Authorization
que apareça em mensagem de erro propagada de qualquer camada (PostgREST,
fetch, timeout).
*/

import { createClient } from "@supabase/supabase-js";
import {
  buildFsSnapshotStore,
  buildPokemonCatalogSourcingSupabaseAdapter,
  clampConcurrency,
  runApply,
  runDryRun,
  runPokemonCatalogSourcingAsyncTests,
  runPokemonCatalogSourcingTests,
  validateExactlyOneMode,
} from "../supabase/functions/_shared/pokemon-catalog-sourcing/mod.ts";

const SNAPSHOT_DIRECTORY = "./.pokemon-catalog-sourcing-snapshots";

interface ParsedArgs {
  fixtureCheck: boolean;
  dryRun: boolean;
  apply: boolean;
  concurrency: number;
  preflightRunId: string | null;
  preflightRunCode: string | null;
}

export function parseArgs(argv: string[]): ParsedArgs {
  const args: ParsedArgs = {
    fixtureCheck: false,
    dryRun: false,
    apply: false,
    concurrency: 5,
    preflightRunId: null,
    preflightRunCode: null,
  };
  for (const arg of argv) {
    if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--apply") args.apply = true;
    else if (arg.startsWith("--concurrency=")) {
      args.concurrency = Number(arg.slice("--concurrency=".length));
    } else if (arg.startsWith("--preflight-run-id=")) {
      args.preflightRunId = arg.slice("--preflight-run-id=".length);
    } else if (arg.startsWith("--preflight-run-code=")) {
      args.preflightRunCode = arg.slice("--preflight-run-code=".length);
    }
  }
  return args;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`Variável de ambiente obrigatória ausente: ${name}`);
    Deno.exit(1);
  }
  return value;
}

async function runFixtureCheck(): Promise<void> {
  console.log(
    "=== MODO FIXTURE-CHECK (offline, sem rede, sem escrita no Supabase) ===\n",
  );
  const syncTests = runPokemonCatalogSourcingTests();
  for (const [label, ok] of syncTests.assertions) {
    console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  }
  const asyncTests = await runPokemonCatalogSourcingAsyncTests();
  for (const [label, ok] of asyncTests.assertions) {
    console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  }
  const todas = [...syncTests.assertions, ...asyncTests.assertions];
  const falharam = todas.filter(([, ok]) => !ok);
  console.log(
    `\n${
      falharam.length === 0
        ? "TODAS as asserções passaram"
        : `${falharam.length} asserção(ões) FALHARAM`
    } (${todas.length} no total).`,
  );
  console.log(
    "\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.",
  );
  if (falharam.length > 0) Deno.exit(1);
}

async function runReal(args: ParsedArgs): Promise<void> {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const port = buildPokemonCatalogSourcingSupabaseAdapter(supabase);
  const snapshotStore = buildFsSnapshotStore(SNAPSHOT_DIRECTORY);

  if (args.dryRun) {
    const concurrency = clampConcurrency(args.concurrency);
    console.log(`Iniciando DRY_RUN (concorrência=${concurrency})...`);
    const result = await runDryRun({
      port,
      snapshotStore,
      concurrency,
      fetchImpl: fetch,
      waitImpl: (ms: number) => new Promise((r) => setTimeout(r, ms)),
    });
    console.log(JSON.stringify(result, null, 2));
    if (
      result.kind !== "COMPLETED" && result.kind !== "COMPLETED_WITH_DIVERGENCES"
    ) {
      Deno.exit(1);
    }
    return;
  }

  if (args.apply) {
    if (!args.preflightRunId || !args.preflightRunCode) {
      console.error(
        "--apply exige --preflight-run-id=<uuid> e --preflight-run-code=<RUN-...> (do DRY_RUN COMPLETED aprovado).",
      );
      Deno.exit(1);
    }
    console.log(`Iniciando APPLY (preflight=${args.preflightRunCode})...`);
    const result = await runApply({
      port,
      snapshotStore,
      preflightRunId: args.preflightRunId!,
      preflightRunCode: args.preflightRunCode!,
    });
    console.log(JSON.stringify(result, null, 2));
    if (result.kind !== "COMPLETED") Deno.exit(1);
    return;
  }

  console.error(
    "Nenhuma ação especificada — use --dry-run, --apply ou --fixture-check.",
  );
  Deno.exit(1);
}

async function main(): Promise<void> {
  const args = parseArgs(Deno.args);

  // REVISION-03 (Bloco 5, Operational Safety) — "exatamente um modo entre
  // fixture-check/dry-run/apply": nem zero flags (comportamento implícito
  // ambíguo) nem mais de uma simultaneamente. validateExactlyOneMode() é
  // puro e testado offline (cli-validation.ts).
  const modeValidation = validateExactlyOneMode(args);
  if (!modeValidation.ok) {
    console.error(modeValidation.detail);
    Deno.exit(1);
    return;
  }

  if (args.fixtureCheck) {
    await runFixtureCheck();
    return;
  }

  // REVISION-03 (Bloco 5) — dry-run/apply SEM SUPABASE_URL/
  // SUPABASE_SERVICE_ROLE_KEY deve falhar com erro e exit não-zero, NUNCA
  // cair silenciosamente para --fixture-check (comportamento antigo,
  // removido nesta revisão: mascarava a ausência de credencial como se
  // fosse uma execução offline bem-sucedida). requireEnv() dentro de
  // runReal() ofereceria o mesmo efeito individualmente por variável, mas a
  // checagem explícita aqui falha ANTES de sequer tentar criar o cliente
  // Supabase, e documenta a intenção no ponto de entrada do modo real.
  const hasSupabaseEnv = !!Deno.env.get("SUPABASE_URL") &&
    !!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!hasSupabaseEnv) {
    console.error(
      "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes — --dry-run/--apply exigem ambas; nenhum fallback automático para --fixture-check.",
    );
    Deno.exit(1);
    return;
  }

  await runReal(args);
}

if (import.meta.main) {
  await main();
}
