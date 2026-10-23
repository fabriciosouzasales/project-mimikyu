/**
 * Fichário Digital — imagem em 2 bolsos (mesclagem horizontal, proposta 5238–5242).
 *
 * Regra pura, espelho de `merge_my_binder_slots_with_image` (SQL). Escopo da
 * primeira versão (aprovado): exatamente 2 bolsos lado a lado, mesma linha,
 * mesma página, ambos livres; a mesclagem só existe com imagem (D7).
 */

import type { BinderPage, BinderSlot, RegionImage } from "./binder.ts";
import { type GapPocket, isFreePocket } from "./binder-insert.ts";
import { type ImageFailure, classifyImageFailure, imageFailureMessage, isSlotImagePath } from "./binder-images.ts";

export type MergeCheck =
  | { ok: true; leftSlotId: string; rightSlotId: string; row: number; leftColumn: number }
  | { ok: false; reason: "NOT_FOUND" | "LAST_COLUMN" | "LEFT_NOT_FREE" | "RIGHT_NOT_FREE" };

/** Pode o bolso `slotId` ocupar também o vizinho da direita? */
export function canMergeRight(pockets: GapPocket[], slotId: string): MergeCheck {
  const left = pockets.find((p) => p.slotId === slotId);
  if (!left) return { ok: false, reason: "NOT_FOUND" };
  const right = pockets.find((p) => p.pageNumber === left.pageNumber && p.row === left.row && p.column === left.column + 1);
  if (!right) return { ok: false, reason: "LAST_COLUMN" };
  if (!isFreePocket(left)) return { ok: false, reason: "LEFT_NOT_FREE" };
  if (!isFreePocket(right)) return { ok: false, reason: "RIGHT_NOT_FREE" };
  return { ok: true, leftSlotId: left.slotId, rightSlotId: right.slotId, row: left.row, leftColumn: left.column };
}

export function mergeCheckMessage(check: MergeCheck): string | null {
  if (check.ok) return null;
  switch (check.reason) {
    case "NOT_FOUND":
      return "Este bolso não está mais neste fichário. Recarregue a página.";
    case "LAST_COLUMN":
      return "Não há bolso à direita deste na mesma linha.";
    case "LEFT_NOT_FREE":
      return "Este bolso precisa estar livre: sem carta, reserva, imagem ou fixação.";
    case "RIGHT_NOT_FREE":
      return "O bolso à direita precisa estar livre: sem carta, reserva, imagem ou fixação.";
  }
}

/** Enquadramento da área larga: dois eixos, 0–100, inteiro. */
export function clampFocal2(x: number, y: number): { focalX: number; focalY: number } {
  const c = (v: number) => (Number.isFinite(v) ? Math.min(100, Math.max(0, Math.round(v))) : 50);
  return { focalX: c(x), focalY: c(y) };
}

/** `object-position` correspondente (CSS). */
export function regionObjectPosition(focalX: number, focalY: number): string {
  const f = clampFocal2(focalX, focalY);
  return `${f.focalX}% ${f.focalY}%`;
}

/** Teclado do enquadramento em 2 eixos: setas (2), PageUp/PageDown (10, vertical), Home = centro. */
export function focal2ForKey(key: string, focalX: number, focalY: number): { focalX: number; focalY: number } | null {
  switch (key) {
    case "ArrowUp":
      return clampFocal2(focalX, focalY - 2);
    case "ArrowDown":
      return clampFocal2(focalX, focalY + 2);
    case "ArrowLeft":
      return clampFocal2(focalX - 2, focalY);
    case "ArrowRight":
      return clampFocal2(focalX + 2, focalY);
    case "PageUp":
      return clampFocal2(focalX, focalY - 10);
    case "PageDown":
      return clampFocal2(focalX, focalY + 10);
    case "Home":
      return { focalX: 50, focalY: 50 };
    default:
      return null;
  }
}

/** Texto acessível do enquadramento. */
export function focal2Label(focalX: number, focalY: number): string {
  const f = clampFocal2(focalX, focalY);
  const h = f.focalX < 40 ? "mais à esquerda" : f.focalX > 60 ? "mais à direita" : "centro";
  const v = f.focalY < 40 ? "mais para o topo" : f.focalY > 60 ? "mais para a base" : "centro";
  return h === "centro" && v === "centro" ? "Centralizada" : `Horizontal: ${h}; vertical: ${v}`;
}

