// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/orchestrator.ts
// Fluxos DRY_RUN e APPLY (Seção 8 do contrato) — ligam acquisition.ts +
// cross-check.ts + snapshot.ts + a porta das RPCs (run-port.ts). Núcleo puro
// quanto a I/O: fetch/wait/port/snapshotStore são sempre injetados.
//
// Garantia estrutural exigida pelo contrato ("APPLY usa EXATAMENTE snapshot
// aprovado e faz ZERO GETs à PokéAPI"): runApply() nunca importa
// acquisition.ts/discovery.ts/http.ts — não há NENHUMA referência a fetch
// neste fluxo, então é impossível ele disparar uma chamada HTTP por
// construção, não apenas por disciplina de runtime.

import { clampConcurrency, createHeartbeatGate, type FetchJsonDeps } from "./http.ts";
import { acquirePokemonCatalogSnapshot } from "./acquisition.ts";
import { crossCheckNationalPokedex } from "./cross-check.ts";
import { buildDeterministicSnapshot, isPayloadGuardExceeded } from "./snapshot.ts";
import { extractCanonicalNameEn, extractIdFromUrl } from "./normalize.ts";
import type {
  PokemonCatalogSourcingPort,
} from "./run-port.ts";
import type { PokemonCatalogSnapshot, SnapshotStore, WaitLike } from "./types.ts";

// REVISION-03 (Bloco 1, National Authority) — identidade numérica fixa
// (Seção 4.4), nunca o slug "national". Ver mesma decisão em acquisition.ts
// (NATIONAL_POKEDEX_URL) — este valor é o que efetivamente vai gravado no
// snapshot como `national_pokedex.source_url`.
export const NATIONAL_POKEDEX_SOURCE_URL = "https://pokeapi.co/api/v2/pokedex/1/";

export type DryRunOutcomeKind =
  | "COMPLETED"
  | "COMPLETED_WITH_DIVERGENCES"
  | "SOURCE_BUSY"
  | "ACQUISITION_FAILED"
  | "CROSS_CHECK_FAILED"
  | "PAYLOAD_GUARD_EXCEEDED"
  | "PLAN_VALIDATION_FAILURE"
  // REVISION-03 (Bloco 5, Operational Safety) — distintos de
  // ACQUISITION_FAILED/PLAN_VALIDATION_FAILURE: cobrem uma EXCEÇÃO lançada
  // pela própria chamada de heartbeat/plan (rede, RPC indisponível), não uma
  // falha de negócio reportada pelo outcome normal da RPC.
  | "HEARTBEAT_FAILED"
  | "PLAN_EXCEPTION";

// REVISION-03 (Bloco 5, Operational Safety) — uma falha do PRÓPRIO
// closeFailed (rede instável, RPC indisponível) nunca pode mascarar ou
// substituir o erro original que motivou a tentativa de fechamento. Esta
// função nunca lança: o catch é intencionalmente silencioso quanto ao
// *retorno* de closeFailed — o erro original continua sendo o único
// reportado ao chamador de runDryRun/runApply.
async function closeFailedSafely(
  port: PokemonCatalogSourcingPort,
  runId: string,
  errorSummary: string,
): Promise<void> {
  try {
    await port.closeFailed(runId, errorSummary);
  } catch {
    // Intencionalmente engolido — ver comentário acima.
  }
}

