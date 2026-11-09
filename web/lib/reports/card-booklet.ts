/**
 * V1-14 — "Caderno de Cartas da Coleção" (D7 §4p). Núcleo PURO do caderno editorial do Card Set:
 *
 *  - Universo = o Card Set INTEIRO do catálogo (cartas ativas, `search_cards` com o código do Set da
 *    coleção autorizada), na ordem de coleção — independente da posse e, no Master Set, também as
 *    cartas sem posição no objetivo (acabamentos não adotados) aparecem, sem marca.
 *  - Posse = contexto SECUNDÁRIO, vinda das posições canônicas do Checklist (5169 ou 5189/5198,
 *    `is_satisfied` do banco). Nenhuma regra de completude aqui.
 *  - Raridade = da carta (catálogo 5355 para nome/símbolo/ordem da legenda).
 *  - Paginação editorial determinística: capa (1), abertura (2), páginas de cartas (20 por página,
 *    5 × 4 no A4), encerramento. Números de página calculados aqui (iguais na tela e no papel).
 *  - Conferência: catálogo completo e sem repetição; posições completas; toda posição pertence a uma
 *    carta do catálogo; Σ posições e satisfeitas = resumo canônico (5332); toda carta com raridade
 *    do catálogo. Divergência → incompleto com motivo (impressão bloqueada); nada é inventado.
 */
import { progressPercentText } from "../colecoes/colecoes.ts";
import { type ChecklistKind, type ChecklistRow, checklistFinishCode, checklistFinishLegend } from "./collection-checklist.ts";
import type { RarityCatalogInput } from "./distribution.ts";

export const CARD_BOOKLET_TITLE = "Caderno de Cartas";
/** Cartas por página impressa (5 colunas × 4 linhas no A4). */
export const BOOKLET_CARDS_PER_PAGE = 20;
export const BOOKLET_PAGE_SIZE = 60;
export const BOOKLET_MAX_PAGES = 20;
/** Páginas antes das cartas: capa e abertura. */
export const BOOKLET_FRONT_PAGES = 2;

const N = new Intl.NumberFormat("pt-BR");

// ---------------------------------------------------------------------------------------------
// Catálogo do Set (`search_cards`)
// ---------------------------------------------------------------------------------------------

export type BookletCatalogCard = {
  cardId: string;
  number: string;
  total: number | null;
  name: string;
  rarityCode: string;
  imagePath: string | null;
};

export type BookletCatalogPage = { rows: Array<BookletCatalogCard & { setCode: string }>; total: number };

export type BookletCatalogRead =
  | { status: "ok"; cards: BookletCatalogCard[] }
  | { status: "incomplete"; cards: BookletCatalogCard[]; reason: "pages" | "too_large" }
  | { status: "error" };

const str = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v : null);

/** Uma página da `search_cards` → linhas validadas; `null` = fora da forma esperada. */
export function parseCatalogPage(data: unknown): BookletCatalogPage | null {
  if (!Array.isArray(data)) return null;
  const rows: BookletCatalogPage["rows"] = [];
  let total: number | null = data.length === 0 ? 0 : null;
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const t = typeof r.total_count === "string" ? Number(r.total_count) : r.total_count;
    const cardId = str(r.card_id);
    const rarityCode = str(r.rarity_code);
    const setCode = str(r.card_set_code);
    if (!cardId || !rarityCode || !setCode || typeof r.card_name !== "string" || typeof r.collector_number !== "string") return null;
    if (typeof t !== "number" || !Number.isInteger(t) || t < 0 || (total !== null && t !== total)) return null;
    total = t;
    const collectorTotal = typeof r.collector_total === "number" && Number.isInteger(r.collector_total) ? r.collector_total : null;
    rows.push({
      cardId: cardId.toLowerCase(),
      number: r.collector_number,
      total: collectorTotal,
      name: r.card_name,
      rarityCode,
      imagePath: str(r.image_path_pt) ?? str(r.image_path_en),
      setCode,
    });
  }
  return { rows, total: total ?? 0 };
}

/** Junta as páginas: só o Set da coleção, sem carta repetida, total estável, conjunto fechado. Ordem preservada. */
export function mergeCatalogPages(setCode: string, pages: ReadonlyArray<BookletCatalogPage | null>, expectedPages: number): BookletCatalogRead {
  const first = pages[0];
  if (!first) return { status: "error" };
  const cards: BookletCatalogCard[] = [];
  const seen = new Set<string>();
  let consistent = pages.length === expectedPages;
  const wanted = setCode.toLocaleLowerCase("en");
  for (const page of pages) {
    if (!page || page.total !== first.total) {
      consistent = false;
      continue;
    }
    for (const { setCode: rowSet, ...card } of page.rows) {
      if (rowSet.toLocaleLowerCase("en") !== wanted || seen.has(card.cardId)) {
        consistent = false;
        continue;
      }
      seen.add(card.cardId);
      cards.push(card);
    }
  }
  if (cards.length !== first.total) consistent = false;
  return consistent ? { status: "ok", cards } : { status: "incomplete", cards, reason: "pages" };
}

