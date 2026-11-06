/**
 * V1-14 R1-E — relatório "Minha Lista de Desejos" (5º relatório do Meu acervo): planejamento e
 * consulta dos desejos do titular, por Card Set. Sem banco, sem rede.
 *
 * Unidade = o DESEJO (`card_wishlist_entry`, V1-11): variante + condição de idioma (vazio =
 * "qualquer idioma", C-92). Dois idiomas da mesma variante são dois desejos (C-99). Binário: sem
 * quantidade, prioridade, preço-alvo nem ranking (C-210). Nada de coleção nem faltantes (L8).
 *
 * Posse (C-213, derivada pela 5350): quatro estados, preservados. "Pendente" = qualquer estado
 * diferente de "Já no acervo". Variante desativada continua listada e sinalizada (C-214).
 *
 * Referência NM (`get_card_variants_pricing_summary`, 3989, com a Pricing Resilience): UMA por
 * VARIANTE DISTINTA — nunca multiplicada por idiomas nem exemplares; > 0 conta como cotação.
 * Três situações nunca confundidas: cotada · sem cotação (lida, sem valor) · indisponível (bloco
 * de preço que falhou). Agregado com variante indisponível é marcado parcial e bloqueia a
 * impressão. Referência é indicação de mercado — não é gasto, orçamento nem preço-alvo.
 *
 * Ordem: Card Sets por nome (pt-BR), desempate pelo código; dentro do Set, número de colecionador
 * crescente (numérico), preservando a ordem do banco (variante, idioma) nos empates.
 */
import { formatCount, plural } from "./acervo-reports.ts";
import { type WishOwnership, normalizeLanguageCode, ownershipLabel, wishLanguageLabel } from "../wishlist/wishlist.ts";

/** Teto de desejos lidos (páginas de 100 da 5350/5351). */
export const WISHLIST_REPORT_MAX = 5000;
export const WISHLIST_REPORT_PAGE = 100;

export type WishReportEntryInput = {
  entryId: string;
  cardVariantId: string;
  cardId: string;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  variantLabel: string | null;
  variantAvailable: boolean;
  /** `null` = qualquer idioma. */
  languageCode: string | null;
  ownership: WishOwnership;
  /** Frente primária no bucket público `card-front` (pt-BR, senão en). */
  imagePath: string | null;
  wishedAt: string;
};

/** Referência de UMA variante: cotada, sem cotação (lida) ou indisponível (leitura falhou). */
export type WishReference = { kind: "priced"; brl: number } | { kind: "none" } | { kind: "unavailable" };

export type WishReportLine = Omit<WishReportEntryInput, "imagePath"> & {
  reference: WishReference;
  pending: boolean;
  imageUrl: string | null;
};

export type WishReportSet = { code: string; name: string; lines: WishReportLine[] };

export type WishValue = {
  /** Variantes distintas consideradas. */
  variants: number;
  priced: number;
  unavailable: number;
  /** Σ de uma referência por variante cotada; `null` sem nenhuma cotada (nunca R$ 0). */
  totalBrl: number | null;
};

export type WishlistIncompleteReason = "too_large" | "changed" | "prices_unavailable" | null;

export type WishlistReport = {
  entryCount: number;
  pendingCount: number;
  setCount: number;
  variantCount: number;
  /** Variantes distintas com ao menos um desejo pendente. */
  pending: WishValue;
  /** Toda a lista (inclui desejos já satisfeitos). */
  all: WishValue;
  sets: WishReportSet[];
  complete: boolean;
  incompleteReason: WishlistIncompleteReason;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const OWNERSHIP: readonly WishOwnership[] = ["SAME_VARIANT_LANGUAGE", "SAME_VARIANT_OTHER_LANGUAGE", "OTHER_VARIANT", "NONE"];
const str = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v : null);
const id = (v: unknown) => (typeof v === "string" && UUID.test(v) ? v.toLowerCase() : null);

/**
 * Uma página de `get_my_wishlist_filtered` (5350/5351) em modo ESTRITO: qualquer linha fora do
 * contrato (posse desconhecida, idioma inválido, disponibilidade ausente…) invalida a página
 * (`null`) — o relatório nunca reinterpreta nem descarta desejos em silêncio.
 */
