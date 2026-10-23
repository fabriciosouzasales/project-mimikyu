/**
 * Fichário Digital — "Inserir espaço" (P2-BINDER-LAYOUT-CUSTOMIZATION, proposta 5243).
 *
 * Regra pura, espelho exato de `binder_gap_chain` (SQL). Serve à prévia e aos
 * testes; a autoridade é sempre o banco, que refaz o cálculo sob trava e
 * recusa se o plano mudou (token).
 *
 * Modelo (decisões D1 ajustada, D2–D4 aprovadas):
 *   - ordem de leitura: página → linha → coluna, atravessando páginas;
 *   - bolso LIVRE: sem carta, sem reserva, sem imagem, não fixado, fora de mesclagem;
 *   - BARREIRA: bolso fixado ou dentro de mesclagem. O deslocamento NÃO a atravessa;
 *   - inserir antes do bolso X empurra X..(primeiro livre − 1) uma posição;
 *     o bolso inteiro anda junto (carta + reserva + imagem);
 *   - se aparecer uma barreira antes do primeiro livre → bloqueado (com a barreira);
 *   - se não houver livre até o fim → precisa de página nova (confirmação explícita);
 *   - limite operacional: linhas movidas (cartas + reservas + imagens) ≤ 500,
 *     o mesmo teto por chamada já validado no fichário (5129/5130/5133, 5820).
 */

export const GAP_ROW_LIMIT = 500;

export type GapPocket = {
  slotId: string;
  pageNumber: number;
  row: number;
  column: number;
  locked: boolean;
  inRegion: boolean;
  hasCard: boolean;
  hasReservation: boolean;
  hasImage: boolean;
};

export type GapMove = { from: string; to: string };

export type GapBarrier = { slotId: string; pageNumber: number; row: number; column: number; kind: "LOCKED" | "REGION" };

export type GapSummary = {
  /** Bolsos que andam uma posição (ordem de leitura). */
  moves: GapMove[];
  cards: number;
  reservations: number;
  images: number;
  /** Linhas escritas no banco (cartas + reservas + imagens). */
  rows: number;
  /** Páginas tocadas, em ordem crescente (inclui a da posição livre final). */
  pages: number[];
};

export type GapPlan =
  | { kind: "NOT_FOUND" }
  | { kind: "ALREADY_FREE" }
  | { kind: "AT_BARRIER"; barrier: GapBarrier }
  | ({ kind: "BLOCKED"; barrier: GapBarrier } & GapSummary)
  | ({ kind: "OVER_LIMIT"; limit: number } & GapSummary)
  | ({ kind: "SAME_PAGE"; targetSlotId: string } & GapSummary)
  | ({ kind: "CROSS_PAGE"; targetSlotId: string } & GapSummary)
  /** Nenhum livre até o fim: o último bolso vai para a 1ª posição de uma página nova. */
  | ({ kind: "NEEDS_PAGE" } & GapSummary);

export function isBarrier(p: GapPocket): boolean {
  return p.locked || p.inRegion;
}

export function isFreePocket(p: GapPocket): boolean {
  return !isBarrier(p) && !p.hasCard && !p.hasReservation && !p.hasImage;
}

/** Acesso por índice que falha alto (o índice vem sempre de uma busca válida). */
function at<T>(list: readonly T[], i: number): T {
  const v = list[i];
  if (v === undefined) throw new Error(`índice fora da faixa: ${i}`);
  return v;
}

function barrierOf(p: GapPocket): GapBarrier {
  return { slotId: p.slotId, pageNumber: p.pageNumber, row: p.row, column: p.column, kind: p.locked ? "LOCKED" : "REGION" };
}

/** Ordem de leitura canônica (a mesma do `row_number()` do SQL). */
export function readingOrder(pockets: GapPocket[]): GapPocket[] {
  return [...pockets].sort((a, b) => a.pageNumber - b.pageNumber || a.row - b.row || a.column - b.column);
}