// REVISION-05 (Bloco 3, residual físico) — uma espera de retry/Retry-After
// longa (Query 6103: stale threshold de 30min) NUNCA pode deixar o run sem
// heartbeat pelo tempo total da espera. Implementação DELIBERADAMENTE na
// camada de orquestração, não em http.ts: `fetchJsonWithRetry` (módulo HTTP
// genérico, sem qualquer noção de RPC/heartbeat) continua chamando apenas
// `deps.waitImpl(ms)` exatamente como sempre fez — nada em http.ts muda. O
// que muda é QUAL função é injetada como `waitImpl` pelo orquestrador: esta
// função fatia uma espera longa em pedaços de no máximo `chunkMs` e invoca o
// heartbeat gate ENTRE os pedaços, preservando o tempo total solicitado
// EXATAMENTE — a soma de todas as chamadas a `waitImpl` internas é sempre
// igual ao `ms` recebido, nunca menos (violaria a política de retry/
// Retry-After) nem mais (adicionaria latência artificial não solicitada).
// `heartbeatTick` continua sendo o mesmo gate temporal único (createHeartbeatGate)
// usado no restante da aquisição — chamá-lo com frequência aqui é seguro por
// construção: ele só produz um heartbeat real quando tempo suficiente já
// passou desde o último, independente de quantas vezes for invocado.
export const HEARTBEAT_AWARE_WAIT_CHUNK_MS = 60_000; // 1min — folga ampla sob o stale threshold de 30min (Query 6103)

export function createHeartbeatAwareWait(
  waitImpl: WaitLike,
  heartbeatTick: () => Promise<void>,
  chunkMs: number = HEARTBEAT_AWARE_WAIT_CHUNK_MS,
): WaitLike {
  return async (ms: number) => {
    let remaining = ms;
    while (remaining > chunkMs) {
      await waitImpl(chunkMs);
      remaining -= chunkMs;
      await heartbeatTick();
    }
    if (remaining > 0) {
      await waitImpl(remaining);
    }
  };
}

export interface DryRunOutcome {
  kind: DryRunOutcomeKind;
  runId?: string;
  runCode?: string;
  snapshotHash?: string | null;
  planSummary?: Record<string, unknown> | null;
  detail?: string;
  crossCheckFailures?: number;
}

export interface DryRunDeps extends FetchJsonDeps {
  port: PokemonCatalogSourcingPort;
  snapshotStore: SnapshotStore;
  concurrency?: number;
  // REVISION-03 (Bloco 3) — relógio injetado para o heartbeat gate temporal
  // (createHeartbeatGate, http.ts). Nunca `Date.now` referenciado
  // diretamente neste módulo; default abaixo é o único ponto onde o
  // ambiente global é tocado, e só quando o chamador não injeta nada
  // (permite determinismo total em teste).
  nowImpl?: () => number;
}