/** Área larga (2 bolsos + vão) em relação ao bolso 8:11, para a prévia. */
export function regionAspect(width: number, gapRatio: number): string {
  return `${8 * width + gapRatio * 8 * (width - 1)} / 11`;
}

// ---------------------------------------------------------------------------
// Bolsos ↔ mesclagens
// ---------------------------------------------------------------------------

/** Adaptador: bolso da 5223 (+ mesclagem) → bolso do planejador. */
export function pocketsFromPages(pages: BinderPage[]): GapPocket[] {
  const out: GapPocket[] = [];
  for (const page of pages) {
    for (const slot of page.slots) {
      out.push({
        slotId: slot.slotId,
        pageNumber: page.pageNumber,
        row: slot.row,
        column: slot.column,
        locked: slot.locked,
        inRegion: Boolean(slot.regionId),
        hasCard: slot.state === "OCCUPIED_MATCH" || slot.state === "OCCUPIED_UNPLANNED" || slot.state === "OCCUPIED_MISMATCH",
        hasReservation: Boolean(slot.expectedCardId),
        hasImage: Boolean(slot.image),
      });
    }
  }
  return out;
}

export type RegionCells = {
  /** Bolso mais à esquerda (âncora) → mesclagem que ele desenha. */
  anchors: Map<string, { region: RegionImage | null; regionId: string; width: number }>;
  /** Bolsos cobertos por uma mesclagem e que não são a âncora (não desenhados). */
  covered: Set<string>;
};

/**
 * Como desenhar uma página com mesclagens. A fonte da cobertura é o
 * `region_id` de cada bolso (5230) — mesmo sem a imagem lida (falha de
 * assinatura, leitura atrasada), a mesclagem continua visível e protegida.
 */
export function regionCells(page: BinderPage): RegionCells {
  const anchors: RegionCells["anchors"] = new Map();
  const covered = new Set<string>();
  const byRegion = new Map<string, BinderSlot[]>();
  for (const slot of page.slots) {
    if (!slot.regionId) continue;
    const list = byRegion.get(slot.regionId) ?? [];
    list.push(slot);
    byRegion.set(slot.regionId, list);
  }
  const images = new Map((page.regions ?? []).map((r) => [r.regionId, r]));
  for (const [regionId, slots] of byRegion) {
    const ordered = [...slots].sort((a, b) => a.row - b.row || a.column - b.column);
    const anchor = ordered[0];
    if (!anchor) continue;
    // Primeira versão: uma linha. Outras formas (não criáveis pela interface) caem para bolsos individuais.
    const sameRow = ordered.every((s) => s.row === anchor.row);
    if (!sameRow) continue;
    anchors.set(anchor.slotId, { region: images.get(regionId) ?? null, regionId, width: ordered.length });
    for (const s of ordered.slice(1)) covered.add(s.slotId);
  }
  return { anchors, covered };
}

// ---------------------------------------------------------------------------
// Contrato das RPCs 5240/5241
// ---------------------------------------------------------------------------

function int(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : Number.NaN;
  return Number.isInteger(n) ? n : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/** Linhas da 5241 por página. `null` = forma inesperada. */
export function parseRegionImages(data: unknown): Map<number, RegionImage[]> | null {
  if (!Array.isArray(data)) return null;
  const byPage = new Map<number, RegionImage[]>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const regionId = str(r.region_id);
    const page = int(r.page_number);
    const row = int(r.top_row);
    const leftColumn = int(r.left_column);
    const height = int(r.height);
    const width = int(r.width);
    const focalX = int(r.focal_x);
    const focalY = int(r.focal_y);
    if (!regionId || page === null || row === null || leftColumn === null || height === null || width === null || focalX === null || focalY === null) return null;
    if (!isSlotImagePath(r.storage_path)) return null;
    const list = byPage.get(page) ?? [];
    list.push({ regionId, row, leftColumn, height, width, path: r.storage_path as string, focalX, focalY, updatedAt: str(r.updated_at), url: null });
    byPage.set(page, list);
  }
  return byPage;
}

export function attachRegionImages(pages: BinderPage[], byPage: Map<number, RegionImage[]>): BinderPage[] {
  return pages.map((page) => {
    const regions = byPage.get(page.pageNumber);
    return regions && regions.length > 0 ? { ...page, regions } : page;
  });
}