// ---------------------------------------------------------------------------------------------
// Caderno
// ---------------------------------------------------------------------------------------------

export type BookletFinish = { key: string; label: string; code: string | null; owned: boolean };

/** Posse da carta: obtida (todas as posições satisfeitas), parcial (Master Set), falta, ou fora do objetivo. */
export type BookletCardStatus = "owned" | "partial" | "missing" | "outside";

export type BookletRarity = { code: string; name: string; symbolCode: string | null };

export type BookletCard = {
  cardId: string;
  number: string;
  total: number | null;
  name: string;
  rarity: BookletRarity | null;
  /** Frente da carta: a da leitura da coleção (idioma da coleção) ou, sem posição, a do catálogo. */
  imagePath: string | null;
  status: BookletCardStatus;
  /** Master Set: posições da carta por acabamento (vazio no Set padrão). */
  finishes: BookletFinish[];
};

export type BookletPage = {
  /** Número da página no caderno (capa = 1, abertura = 2). */
  pageNumber: number;
  cards: BookletCard[];
  /** Faixa de números da página ("001" → "020"). */
  firstNumber: string;
  lastNumber: string;
};

export type BookletIncomplete = "catalog" | "positions" | "catalog_unavailable" | "rarity_unknown" | "position_outside_catalog" | "duplicate_position" | "total_mismatch";

export type BookletReport = {
  kind: ChecklistKind;
  cards: BookletCard[];
  pages: BookletPage[];
  /** Número da página de encerramento. */
  closingPage: number;
  totalPages: number;
  /** Totais canônicos (5332). */
  positions: number;
  satisfied: number;
  missing: number;
  percentText: string;
  /** Cartas por posse (secundário). */
  ownedCards: number;
  partialCards: number;
  outsideCards: number;
  /** Raridades presentes no Set, na ordem do catálogo, com a contagem de cartas. */
  rarities: Array<BookletRarity & { cards: number }>;
  /** Siglas de acabamento presentes (Master Set). */
  finishLegend: Array<{ code: string; label: string }>;
  complete: boolean;
  incompleteReason: BookletIncomplete | null;
};

export type BookletInput = {
  kind: ChecklistKind;
  catalog: BookletCatalogRead;
  positions: readonly ChecklistRow[];
  positionsComplete: boolean;
  rarityCatalog: RarityCatalogInput;
  canonical: { total: number; satisfied: number };
};

function statusOf(kind: ChecklistKind, rows: readonly ChecklistRow[]): BookletCardStatus {
  if (rows.length === 0) return "outside";
  const owned = rows.filter((r) => r.owned).length;
  if (owned === rows.length) return "owned";
  if (owned > 0 && kind === "MASTER_SET") return "partial";
  return "missing";
}