export async function runDryRun(deps: DryRunDeps): Promise<DryRunOutcome> {
  const openResult = await deps.port.openRun("DRY_RUN", null);
  if (openResult.outcome === "SOURCE_BUSY") {
    return { kind: "SOURCE_BUSY" };
  }
  const runId = openResult.runId!;
  const runCode = openResult.runCode!;

  // Heartbeat ANTES de iniciar a aquisição HTTP — única forma de o run
  // entrar em ACQUIRING de forma durável e observável (Query 6107),
  // precondição obrigatória de PLAN (Query 6104). REVISION-03 (Bloco 5) —
  // após CLAIMED, uma exceção aqui (rede, RPC indisponível) deve tentar
  // closeFailed antes de propagar, para nunca deixar o run travado em
  // PENDING sem tentativa de reconciliação.
  try {
    await deps.port.heartbeat(runId);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await closeFailedSafely(deps.port, runId, `HEARTBEAT_EXCEPTION: ${message}`);
    return { kind: "HEARTBEAT_FAILED", runId, runCode, detail: message };
  }

  const concurrency = clampConcurrency(deps.concurrency ?? 5);
  const nowImpl = deps.nowImpl ?? (() => Date.now());
  // REVISION-03 (Bloco 3) — gate temporal único, compartilhado por TODA a
  // aquisição (discovery + detail fetch): nunca decide por contagem de
  // itens, sempre por tempo decorrido real, folgado frente ao stale
  // threshold de 30min (Query 6103).
  const heartbeatTick = createHeartbeatGate(
    () => deps.port.heartbeat(runId).then(() => undefined),
    nowImpl,
  );
  // REVISION-05 (Bloco 3, residual físico) — o `waitImpl` passado para a
  // aquisição nunca é o `deps.waitImpl` cru: é esta versão heartbeat-aware,
  // que fatia qualquer espera de retry/Retry-After longa em pedaços e
  // renova o heartbeat entre eles (ver createHeartbeatAwareWait acima) — sem
  // alterar em nada o tempo total efetivamente aguardado.
  const heartbeatAwareWait = createHeartbeatAwareWait(deps.waitImpl, heartbeatTick);

  let acquisition;
  try {
    acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: deps.fetchImpl,
      waitImpl: heartbeatAwareWait,
      timeoutMs: deps.timeoutMs,
      maxAttempts: deps.maxAttempts,
      retryDelaysMs: deps.retryDelaysMs,
      concurrency,
      onHeartbeat: heartbeatTick,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await closeFailedSafely(deps.port, runId, `ACQUISITION_EXCEPTION: ${message}`);
    return { kind: "ACQUISITION_FAILED", runId, runCode, detail: message };
  }

  if (acquisition.status !== "SUCCESS") {
    const detail = acquisition.issues.length > 0
      ? acquisition.issues.map((i) =>
        `${i.stage}:${i.externalId ?? "?"}:${i.reason}`
      ).join("; ")
      : (acquisition.detail ?? "ACQUISITION_FAILED");
    await closeFailedSafely(deps.port, runId, detail);
    return { kind: "ACQUISITION_FAILED", runId, runCode, detail };
  }

  // Cross-check nacional OBRIGATÓRIO (Seção 4.3) — ANTES da construção do
  // snapshot, responsabilidade exclusiva do script (nunca do banco/PLAN).
  const crossCheck = crossCheckNationalPokedex(
    acquisition.speciesRaw,
    acquisition.nationalPokedexRaw!.pokemon_entries ?? [],
  );
  if (!crossCheck.ok) {
    const detail =
      `CROSS_CHECK_NACIONAL_FAILURE: ${crossCheck.failures.length} divergência(s).`;
    await closeFailedSafely(deps.port, runId, detail);
    return {
      kind: "CROSS_CHECK_FAILED",
      runId,
      runCode,
      detail,
      crossCheckFailures: crossCheck.failures.length,
    };
  }

  const nationalCanonicalName = extractCanonicalNameEn(
    acquisition.nationalPokedexRaw!.names,
  );
  if (!nationalCanonicalName) {
    await closeFailedSafely(deps.port, runId, "NATIONAL_POKEDEX_CANONICAL_NAME_BLANK");
    return {
      kind: "ACQUISITION_FAILED",
      runId,
      runCode,
      detail: "NATIONAL_POKEDEX_CANONICAL_NAME_BLANK",
    };
  }

  // REVISION-03 (Bloco 1, National Authority) — `national_dex_number` no
  // snapshot final DEVE vir da autoridade (`/pokedex/1/.pokemon_entries[]`),
  // nunca do auto-declarado de Species (`pokedex_numbers[national]`), que
  // fica exclusivamente como ponto de cross-check (já validado acima, S=P
  // exato). Construído aqui — e não em acquisition.ts — porque a ordem de
  // aquisição mandatória (Seção 3) busca Species antes de National Pokédex;
  // a autoridade só está disponível neste ponto do fluxo. Se o cross-check
  // já passou, todo external_species_id descoberto tem uma entrada de
  // autoridade correspondente (garantido por S=P) — a ausência aqui indica
  // uma inconsistência interna grave, nunca silenciosamente ignorada.
  const nationalAuthorityByExternalSpeciesId = new Map<string, number>();
  for (const entry of acquisition.nationalPokedexRaw!.pokemon_entries ?? []) {
    const externalSpeciesId = extractIdFromUrl(entry.pokemon_species?.url ?? "");
    if (externalSpeciesId) {
      nationalAuthorityByExternalSpeciesId.set(externalSpeciesId, entry.entry_number);
    }
  }
  const missingAuthorityIds: string[] = [];
  const speciesWithAuthorityNumber = acquisition.species.map((row) => {
    const authorityNumber = nationalAuthorityByExternalSpeciesId.get(
      row.external_species_id,
    );
    if (authorityNumber === undefined) {
      missingAuthorityIds.push(row.external_species_id);
      return row;
    }
    return { ...row, national_dex_number: authorityNumber };
  });
  if (missingAuthorityIds.length > 0) {
    // Defensivo: nunca deveria ocorrer pós cross-check S=P bem-sucedido — se
    // ocorrer, é uma inconsistência interna grave e nunca prossegue
    // silenciosamente para PLAN com valores auto-declarados não confirmados.
    const detail =
      `NATIONAL_AUTHORITY_MISSING_APOS_CROSS_CHECK: Species sem entrada de autoridade ` +
      `em /pokedex/1/.pokemon_entries[] apesar do cross-check ter passado: ${
        missingAuthorityIds.join(", ")
      }.`;
    await closeFailedSafely(deps.port, runId, detail);
    return { kind: "ACQUISITION_FAILED", runId, runCode, detail };
  }

  const snapshot: PokemonCatalogSnapshot = buildDeterministicSnapshot({
    regions: acquisition.regions,
    generations: acquisition.generations,
    species: speciesWithAuthorityNumber,
    nationalPokedex: {
      external_pokedex_id: "1",
      code: "NATIONAL",
      canonical_name: nationalCanonicalName,
      source_url: NATIONAL_POKEDEX_SOURCE_URL,
      metadata: {},
    },
    nationalPokedexEntries: acquisition.nationalPokedexRaw!.pokemon_entries.map(
      (e) => ({
        external_species_id:
          e.pokemon_species.url.match(/\/(\d+)\/?$/)?.[1] ?? "",
        position_number: e.entry_number,
      }),
    ),
  });

  if (isPayloadGuardExceeded(snapshot)) {
    await closeFailedSafely(deps.port, runId, "PAYLOAD_GUARD_EXCEEDED_LOCAL");
    return { kind: "PAYLOAD_GUARD_EXCEEDED", runId, runCode };
  }

  // Fluxo canônico (Seção 8): "... → PLAN → salvar snapshot local sanitizado"
  // — o snapshot NUNCA é persistido antes do retorno do PLAN. Um snapshot
  // pré-PLAN jamais é tratado como aprovado: se a chamada de PLAN abaixo
  // lançar, falhar, ou divergir, nenhum arquivo é gravado neste run.
  // REVISION-03 (Bloco 5) — uma EXCEÇÃO na própria chamada (rede, RPC
  // indisponível) também tenta closeFailed, distinto de um outcome de
  // negócio VALIDATION_FAILURE/PAYLOAD_GUARD_EXCEEDED retornado normalmente
  // pela RPC (tratado logo abaixo).
  let planResult;
  try {
    planResult = await deps.port.plan(runId, snapshot);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await closeFailedSafely(deps.port, runId, `PLAN_EXCEPTION: ${message}`);
    return { kind: "PLAN_EXCEPTION", runId, runCode, detail: message };
  }

  if (
    planResult.outcome === "VALIDATION_FAILURE" ||
    planResult.outcome === "PAYLOAD_GUARD_EXCEEDED"
  ) {
    return {
      kind: planResult.outcome === "PAYLOAD_GUARD_EXCEEDED"
        ? "PAYLOAD_GUARD_EXCEEDED"
        : "PLAN_VALIDATION_FAILURE",
      runId,
      runCode,
      snapshotHash: planResult.snapshotHash,
    };
  }

  // Persistência local só acontece DEPOIS do retorno do PLAN — nunca antes
  // (Seção 8: "... → PLAN → salvar snapshot local sanitizado"). REVISION-02:
  // a partir daqui, `planResult.outcome` só pode ser COMPLETED ou
  // COMPLETED_WITH_DIVERGENCES (os dois casos de falha já retornaram acima),
  // e AMBOS são persistidos — um snapshot divergente ainda tem valor de
  // auditoria/diagnóstico e não deve ser descartado. O que distingue os dois
  // não é "foi salvo ou não", e sim o campo `planOutcome` gravado no próprio
  // envelope: só COMPLETED é elegível como preflight de APPLY (ver
  // runApply() abaixo, que recusa localmente qualquer outro valor). Para
  // VALIDATION_FAILURE/PAYLOAD_GUARD_EXCEEDED/exceções, nenhum registro
  // chega a ser criado — a ausência física do arquivo cobre esses casos.
  if (!planResult.snapshotHash) {
    // Defensivo: o contrato físico (Query 6104) garante snapshot_hash não
    // nulo para os dois outcomes de sucesso do PLAN, mas nunca persistimos
    // um envelope sem hash de vinculação — isso enfraqueceria a validação
    // server-side de hash no APPLY (proibido pela revisão).
    await closeFailedSafely(
      deps.port,
      runId,
      `PLAN_${planResult.outcome}_SEM_SNAPSHOT_HASH`,
    );
    return {
      kind: "PLAN_VALIDATION_FAILURE",
      runId,
      runCode,
      detail:
        `PLAN retornou ${planResult.outcome} sem snapshot_hash — persistência local abortada.`,
    };
  }
  await deps.snapshotStore.save({
    runId,
    runCode,
    snapshotHash: planResult.snapshotHash,
    planOutcome: planResult.outcome,
    snapshot,
  });

  return {
    kind: planResult.outcome === "COMPLETED_WITH_DIVERGENCES"
      ? "COMPLETED_WITH_DIVERGENCES"
      : "COMPLETED",
    runId,
    runCode,
    snapshotHash: planResult.snapshotHash,
    planSummary: planResult.planSummary,
  };
}