export type MergeResult = {
  regionId: string;
  leftSlotId: string;
  rightSlotId: string;
  path: string;
  focalX: number;
  focalY: number;
  operation: "ADDED" | "UNCHANGED";
};

export function parseMergeResult(data: unknown): MergeResult | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  const regionId = str(r.region_id);
  const leftSlotId = str(r.left_slot_id);
  const rightSlotId = str(r.right_slot_id);
  const focalX = int(r.focal_x);
  const focalY = int(r.focal_y);
  if (!regionId || !leftSlotId || !rightSlotId || focalX === null || focalY === null || !isSlotImagePath(r.storage_path)) return null;
  if (r.operation !== "ADDED" && r.operation !== "UNCHANGED") return null;
  return { regionId, leftSlotId, rightSlotId, path: r.storage_path as string, focalX, focalY, operation: r.operation };
}

export type RegionImageResult = { regionId: string; path: string; focalX: number; focalY: number; operation: "REPLACED" | "UNCHANGED"; previousPath: string | null };

export function parseRegionImageResult(data: unknown): RegionImageResult | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  const regionId = str(r.region_id);
  const focalX = int(r.focal_x);
  const focalY = int(r.focal_y);
  const previous = r.previous_path ?? null;
  if (!regionId || focalX === null || focalY === null || !isSlotImagePath(r.storage_path)) return null;
  if (r.operation !== "REPLACED" && r.operation !== "UNCHANGED") return null;
  if (previous !== null && !isSlotImagePath(previous)) return null;
  if (r.operation === "REPLACED" && previous === null) return null;
  return { regionId, path: r.storage_path as string, focalX, focalY, operation: r.operation, previousPath: r.operation === "REPLACED" ? (previous as string) : null };
}

export function parseRegionFocusResult(data: unknown): { regionId: string; focalX: number; focalY: number } | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  const regionId = str(r.region_id);
  const focalX = int(r.focal_x);
  const focalY = int(r.focal_y);
  return regionId && focalX !== null && focalY !== null ? { regionId, focalX, focalY } : null;
}

export function parseSeparateResult(data: unknown): { regionId: string; outcome: "SEPARATED" | "ALREADY_ABSENT"; previousPath: string | null } | null {
  const r = (Array.isArray(data) ? data[0] : null) as Record<string, unknown> | null | undefined;
  if (!r || typeof r !== "object") return null;
  const regionId = str(r.region_id);
  const previous = r.previous_path ?? null;
  if (!regionId || (r.outcome !== "SEPARATED" && r.outcome !== "ALREADY_ABSENT")) return null;
  if (previous !== null && !isSlotImagePath(previous)) return null;
  return { regionId, outcome: r.outcome, previousPath: previous as string | null };
}

export type RegionFailure = ImageFailure | "slots_not_free" | "no_neighbor" | "region_missing" | "unavailable";

/** Erros das RPCs 5240 → motivo; o que for comum à imagem de bolso reaproveita o classificador da 5233. */
export function classifyRegionFailure(code: string | null | undefined, message: string | null | undefined): RegionFailure {
  const text = (message ?? "").toUpperCase();
  // Função ainda não aplicada no banco (PostgREST / Postgres).
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (text.includes("SLOTS_NOT_FREE") || text.includes("REGION_SLOTS_NOT_FREE")) return "slots_not_free";
  if (text.includes("NO_RIGHT_NEIGHBOR")) return "no_neighbor";
  if (text.includes("REGION_NOT_FOUND")) return "region_missing";
  return classifyImageFailure(code, message);
}

export function isDefiniteRegionRefusal(reason: RegionFailure): boolean {
  return reason !== "unknown";
}

export function regionFailureMessage(reason: RegionFailure): string {
  switch (reason) {
    case "slots_not_free":
      return "Os 2 bolsos precisam estar livres: sem carta, reserva, imagem ou fixação. Algo mudou — confira a página.";
    case "no_neighbor":
      return "Não há bolso à direita deste na mesma linha.";
    case "region_missing":
      return "Essa imagem em 2 bolsos não está mais neste fichário. Recarregue a página.";
    case "unavailable":
      return "A imagem em 2 bolsos ainda não está disponível.";
    default:
      return imageFailureMessage(reason);
  }
}