export function parseWishlistReportPage(data: unknown): { entries: WishReportEntryInput[]; totalCount: number } | null {
  if (!Array.isArray(data)) return null;
  const entries: WishReportEntryInput[] = [];
  let totalCount = 0;
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row || typeof row !== "object") return null;
    const entryId = id(row.entry_id);
    const cardVariantId = id(row.card_variant_id);
    const cardId = id(row.card_id);
    const cardName = str(row.card_name);
    const setCode = str(row.card_set_code);
    const wishedAt = str(row.wished_at);
    const total = Number(row.total_count);
    const ownership = typeof row.ownership === "string" && (OWNERSHIP as readonly string[]).includes(row.ownership) ? (row.ownership as WishOwnership) : null;
    if (!entryId || !cardVariantId || !cardId || !cardName || !setCode || !wishedAt || !ownership) return null;
    if (!Number.isInteger(total) || total < 0 || typeof row.variant_available !== "boolean") return null;
    let languageCode: string | null = null;
    if (row.language_code !== null && row.language_code !== undefined) {
      languageCode = normalizeLanguageCode(row.language_code);
      if (!languageCode) return null;
    }
    const collectorTotal = row.collector_total === null || row.collector_total === undefined ? null : Number(row.collector_total);
    totalCount = Math.max(totalCount, total);
    entries.push({
      entryId,
      cardVariantId,
      cardId,
      cardName,
      collectorNumber: str(row.collector_number),
      collectorTotal: collectorTotal !== null && Number.isInteger(collectorTotal) && collectorTotal > 0 ? collectorTotal : null,
      cardSetCode: setCode,
      cardSetName: str(row.card_set_name) ?? setCode,
      variantLabel: str(row.variant_label),
      variantAvailable: row.variant_available,
      languageCode,
      ownership,
      imagePath: str(row.image_path_pt) ?? str(row.image_path_en),
      wishedAt,
    });
  }
  return { entries, totalCount };
}

/** Preço lido da 3989 (forma mínima de `VariantPrice`). */
export type WishPriceInput = { hasPricing: boolean; brlAmount: number | null };

/** Referência de uma variante: indisponível > cotada (> 0) > sem cotação. */
export function referenceOf(variantId: string, prices: ReadonlyMap<string, WishPriceInput>, unavailable: ReadonlySet<string>): WishReference {
  const key = variantId.toLowerCase();
  if (unavailable.has(key)) return { kind: "unavailable" };
  const price = prices.get(key);
  if (price && price.hasPricing && price.brlAmount !== null && Number.isFinite(price.brlAmount) && price.brlAmount > 0) {
    return { kind: "priced", brl: price.brlAmount };
  }
  return { kind: "none" };
}

const ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const cents = (brl: number) => Math.round(brl * 100);

function valueOf(references: readonly WishReference[]): WishValue {
  let priced = 0;
  let unavailable = 0;
  let total = 0;
  for (const ref of references) {
    if (ref.kind === "priced") {
      priced += 1;
      total += cents(ref.brl);
    } else if (ref.kind === "unavailable") unavailable += 1;
  }
  return { variants: references.length, priced, unavailable, totalBrl: priced > 0 ? total / 100 : null };
}