function summarize(chain: GapPocket[], destinations: string[], extraPage: number | null): GapSummary {
  const moves: GapMove[] = [];
  let cards = 0;
  let reservations = 0;
  let images = 0;
  const pages = new Set<number>();
  chain.forEach((p, i) => {
    moves.push({ from: p.slotId, to: at(destinations, i) });
    if (p.hasCard) cards += 1;
    if (p.hasReservation) reservations += 1;
    if (p.hasImage) images += 1;
    pages.add(p.pageNumber);
  });
  if (extraPage !== null) pages.add(extraPage);
  return { moves, cards, reservations, images, rows: cards + reservations + images, pages: [...pages].sort((a, b) => a - b) };
}

export function planInsertGap(pockets: GapPocket[], atSlotId: string, limit: number = GAP_ROW_LIMIT): GapPlan {
  const ordered = readingOrder(pockets);
  const start = ordered.findIndex((p) => p.slotId === atSlotId);
  if (start < 0) return { kind: "NOT_FOUND" };
  const first = at(ordered, start);
  if (isBarrier(first)) return { kind: "AT_BARRIER", barrier: barrierOf(first) };
  if (isFreePocket(first)) return { kind: "ALREADY_FREE" };

  let stop = -1;
  for (let i = start + 1; i < ordered.length; i += 1) {
    const p = at(ordered, i);
    if (isBarrier(p) || isFreePocket(p)) {
      stop = i;
      break;
    }
  }

  if (stop >= 0 && isBarrier(at(ordered, stop))) {
    const chain = ordered.slice(start, stop);
    return { kind: "BLOCKED", barrier: barrierOf(at(ordered, stop)), ...summarize(chain, chain.map(() => ""), null) };
  }

  if (stop < 0) {
    const chain = ordered.slice(start);
    const lastPage = at(ordered, ordered.length - 1).pageNumber;
    // Destinos: o próximo da cadeia; o último vai para "nova página, 1ª posição".
    const dest = chain.map((_, i) => (i + 1 < chain.length ? at(chain, i + 1).slotId : "NEW_PAGE_FIRST_SLOT"));
    const s = summarize(chain, dest, lastPage + 1);
    if (s.rows > limit) return { kind: "OVER_LIMIT", limit, ...s };
    return { kind: "NEEDS_PAGE", ...s };
  }

  const chain = ordered.slice(start, stop);
  const target = at(ordered, stop);
  const dest = chain.map((_, i) => at(ordered, start + i + 1).slotId);
  const s = summarize(chain, dest, target.pageNumber);
  if (s.rows > limit) return { kind: "OVER_LIMIT", limit, ...s };
  return target.pageNumber === first.pageNumber
    ? { kind: "SAME_PAGE", targetSlotId: target.slotId, ...s }
    : { kind: "CROSS_PAGE", targetSlotId: target.slotId, ...s };
}

/**
 * Aplica um plano executável a uma cópia (simula o banco). O deslocamento é
 * feito do fim para o começo: cada destino já está livre quando recebe o
 * conteúdo — sem estado intermediário inválido e sem restrição diferida.
 */
export function applyInsertGap(pockets: GapPocket[], plan: GapPlan, newPage?: GapPocket[]): GapPocket[] {
  if (plan.kind !== "SAME_PAGE" && plan.kind !== "CROSS_PAGE" && plan.kind !== "NEEDS_PAGE") {
    throw new Error(`plano não executável: ${plan.kind}`);
  }
  const all = [...pockets, ...(plan.kind === "NEEDS_PAGE" ? (newPage ?? []) : [])].map((p) => ({ ...p }));
  const byId = new Map(all.map((p) => [p.slotId, p]));
  const firstOfNewPage = plan.kind === "NEEDS_PAGE" ? readingOrder(newPage ?? [])[0]?.slotId : undefined;
  for (let i = plan.moves.length - 1; i >= 0; i -= 1) {
    const { from, to } = at(plan.moves, i);
    const toId = to === "NEW_PAGE_FIRST_SLOT" ? firstOfNewPage : to;
    const src = byId.get(from);
    const dst = toId ? byId.get(toId) : undefined;
    if (!src || !dst) throw new Error("destino ausente");
    if (!isFreePocket(dst)) throw new Error(`destino ocupado: ${dst.slotId}`);
    dst.hasCard = src.hasCard;
    dst.hasReservation = src.hasReservation;
    dst.hasImage = src.hasImage;
    src.hasCard = false;
    src.hasReservation = false;
    src.hasImage = false;
  }
  return all;
}