export type ApplyOutcomeKind =
  | "COMPLETED"
  | "SOURCE_BUSY"
  | "SNAPSHOT_NOT_FOUND"
  | "SNAPSHOT_MISMATCH"
  | "PREFLIGHT_NOT_ELIGIBLE"
  | "APPLY_FAILED";

export interface ApplyOutcome {
  kind: ApplyOutcomeKind;
  runId?: string;
  runCode?: string;
  applySummary?: Record<string, unknown>;
  detail?: string;
}

export interface ApplyDeps {
  port: PokemonCatalogSourcingPort;
  snapshotStore: SnapshotStore;
  preflightRunId: string;
  // Chave usada para localizar o snapshot local salvo pelo DRY_RUN aprovado
  // — é o run_code do PRÓPRIO DRY_RUN (preflight), nunca do run APPLY que
  // está prestes a ser aberto.
  preflightRunCode: string;
}

export async function runApply(deps: ApplyDeps): Promise<ApplyOutcome> {
  // Arquivo em disco existe para QUALQUER outcome terminal de sucesso do
  // PLAN — COMPLETED ou COMPLETED_WITH_DIVERGENCES (REVISION-02) — nunca
  // para VALIDATION_FAILURE/PAYLOAD_GUARD_EXCEEDED/exceção. A ausência física
  // do envelope cobre esses últimos casos; ausência não implica, por si só,
  // que o preflight seja elegível — isso é checado abaixo via `planOutcome`.
  const record = await deps.snapshotStore.load(deps.preflightRunCode);
  if (!record) {
    return {
      kind: "SNAPSHOT_NOT_FOUND",
      detail:
        `Nenhum snapshot local encontrado para o run ${deps.preflightRunCode}.`,
    };
  }

  // Vínculo inequívoco run_id/run_code (Seção 8 + auditoria item 4): o
  // envelope persistido amarra o snapshot ao run_id que o PLAN produziu —
  // se o chamador passar um preflightRunId que não bate com o gravado no
  // próprio arquivo, isso é tratado como inconsistência e barrado aqui,
  // antes de qualquer chamada a openRun/apply.
  if (record.runId !== deps.preflightRunId) {
    return {
      kind: "SNAPSHOT_MISMATCH",
      detail:
        `snapshot local do run_code ${deps.preflightRunCode} pertence a run_id ` +
        `${record.runId}, mas foi solicitado com preflightRunId ${deps.preflightRunId}.`,
    };
  }

  // REVISION-03 (Bloco 4, Snapshot Integrity) — mesmo vínculo, agora sobre
  // run_code: o envelope carrega seu próprio runCode gravado no momento do
  // PLAN; se não bater com o run_code de preflight informado pelo chamador,
  // é a mesma classe de inconsistência do check de runId acima — barrado
  // ANTES de abrir run ou chamar apply, nunca depois.
  if (record.runCode !== deps.preflightRunCode) {
    return {
      kind: "SNAPSHOT_MISMATCH",
      detail:
        `snapshot local carregado sob a chave ${deps.preflightRunCode} tem ` +
        `runCode interno ${record.runCode} — inconsistência de vínculo run_code.`,
    };
  }

  // Elegibilidade para APPLY (REVISION-02): "COMPLETED_WITH_DIVERGENCES
  // nunca pode ser usado como preflight de APPLY" — mas seu registro EXISTE
  // em disco (persistido para auditoria/diagnóstico), então a recusa não
  // pode depender de SNAPSHOT_NOT_FOUND; é uma checagem de negócio explícita
  // sobre `planOutcome`, feita ANTES de abrir run ou chamar apply.
  if (record.planOutcome !== "COMPLETED") {
    return {
      kind: "PREFLIGHT_NOT_ELIGIBLE",
      detail:
        `snapshot local do run_code ${deps.preflightRunCode} tem planOutcome=` +
        `${record.planOutcome} — só COMPLETED é elegível como preflight de APPLY.`,
    };
  }

  const openResult = await deps.port.openRun("APPLY", deps.preflightRunId);
  if (openResult.outcome === "SOURCE_BUSY") {
    return { kind: "SOURCE_BUSY" };
  }
  const runId = openResult.runId!;
  const runCode = openResult.runCode!;

  // REVISION-03 (Bloco 4, Snapshot Integrity) — o banco é a autoridade final
  // de preflight/hash (Query 6103 retorna o preflight_run_id/
  // preflight_snapshot_hash que ele próprio resolveu para este APPLY). Se o
  // que o banco resolveu não bater com o envelope local que estamos prestes
  // a reutilizar, isso é uma divergência grave entre o que o caller pensa
  // que é o preflight aprovado e o que o banco efetivamente aceitou como tal
  // — o run APPLY recém-aberto é fechado via closeFailed e `apply` NUNCA é
  // chamado.
  if (
    openResult.preflightRunId !== record.runId ||
    openResult.preflightSnapshotHash !== record.snapshotHash
  ) {
    const detail =
      `openRun(APPLY) retornou preflightRunId=${openResult.preflightRunId}/` +
      `preflightSnapshotHash=${openResult.preflightSnapshotHash}, mas o envelope ` +
      `local tem runId=${record.runId}/snapshotHash=${record.snapshotHash} — ` +
      `divergência de preflight entre banco e snapshot local.`;
    await closeFailedSafely(deps.port, runId, detail);
    return { kind: "SNAPSHOT_MISMATCH", runId, runCode, detail };
  }

  try {
    // Reutiliza EXATAMENTE o snapshot aprovado do preflight (Seção 10) — a
    // validação server-side de hash (Query 6105) continua sendo a
    // autoridade final; este caller nunca recalcula nem substitui o hash.
    const applyResult = await deps.port.apply(runId, record.snapshot);
    return {
      kind: "COMPLETED",
      runId,
      runCode,
      applySummary: applyResult.applySummary,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await closeFailedSafely(deps.port, runId, `APPLY_EXCEPTION: ${message}`);
    return { kind: "APPLY_FAILED", runId, runCode, detail: message };
  }
}