export function buildCardBooklet(input: BookletInput): BookletReport {
  const { kind, catalog, positions, rarityCatalog, canonical } = input;
  const catalogCards = catalog.status === "error" ? [] : catalog.cards;
  const rarityByCode = new Map(rarityCatalog.status === "ok" ? rarityCatalog.entries.map((e) => [e.code, e]) : []);

  // Posições por carta (ordem do banco preservada dentro da carta).
  const byCard = new Map<string, ChecklistRow[]>();
  const seenKeys = new Set<string>();
  let duplicate = false;
  for (const row of positions) {
    if (seenKeys.has(row.key)) {
      duplicate = true;
      continue;
    }
    seenKeys.add(row.key);
    const id = row.cardId ?? row.key.split(":")[0]!;
    const list = byCard.get(id);
    if (list) list.push(row);
    else byCard.set(id, [row]);
  }
  const catalogIds = new Set(catalogCards.map((c) => c.cardId));
  const outsideCatalog = [...byCard.keys()].some((id) => !catalogIds.has(id));

  let unknownRarity = false;
  const rarityCounts = new Map<string, number>();
  const cards: BookletCard[] = catalogCards.map((c) => {
    const rows = byCard.get(c.cardId) ?? [];
    const entry = rarityByCode.get(c.rarityCode);
    if (!entry) unknownRarity = true;
    rarityCounts.set(c.rarityCode, (rarityCounts.get(c.rarityCode) ?? 0) + 1);
    return {
      cardId: c.cardId,
      number: c.number,
      total: c.total,
      name: c.name,
      rarity: entry ? { code: entry.code, name: entry.name, symbolCode: entry.symbolCode } : { code: c.rarityCode, name: c.rarityCode, symbolCode: null },
      imagePath: rows.find((r) => r.imagePath)?.imagePath ?? c.imagePath,
      status: statusOf(kind, rows),
      finishes:
        kind === "MASTER_SET"
          ? rows.map((r) => {
              const label = r.finish ?? "Acabamento";
              return { key: r.key, label, code: checklistFinishCode(label)?.code ?? null, owned: r.owned };
            })
          : [],
    };
  });

  const pages: BookletPage[] = [];
  for (let i = 0; i < cards.length; i += BOOKLET_CARDS_PER_PAGE) {
    const slice = cards.slice(i, i + BOOKLET_CARDS_PER_PAGE);
    pages.push({ pageNumber: BOOKLET_FRONT_PAGES + 1 + pages.length, cards: slice, firstNumber: slice[0]!.number, lastNumber: slice[slice.length - 1]!.number });
  }
  const closingPage = BOOKLET_FRONT_PAGES + pages.length + 1;

  const rarities = [...rarityCounts.entries()]
    .map(([code, count]) => {
      const e = rarityByCode.get(code);
      return { code, name: e?.name ?? code, symbolCode: e?.symbolCode ?? null, cards: count, order: e?.displayOrder ?? Number.MAX_SAFE_INTEGER };
    })
    .sort((a, b) => a.order - b.order || (a.code < b.code ? -1 : 1))
    .map(({ order: _order, ...r }) => r);

  const finishLegend = checklistFinishLegend(cards.flatMap((c) => c.finishes.map((f) => f.label)));

  const sumPositions = [...byCard.values()].reduce((s, rows) => s + rows.length, 0);
  const sumSatisfied = [...byCard.values()].reduce((s, rows) => s + rows.filter((r) => r.owned).length, 0);
  const incompleteReason: BookletIncomplete | null =
    catalog.status !== "ok"
      ? "catalog"
      : !input.positionsComplete
        ? "positions"
        : rarityCatalog.status !== "ok"
          ? "catalog_unavailable"
          : duplicate
            ? "duplicate_position"
            : outsideCatalog
              ? "position_outside_catalog"
              : unknownRarity
                ? "rarity_unknown"
                : sumPositions !== canonical.total || sumSatisfied !== canonical.satisfied
                  ? "total_mismatch"
                  : null;

  return {
    kind,
    cards,
    pages,
    closingPage,
    totalPages: closingPage,
    positions: canonical.total,
    satisfied: canonical.satisfied,
    missing: Math.max(0, canonical.total - canonical.satisfied),
    percentText: progressPercentText(canonical.satisfied, canonical.total),
    ownedCards: cards.filter((c) => c.status === "owned").length,
    partialCards: cards.filter((c) => c.status === "partial").length,
    outsideCards: cards.filter((c) => c.status === "outside").length,
    rarities,
    finishLegend,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------------------------
// Textos (pt-BR)
// ---------------------------------------------------------------------------------------------

/** "001/295" (ou só o número quando o total não é conhecido). */
export function bookletNumberText(card: Pick<BookletCard, "number" | "total">): string {
  if (card.total === null) return card.number;
  const width = String(card.total).length;
  const padded = /^\d+$/.test(card.number) ? card.number.padStart(width, "0") : card.number;
  return `${padded}/${String(card.total).padStart(width, "0")}`;
}

export function bookletStatusText(card: Pick<BookletCard, "status" | "finishes">): string {
  const master = card.finishes.length > 0;
  switch (card.status) {
    case "owned":
      return master ? "Completa" : "Obtida";
    case "partial": {
      const owned = card.finishes.filter((f) => f.owned).length;
      return `${N.format(owned)} de ${N.format(card.finishes.length)} acabamentos atendidos`;
    }
    case "missing":
      return master ? "Pendente" : "Falta";
    case "outside":
      return "Fora do objetivo";
  }
}

/** Texto acessível do cartão da carta. */
export function bookletCardAria(card: BookletCard): string {
  const parts = [`${card.name}, ${bookletNumberText(card)}`];
  if (card.rarity) parts.push(card.rarity.name);
  parts.push(bookletStatusText(card));
  if (card.finishes.length > 0) parts.push(card.finishes.map((f) => `${f.label}: ${f.owned ? "atendido" : "pendente"}`).join("; "));
  return parts.join(" · ");
}

export function bookletRangeText(page: Pick<BookletPage, "firstNumber" | "lastNumber">): string {
  return page.firstNumber === page.lastNumber ? `Carta ${page.firstNumber}` : `Cartas ${page.firstNumber}–${page.lastNumber}`;
}

export function bookletIncompleteText(reason: BookletIncomplete | null): string | null {
  switch (reason) {
    case null:
      return null;
    case "catalog":
      return "Caderno incompleto: nem todas as cartas do Set puderam ser lidas agora. Tente novamente; nada foi alterado.";
    case "positions":
      return "Caderno incompleto: as posições da coleção não puderam ser lidas por inteiro agora. Tente novamente; nada foi alterado.";
    case "catalog_unavailable":
      return "Caderno incompleto: o catálogo de raridades não pôde ser lido agora. Tente novamente; nada foi alterado.";
    case "rarity_unknown":
      return "Caderno incompleto: há carta com raridade que não consta do catálogo vigente.";
    case "position_outside_catalog":
      return "Caderno incompleto: há posição da coleção cuja carta não está entre as cartas ativas do Set.";
    case "duplicate_position":
      return "Caderno incompleto: a leitura das posições devolveu uma posição repetida.";
    case "total_mismatch":
      return "Caderno incompleto: as posições lidas não conferem com o resumo da coleção.";
  }
}

export const CARD_BOOKLET_INTRO =
  "Todas as cartas do Set, na ordem da coleção, como num guia de colecionador. A posse aparece como um detalhe discreto em cada carta — o protagonista é o Set.";