/**
 * Desfazer (D4): fecha o espaço aberto em `gapSlotId`, puxando de volta
 * (gap+1 .. end) uma posição. Válido só se o estado ainda é o deixado pela
 * inserção — no banco, conferido pelo token de desfazer.
 */
export function planCloseGap(pockets: GapPocket[], gapSlotId: string, endSlotId: string): GapMove[] | null {
  const ordered = readingOrder(pockets);
  const g = ordered.findIndex((p) => p.slotId === gapSlotId);
  const e = ordered.findIndex((p) => p.slotId === endSlotId);
  if (g < 0 || e <= g) return null;
  if (!isFreePocket(at(ordered, g))) return null;
  for (let i = g + 1; i <= e; i += 1) if (isBarrier(at(ordered, i))) return null;
  const moves: GapMove[] = [];
  for (let i = g + 1; i <= e; i += 1) moves.push({ from: at(ordered, i).slotId, to: at(ordered, i - 1).slotId });
  return moves;
}

export function applyCloseGap(pockets: GapPocket[], moves: GapMove[]): GapPocket[] {
  const all = pockets.map((p) => ({ ...p }));
  const byId = new Map(all.map((p) => [p.slotId, p]));
  for (const m of moves) {
    const src = byId.get(m.from)!;
    const dst = byId.get(m.to)!;
    if (!isFreePocket(dst)) throw new Error(`destino ocupado: ${dst.slotId}`);
    dst.hasCard = src.hasCard;
    dst.hasReservation = src.hasReservation;
    dst.hasImage = src.hasImage;
    src.hasCard = false;
    src.hasReservation = false;
    src.hasImage = false;
  }
  return all;
}

/** Texto da prévia (linguagem do colecionador; nunca ids). */
export function gapPreviewMessage(plan: GapPlan): string {
  const moved = (n: number) => (n === 1 ? "1 bolso avança" : `${n} bolsos avançam`);
  const where = (b: GapBarrier) => `página ${b.pageNumber}, linha ${b.row}, coluna ${b.column}`;
  switch (plan.kind) {
    case "NOT_FOUND":
      return "Este bolso não está mais neste fichário. Recarregue a página.";
    case "ALREADY_FREE":
      return "Este bolso já está livre.";
    case "AT_BARRIER":
      return plan.barrier.kind === "LOCKED"
        ? "Este bolso está fixado. Desafixe-o para abrir espaço aqui."
        : "Este bolso faz parte de uma imagem em 2 bolsos.";
    case "BLOCKED":
      return plan.barrier.kind === "LOCKED"
        ? `Não há bolso livre antes do bolso fixado (${where(plan.barrier)}). Desafixe-o ou libere um bolso antes dele.`
        : `Não há bolso livre antes da imagem em 2 bolsos (${where(plan.barrier)}). Libere um bolso antes dela.`;
    case "OVER_LIMIT":
      return `Abrir espaço aqui moveria muitos itens de uma vez (${plan.rows}). Abra o espaço mais adiante ou libere um bolso mais próximo.`;
    case "SAME_PAGE":
      return `${moved(plan.moves.length)} uma posição nesta página.`;
    case "CROSS_PAGE":
      return `${moved(plan.moves.length)} uma posição, nas páginas ${plan.pages.join(", ")}.`;
    case "NEEDS_PAGE":
      return `Não há bolso livre até o fim do fichário. Adicionar uma página ao final? ${moved(plan.moves.length)} uma posição (páginas ${plan.pages.join(", ")}).`;
  }
}

// ---------------------------------------------------------------------------
// Contrato das RPCs 5243 (o banco é a autoridade; a prévia vem dele)
// ---------------------------------------------------------------------------

export type GapOutcome = "NOT_FOUND" | "ALREADY_FREE" | "AT_BARRIER" | "BLOCKED" | "OVER_LIMIT" | "SAME_PAGE" | "CROSS_PAGE" | "NEEDS_PAGE";

const GAP_OUTCOMES = new Set<GapOutcome>(["NOT_FOUND", "ALREADY_FREE", "AT_BARRIER", "BLOCKED", "OVER_LIMIT", "SAME_PAGE", "CROSS_PAGE", "NEEDS_PAGE"]);