export function buildWishlistReport(input: {
  entries: readonly WishReportEntryInput[];
  /** `total_count` do banco (desejos do titular). */
  totalCount: number;
  withinLimit: boolean;
  prices: ReadonlyMap<string, WishPriceInput>;
  /** Variantes cujo bloco de preço falhou (Pricing Resilience). */
  unavailable: ReadonlySet<string>;
  imageUrl?: (path: string) => string | null;
}): WishlistReport {
  const seen = new Set<string>();
  let duplicated = false;
  const groups = new Map<string, WishReportSet>();
  /** Variante → (referência, tem desejo pendente). Uma por variante, nunca por idioma. */
  const variants = new Map<string, { reference: WishReference; pending: boolean }>();
  let pendingCount = 0;
  for (const entry of input.entries) {
    if (seen.has(entry.entryId)) {
      duplicated = true; // a lista mudou entre páginas: uma linha por desejo, relatório incompleto
      continue;
    }
    seen.add(entry.entryId);
    const variantId = entry.cardVariantId.toLowerCase();
    const reference = referenceOf(variantId, input.prices, input.unavailable);
    const pending = entry.ownership !== "SAME_VARIANT_LANGUAGE";
    if (pending) pendingCount += 1;
    const known = variants.get(variantId);
    variants.set(variantId, { reference, pending: (known?.pending ?? false) || pending });
    let set = groups.get(entry.cardSetCode);
    if (!set) {
      set = { code: entry.cardSetCode, name: entry.cardSetName, lines: [] };
      groups.set(entry.cardSetCode, set);
    }
    const { imagePath, ...base } = entry;
    set.lines.push({ ...base, cardVariantId: variantId, reference, pending, imageUrl: imagePath && input.imageUrl ? input.imageUrl(imagePath) : null });
  }
  const sets = [...groups.values()].sort((a, b) => ORDER.compare(a.name, b.name) || ORDER.compare(a.code, b.code));
  // Ordenação estável: empates de número preservam a ordem do banco (variante, idioma).
  for (const set of sets) set.lines.sort((a, b) => ORDER.compare(a.collectorNumber ?? "￿", b.collectorNumber ?? "￿"));
  const all = valueOf([...variants.values()].map((v) => v.reference));
  const pending = valueOf([...variants.values()].filter((v) => v.pending).map((v) => v.reference));
  const entryCount = seen.size;
  const incompleteReason: WishlistIncompleteReason = !input.withinLimit
    ? "too_large"
    : duplicated || entryCount !== input.totalCount
      ? "changed"
      : all.unavailable > 0
        ? "prices_unavailable"
        : null;
  return {
    entryCount,
    pendingCount,
    setCount: sets.length,
    variantCount: variants.size,
    pending,
    all,
    sets,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

export function wishCollectorText(line: Pick<WishReportLine, "collectorNumber" | "collectorTotal">): string {
  if (!line.collectorNumber) return "—";
  return line.collectorTotal ? `${line.collectorNumber}/${line.collectorTotal}` : line.collectorNumber;
}

/** Segunda linha da carta: variante (quando nomeada) · idioma do desejo. */
export function wishVariantText(line: Pick<WishReportLine, "variantLabel" | "languageCode">): string {
  return [line.variantLabel, wishLanguageLabel(line.languageCode)].filter(Boolean).join(" · ");
}

/** Situação no acervo — os quatro estados (C-213); "Não possui" quando não há selo. */
export function wishOwnershipText(ownership: WishOwnership): string {
  return ownershipLabel(ownership) ?? "Não possui";
}

const DATE = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

export function wishedAtText(iso: string): string {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? "—" : DATE.format(date);
}

export function wishlistSummaryLine(report: Pick<WishlistReport, "entryCount" | "setCount">): string {
  return [plural(report.entryCount, "desejo", "desejos"), plural(report.setCount, "Card Set", "Card Sets")].join(" · ");
}

/** "X de Y variantes cotadas" (+ indisponíveis, quando houver). */
export function wishCoverageText(value: WishValue): string {
  const base = `${formatCount(value.priced)} de ${plural(value.variants, "variante cotada", "variantes cotadas")}`;
  return value.unavailable > 0 ? `${base} · ${plural(value.unavailable, "indisponível agora", "indisponíveis agora")}` : base;
}

/**
 * Valor exibido de um agregado: "Sem cotação" sem nenhuma cotada; com variante indisponível, o
 * valor recuperado vem marcado "(parcial)" — nunca apresentado como definitivo.
 */
export function wishValueText(value: WishValue, formatMoney: (brl: number) => string): string {
  if (value.totalBrl === null) return value.unavailable > 0 ? "Indisponível" : "Sem cotação";
  return value.unavailable > 0 ? `${formatMoney(value.totalBrl)} (parcial)` : formatMoney(value.totalBrl);
}

export function wishlistIncompleteText(reason: WishlistIncompleteReason): string | null {
  if (reason === "too_large")
    return `Sua lista tem mais de ${formatCount(WISHLIST_REPORT_MAX)} desejos; esta versão não lista todos e a impressão fica indisponível para não sair incompleta.`;
  if (reason === "changed") return "Sua lista de desejos mudou durante a leitura. Tente novamente; a impressão fica indisponível.";
  if (reason === "prices_unavailable")
    return "Alguns preços de referência não puderam ser carregados agora (marcados “Indisponível”); os totais são parciais e a impressão fica indisponível. Tente novamente em instantes.";
  return null;
}
