/**
 * Ciclo de vida da coleção — arquivar e reativar (V1-04, incremento 01).
 * Regras puras de apresentação; sem banco, sem React (testável com `node --test`).
 *
 * Contratos LIVE e canônicos, sem mudança:
 * - `5037 archive_collection(p_collection_id)` — ACTIVE → ARCHIVED (C-06, C-30).
 * - `5038 reactivate_collection(p_collection_id)` — ARCHIVED → ACTIVE (C-37).
 * Ambos: SECURITY DEFINER, só o dono (`owner_user_id = auth.uid()`), idempotentes
 * (repetir devolve o estado atual sem novo UPDATE). Coleção alheia ou inexistente
 * recebe a mesma recusa ("collection not found or not owned by caller").
 *
 * Arquivar não toca exemplares, vínculos, fichário nem progresso: a coleção só
 * fica em modo de consulta (C-37) até ser reativada.
 */

import { COLECOES_PATH } from "./colecoes.ts";

/** Parâmetro da Biblioteca que mostra as coleções arquivadas. */
export const ARCHIVED_PARAM = "arquivadas";

type Params = Record<string, string | string[] | undefined>;

export function isArchivedView(params: Params): boolean {
  const raw = params[ARCHIVED_PARAM];
  const value = Array.isArray(raw) ? raw[0] : raw;
  return value === "1";
}

/** Biblioteca de arquivadas, com página opcional. */
export function archivedLibraryHref(page = 1): string {
  return page > 1 ? `${COLECOES_PATH}?${ARCHIVED_PARAM}=1&pagina=${page}` : `${COLECOES_PATH}?${ARCHIVED_PARAM}=1`;
}

/**
 * A leitura da Biblioteca (5182) ordena ativas primeiro e arquivadas depois.
 * Com `p_include_archived = true`, a página N das arquivadas começa logo depois
 * de todas as ativas — paginação no banco, sem ler a lista inteira.
 */
export function archivedOffset(activeTotal: number, page: number, pageSize: number): number {
  const active = Number.isFinite(activeTotal) && activeTotal > 0 ? Math.floor(activeTotal) : 0;
  const index = Number.isFinite(page) && page > 1 ? Math.floor(page) - 1 : 0;
  return active + index * pageSize;
}

/** Arquivadas = todas − ativas (nunca negativo). */
export function archivedCount(allTotal: number, activeTotal: number): number {
  const all = Number.isFinite(allTotal) ? allTotal : 0;
  const active = Number.isFinite(activeTotal) ? activeTotal : 0;
  return Math.max(0, Math.floor(all) - Math.floor(active));
}

export type LifecycleStatus = "ACTIVE" | "ARCHIVED";

export function isLifecycleStatus(value: unknown): value is LifecycleStatus {
  return value === "ACTIVE" || value === "ARCHIVED";
}

export type LifecycleFailure = "not_found" | "not_authenticated" | "invalid" | "unavailable";

/** Classifica pela mensagem estável das 5037/5038; o texto cru nunca chega ao usuário. */
export function classifyLifecycleFailure(code: string | null | undefined, message: string | null | undefined): LifecycleFailure {
  const text = message ?? "";
  if (code === "28000" || code === "42501" || text === "authentication required") return "not_authenticated";
  if (text.startsWith("collection not found")) return "not_found";
  if (code === "22P02" || code === "22023") return "invalid";
  return "unavailable";
}

export function lifecycleFailureMessage(reason: LifecycleFailure, action: "archive" | "reactivate"): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "not_found":
      return "Esta coleção não está disponível para você. Nada foi alterado.";
    case "invalid":
      return "Algo no pedido não está certo. Recarregue a página e tente de novo.";
    default:
      return action === "archive"
        ? "Não foi possível arquivar agora. A coleção continua ativa — tente novamente."
        : "Não foi possível reativar agora. A coleção continua arquivada — tente novamente.";
  }
}

/** O que acontece ao arquivar — mesmo texto na confirmação e no aviso da página. */
export const ARCHIVE_EFFECTS: readonly string[] = [
  "Sai da estante e passa para “Arquivadas”.",
  "Cartas, organização, fichário e progresso ficam preservados — nada é apagado.",
  "Fica em modo de consulta até você reativá-la.",
]