export type GapPreview = {
  outcome: GapOutcome;
  movedPockets: number;
  movedCards: number;
  movedReserves: number;
  movedImages: number;
  rowsMoved: number;
  rowLimit: number;
  pages: number[];
  targetSlotId: string | null;
  barrier: GapBarrier | null;
  planToken: string | null;
};

function gInt(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : Number.NaN;
  return Number.isInteger(n) ? n : null;
}

function gStr(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

const PLAN_TOKEN = /^g1:[0-9a-f]{64}$/;
const UNDO_TOKEN = /^u1:[0-9a-f]{64}$/;

export function parseGapPreview(data: unknown): GapPreview | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  const outcome = r.outcome as GapOutcome;
  if (!GAP_OUTCOMES.has(outcome)) return null;
  const pagesRaw = Array.isArray(r.pages) ? r.pages.map(gInt) : [];
  if (pagesRaw.some((p) => p === null)) return null;
  const barrierSlot = gStr(r.barrier_slot_id);
  const kind = r.barrier_kind;
  const barrier: GapBarrier | null =
    barrierSlot && (kind === "LOCKED" || kind === "REGION")
      ? { slotId: barrierSlot, kind, pageNumber: gInt(r.barrier_page) ?? 0, row: gInt(r.barrier_row) ?? 0, column: gInt(r.barrier_column) ?? 0 }
      : null;
  const planToken = gStr(r.plan_token);
  if (planToken !== null && !PLAN_TOKEN.test(planToken)) return null;
  const executable = outcome === "SAME_PAGE" || outcome === "CROSS_PAGE" || outcome === "NEEDS_PAGE";
  if (executable && !planToken) return null;
  return {
    outcome,
    movedPockets: gInt(r.moved_pockets) ?? 0,
    movedCards: gInt(r.moved_cards) ?? 0,
    movedReserves: gInt(r.moved_reserves) ?? 0,
    movedImages: gInt(r.moved_images) ?? 0,
    rowsMoved: gInt(r.rows_moved) ?? 0,
    rowLimit: gInt(r.row_limit) ?? GAP_ROW_LIMIT,
    pages: pagesRaw as number[],
    targetSlotId: gStr(r.target_slot_id),
    barrier,
    planToken,
  };
}

export type GapInsertResult = {
  outcome: "INSERTED" | "ALREADY_FREE";
  gapSlotId: string;
  endSlotId: string | null;
  addedPageId: string | null;
  movedPockets: number;
  pages: number[];
  undoToken: string | null;
};

export function parseGapInsert(data: unknown): GapInsertResult | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  if (r.outcome !== "INSERTED" && r.outcome !== "ALREADY_FREE") return null;
  const gapSlotId = gStr(r.gap_slot_id);
  if (!gapSlotId) return null;
  const undoToken = gStr(r.undo_token);
  if (r.outcome === "INSERTED" && (!undoToken || !UNDO_TOKEN.test(undoToken) || !gStr(r.end_slot_id))) return null;
  const pages = Array.isArray(r.pages) ? r.pages.map(gInt).filter((p): p is number => p !== null) : [];
  return {
    outcome: r.outcome,
    gapSlotId,
    endSlotId: gStr(r.end_slot_id),
    addedPageId: gStr(r.added_page_id),
    movedPockets: gInt(r.moved_pockets) ?? 0,
    pages,
    undoToken,
  };
}

export function parseGapClose(data: unknown): { movedPockets: number; pageRemoved: boolean } | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object" || r.outcome !== "CLOSED") return null;
  return { movedPockets: gInt(r.moved_pockets) ?? 0, pageRemoved: r.page_removed === true };
}

export function isUndoToken(value: unknown): value is string {
  return typeof value === "string" && UNDO_TOKEN.test(value);
}

export function isPlanToken(value: unknown): value is string {
  return typeof value === "string" && PLAN_TOKEN.test(value);
}

export type GapFailure =
  | "plan_changed"
  | "undo_expired"
  | "blocked"
  | "over_limit"
  | "confirm_cross_page"
  | "confirm_add_page"
  | "archived"
  | "not_found"
  | "lock_busy"
  | "not_authenticated"
  | "unavailable"
  | "invalid"
  | "unknown";

