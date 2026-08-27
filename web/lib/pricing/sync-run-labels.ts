import type { StateTone } from "@/components/catalogo/state-badge";

/**
 * Vocabulário compartilhado de `pricing_sync_run` (Tipo/Status/Acionador) e
 * formatação de duração — extraído de `historico-execucoes-table.tsx` para
 * ser reusado também pelo Dialog de detalhe (`sync-run-detail-dialog.tsx`),
 * evitando que as duas telas divirjam nos mesmos rótulos com o tempo. Fonte
 * de verdade dos valores possíveis: CHECKs `ck_pricing_sync_run_type`,
 * `ck_pricing_sync_run_status` e `ck_pricing_sync_run_triggered_by` em
 * `pricing_sync_run` (ver `docs/05f-pricing.md`).
 */

// v1.1 (2026-08-23, feedback de Fabrício sobre a tela) — "Refresh de Preços"
// → "Atualização de Preços", mesma troca já aplicada em Saúde das Fontes
// (`saude-fontes-list.tsx`). `SET_DISCOVERY` incluído por completude (não
// aparece na listagem hoje, mas o Dialog de detalhe pode ser aberto a
// partir de qualquer run_type válido no banco).
export const RUN_TYPE_LABEL: Record<string, string> = {
  SET_DISCOVERY: "Descoberta de Set",
  CARD_SYNC: "Descoberta/Matching",
  PRICE_REFRESH: "Atualização de Preços",
  FX_REFRESH: "Câmbio (PTAX)",
};

// COMPLETED_WITH_ERRORS → "Concluída com alertas" (era "com erros"): o badge
// já é vermelho/amarelo pela tonalidade (`STATUS_TONE`), o texto não precisa
// repetir a palavra "erros" para não soar mais grave do que o real. RECEIVED/
// PROCESSING/CANCELLED incluídos por completude — a listagem filtra só
// estados terminais, mas o Dialog de detalhe deve renderizar qualquer status
// válido sem cair no fallback de código cru.
export const STATUS_LABEL: Record<string, string> = {
  RECEIVED: "Recebida",
  PROCESSING: "Em andamento",
  COMPLETED: "Concluída",
  COMPLETED_WITH_ERRORS: "Concluída com alertas",
  FAILED: "Falhou",
  CANCELLED: "Cancelada",
};

export const STATUS_TONE: Record<string, StateTone> = {
  RECEIVED: "muted",
  PROCESSING: "muted",
  COMPLETED: "success",
  COMPLETED_WITH_ERRORS: "warning",
  FAILED: "danger",
  CANCELLED: "muted",
};

/** `triggered_by` — só dois valores possíveis (CHECK `ck_pricing_sync_run_triggered_by`). */
export const TRIGGERED_BY_LABEL: Record<string, string> = {
  MANUAL: "Manual",
  SCHEDULED: "Automático (agendado)",
};

/** Apresentação de `pricing_source_code` — só troca de caixa visual, nunca o código interno. */
export const SOURCE_CODE_LABEL: Record<string, string> = {
  JUSTTCG: "JustTCG",
};

/**
 * Duração humana (2026-08-23, feedback de Fabrício: "não exibir precisão
 * técnica excessiva como 20.016752s"). Abaixo de 60s mostra 1 casa (vírgula
 * PT-BR); a partir de 60s vira "M min SS s" com segundos inteiros e
 * zero-padded, suficiente para leitura operacional sem ruído de
 * microssegundos.
 */
export function formatSyncRunDuration(seconds: number | null): string {
  if (seconds === null) return "—";
  if (seconds < 60) {
    return `${seconds.toFixed(1).replace(".", ",")} s`;
  }
  const totalSeconds = Math.round(seconds);
  const minutes = Math.floor(totalSeconds / 60);
  const rest = totalSeconds % 60;
  return `${minutes} min ${String(rest).padStart(2, "0")} s`;
}

/**
 * Duração em segundos a partir de `started_at`/`finished_at` — usado pelo
 * Dialog de detalhe, cuja RPC (`admin_get_pricing_sync_run_detail`) não
 * recalcula `duration_seconds` no servidor (diferente de
 * `admin_list_pricing_sync_runs`, que já traz o valor pronto). `null`
 * enquanto a execução não tiver `finished_at` (em andamento) ou se
 * `started_at` estiver ausente.
 */
export function computeSyncRunDurationSeconds(startedAt: string | null, finishedAt: string | null): number | null {
  if (!startedAt || !finishedAt) return null;
  const start = new Date(startedAt).getTime();
  const end = new Date(finishedAt).getTime();
  if (Number.isNaN(start) || Number.isNaN(end) || end < start) return null;
  return (end - start) / 1000;
}