export function classifyGapFailure(code: string | null | undefined, message: string | null | undefined, hint?: string | null): GapFailure {
  const text = (message ?? "").toUpperCase();
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (code === "55P03") return "lock_busy";
  if (code === "28000" || text.includes("NOT_AUTHENTICATED")) return "not_authenticated";
  if (text.includes("GAP_PLAN_CHANGED")) return "plan_changed";
  if (text.includes("GAP_UNDO_EXPIRED")) return "undo_expired";
  if (text.includes("GAP_BLOCKED")) return "blocked";
  if (text.includes("GAP_OVER_LIMIT")) return "over_limit";
  if (text.includes("GAP_CONFIRMATION_REQUIRED")) return (hint ?? "").toUpperCase().includes("ADD_PAGE") ? "confirm_add_page" : "confirm_cross_page";
  if (text.includes("COLLECTION_ARCHIVED")) return "archived";
  if (text.includes("NOT_FOUND") || code === "P0002") return "not_found";
  if (text.includes("INVALID_ARGUMENT") || code === "22023") return "invalid";
  return "unknown";
}

export function gapFailureMessage(reason: GapFailure): string {
  switch (reason) {
    case "plan_changed":
      return "O fichário mudou desde a prévia. Veja a prévia de novo antes de abrir o espaço.";
    case "undo_expired":
      return "Não dá mais para desfazer: o fichário mudou depois que o espaço foi aberto.";
    case "blocked":
      return "Um bolso fixado ou uma imagem em 2 bolsos está no caminho. Nada foi movido.";
    case "over_limit":
      return "Isso moveria itens demais de uma vez. Nada foi movido.";
    case "confirm_cross_page":
    case "confirm_add_page":
      return "Confirme a prévia para continuar.";
    case "archived":
      return "A coleção está arquivada: o fichário pode ser visto, mas não organizado.";
    case "not_found":
      return "Esse bolso não está mais neste fichário. Recarregue a página.";
    case "lock_busy":
      return "O fichário está sendo atualizado agora. Tente de novo em instantes.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "unavailable":
      return "Inserir espaço ainda não está disponível.";
    case "invalid":
      return "Não foi possível abrir o espaço com esses dados.";
    case "unknown":
      return "Não conseguimos confirmar o resultado. O fichário foi relido — confira antes de tentar de novo.";
  }
}

/** Texto da prévia vinda do banco (mesma linguagem da regra local). */
export function gapServerPreviewMessage(preview: GapPreview): string {
  const pockets = preview.movedPockets;
  switch (preview.outcome) {
    case "NOT_FOUND":
    case "ALREADY_FREE":
    case "AT_BARRIER":
      return gapPreviewMessage(preview.outcome === "AT_BARRIER" && preview.barrier ? { kind: "AT_BARRIER", barrier: preview.barrier } : { kind: preview.outcome as "NOT_FOUND" | "ALREADY_FREE" });
    case "BLOCKED":
      return preview.barrier
        ? gapPreviewMessage({ kind: "BLOCKED", barrier: preview.barrier, moves: [], cards: 0, reservations: 0, images: 0, rows: 0, pages: [] })
        : "Um bolso fixado ou uma imagem em 2 bolsos está no caminho.";
    case "OVER_LIMIT":
      return `Abrir espaço aqui moveria ${preview.rowsMoved} itens de uma vez — o limite é ${preview.rowLimit}. Abra o espaço mais adiante ou libere um bolso mais próximo.`;
    case "SAME_PAGE":
      return `${pockets === 1 ? "1 bolso avança" : `${pockets} bolsos avançam`} uma posição nesta página.`;
    case "CROSS_PAGE":
      return `${pockets === 1 ? "1 bolso avança" : `${pockets} bolsos avançam`} uma posição, nas páginas ${preview.pages.join(", ")}.`;
    case "NEEDS_PAGE":
      return `Não há bolso livre até o fim do fichário. Para abrir o espaço, uma página nova é adicionada ao final e ${pockets === 1 ? "1 bolso avança" : `${pockets} bolsos avançam`} (páginas ${preview.pages.join(", ")}).`;
  }
}
