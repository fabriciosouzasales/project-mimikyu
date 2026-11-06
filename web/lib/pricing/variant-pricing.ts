/**
 * Preço NM por variante para a Collection (V1-09) — regras puras.
 *
 * Fonte única: `get_card_variants_pricing_summary(uuid[])` (3983, CONFIRMADO
 * EXECUTADO). Este módulo não lê banco nem rede: interpreta as linhas da 3983
 * e decide o que a interface pode afirmar.
 *
 * Contrato (docs/05f-pricing.md, seção "Preço NM na Collection (V1-09)"):
 *  - `VARIANT`: preço da própria variante do exemplar, com data de observação.
 *  - `CARD_FALLBACK`: preço geral da carta (hierarquia de impressão / manual).
 *    Pode ser de OUTRA impressão — nunca é apresentado como preço da variante.
 *    A 3983 não devolve data nesse caminho: o estado é "data desconhecida",
 *    nunca "atualizado".
 *  - sem preço: nada na grade; o detalhe informa (D5). Câmbio ausente tem
 *    mensagem própria.
 *  - D1: mais de 14 dias desde a observação = desatualizado.
 *  - D4: exemplar em idioma diferente do inglês = referência internacional.
 *  - Preço sempre unitário (nunca multiplicado por cópias).
 */

export const PRICE_STALE_AFTER_DAYS = 14;
/** Teto da 3983 por chamada (`VARIANT_PRICING_SUMMARY_TOO_MANY_IDS`). */
export const VARIANT_PRICING_MAX_IDS = 100;
/**
 * C2 — limites do endpoint em lote antes de qualquer trabalho proporcional à
 * entrada: até 400 entradas brutas (repetições colapsam para ≤ 100 distintas)
 * e até 20 000 bytes de corpo (400 UUIDs entre aspas ≈ 15,6 KB + estrutura).
 */
export const VARIANT_PRICING_MAX_RAW_ENTRIES = 400;
export const VARIANT_PRICING_MAX_BODY_BYTES = 20_000;

const DAY_MS = 86_400_000;
/**
 * C3 — tolerância para `observed_at` à frente do relógio local. O contrato de
 * Pricing não define regra própria (nenhum CHECK em `pricing_observation`).
 * Regra mínima e determinística: até 24 h no futuro é tratado como "agora"
 * (cobre qualquer fuso, de −12 h a +14 h, datas sem hora gravadas em UTC e
 * pequena divergência de relógio entre servidor, banco e navegador). Além
 * disso a data é inconsistente: estado "data desconhecida", nunca atualizado.
 * Nenhum dado é alterado — só a classificação.
 */
export const FUTURE_TOLERANCE_MS = DAY_MS;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type VariantPriceBasis = "VARIANT" | "CARD_FALLBACK";
export type VariantPriceOrigin = "AUTOMATIC" | "MANUAL";
export type VariantFxStatus = "CONVERTED" | "FX_RATE_UNAVAILABLE";

export type VariantPrice = {
  cardVariantId: string;
  hasPricing: boolean;
  brlAmount: number | null;
  sourceAmount: number | null;
  sourceCurrency: string | null;
  fxStatus: VariantFxStatus | null;
  /** Rótulo cru da fonte (ex.: "Reverse Holofoil"); tradução em `printingLabelPt`. */
  printingLabel: string | null;
  basis: VariantPriceBasis | null;
  origin: VariantPriceOrigin | null;
  observedAt: string | null;
};

export type PriceState = "FRESH" | "STALE" | "DATE_UNKNOWN" | "FX_UNAVAILABLE" | "UNAVAILABLE";

// ---------------------------------------------------------------------------
// Leitura da 3983
// ---------------------------------------------------------------------------

function num(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * Linhas da 3983 → mapa por `card_variant_id`. `null` = formato inesperado
 * (tratado como leitura indisponível, nunca como "sem preço").
 */
export function parseVariantPrices(rows: unknown): Map<string, VariantPrice> | null {
  if (!Array.isArray(rows)) return null;
  const out = new Map<string, VariantPrice>();
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const id = typeof r.card_variant_id === "string" && UUID.test(r.card_variant_id) ? r.card_variant_id.toLowerCase() : null;
    if (!id || typeof r.has_pricing !== "boolean") return null;
    const fx = r.fx_status === "CONVERTED" || r.fx_status === "FX_RATE_UNAVAILABLE" ? r.fx_status : null;
    const basis = r.price_basis === "VARIANT" || r.price_basis === "CARD_FALLBACK" ? r.price_basis : null;
    const origin = r.price_origin === "AUTOMATIC" || r.price_origin === "MANUAL" ? r.price_origin : null;
    out.set(id, {
      cardVariantId: id,
      hasPricing: r.has_pricing,
      brlAmount: num(r.brl_amount),
      sourceAmount: num(r.source_amount),
      sourceCurrency: str(r.source_currency),
      fxStatus: fx,
      printingLabel: str(r.printing_label),
      basis,
      origin,
      observedAt: str(r.observed_at),
    });
  }
  return out;
}

/**
 * Ids válidos, sem repetição, em blocos de até 100 (cardinalidade da 3983).
 * Ordem preservada (primeira ocorrência), ids normalizados em minúsculas.
 */
export function chunkVariantIds(ids: readonly (string | null | undefined)[], size = VARIANT_PRICING_MAX_IDS): string[][] {
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const id of ids) {
    if (typeof id !== "string" || !UUID.test(id)) continue;
    const key = id.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(key);
  }
  const chunks: string[][] = [];
  for (let i = 0; i < unique.length; i += size) chunks.push(unique.slice(i, i + size));
  return chunks;
}

export function isValidVariantId(id: unknown): id is string {
  return typeof id === "string" && UUID.test(id);
}

/**
 * Validação do corpo do endpoint em lote (`/api/colecoes/precos`):
 * lista não vazia, só UUIDs, até 100 ids distintos.
 */
export function validateVariantIdsBody(
  body: unknown,
):
  | { ok: true; ids: string[] }
  | { ok: false; error: "missing_variant_ids" | "invalid_variant_id" | "too_many_variant_ids" | "too_many_entries" } {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, error: "missing_variant_ids" };
  const raw = (body as { variantIds?: unknown }).variantIds;
  if (!Array.isArray(raw) || raw.length === 0) return { ok: false, error: "missing_variant_ids" };
  // Teto bruto ANTES de percorrer a lista.
  if (raw.length > VARIANT_PRICING_MAX_RAW_ENTRIES) return { ok: false, error: "too_many_entries" };
  if (!raw.every(isValidVariantId)) return { ok: false, error: "invalid_variant_id" };
  const ids = [...new Set(raw.map((id) => id.toLowerCase()))];
  if (ids.length > VARIANT_PRICING_MAX_IDS) return { ok: false, error: "too_many_variant_ids" };
  return { ok: true, ids };
}

// ---------------------------------------------------------------------------
// Estados
// ---------------------------------------------------------------------------

/** Dias inteiros desde a observação (`null` = data ausente ou inválida). Observação no futuro conta como 0. */
export function daysSince(observedAt: string | null, now: number): number | null {
  if (!observedAt) return null;
  const at = Date.parse(observedAt);
  if (!Number.isFinite(at)) return null;
  if (at - now > FUTURE_TOLERANCE_MS) return null;
  return Math.max(0, Math.floor((now - at) / DAY_MS));
}

/** Por que a data não serve para afirmar recência: ausente/ilegível ou além da tolerância futura. */
export function observedDateIssue(observedAt: string | null, now: number): "missing" | "future" | null {
  if (!observedAt) return "missing";
  const at = Date.parse(observedAt);
  if (!Number.isFinite(at)) return "missing";
  if (at - now > FUTURE_TOLERANCE_MS) return "future";
  return null;
}

/**
 * Os cinco estados do contrato. Data desconhecida nunca vira "atualizado";
 * sem preço nunca vira zero.
 */
export function priceState(price: VariantPrice | null | undefined, now: number): PriceState {
  if (!price || !price.hasPricing || price.brlAmount === null) {
    return price?.fxStatus === "FX_RATE_UNAVAILABLE" ? "FX_UNAVAILABLE" : "UNAVAILABLE";
  }
  const age = daysSince(price.observedAt, now);
  if (age === null) return "DATE_UNKNOWN";
  return age > PRICE_STALE_AFTER_DAYS ? "STALE" : "FRESH";
}

/** A grade só mostra indicador quando existe valor (D5). */
export function isPriceShown(state: PriceState): boolean {
  return state === "FRESH" || state === "STALE" || state === "DATE_UNKNOWN";
}

/** Indicador atenuado: preço antigo ou sem data confirmada. */
export function isPriceMuted(state: PriceState): boolean {
  return state === "STALE" || state === "DATE_UNKNOWN";
}

/**
 * C1 — sinal não cromático de cada estado exibível: forma do ícone + texto
 * curto (tooltip e leitor de tela). O valor mantém a cor de texto principal
 * em todos os estados (contraste do Catálogo); a cor nunca é o único sinal.
 */
export type PriceIndicator = { glyph: "current" | "stale" | "unknown"; label: string };

export function priceIndicator(state: PriceState): PriceIndicator | null {
  if (state === "FRESH") return { glyph: "current", label: "Preço de referência NM atualizado" };
  if (state === "STALE") return { glyph: "stale", label: "Preço de referência NM desatualizado" };
  if (state === "DATE_UNKNOWN") return { glyph: "unknown", label: "Preço de referência NM sem data confirmada" };
  return null;
}

/** D4: o preço da fonte é de mercado internacional (inglês); outro idioma = só referência. */
export function isInternationalReference(languageCode: string | null | undefined): boolean {
  if (!languageCode) return false;
  return !/^en(-|$)/i.test(languageCode.trim());
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

/** Rótulos PT-BR das impressões da fonte (mesmo dicionário do Catálogo Editorial). */
export const PRINTING_LABEL_PT: Readonly<Record<string, string>> = {
  Normal: "Normal",
  Holofoil: "Holográfica",
  "Reverse Holofoil": "Holográfica reversa",
  Unlimited: "Ilimitada",
  "Unlimited Holofoil": "Ilimitada Holográfica",
  "1st Edition": "1ª Edição",
  "1st Edition Holofoil": "1ª Edição Holográfica",
};

export function printingLabelPt(label: string | null): string | null {
  if (!label) return null;
  return PRINTING_LABEL_PT[label] ?? label;
}

const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const usd = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "USD" });
// Fuso fixo: o mesmo texto no servidor e no navegador (sem divergência de hidratação).
const dateFmt = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

export function formatBrl(value: number): string {
  return brl.format(value);
}

export function formatSourceAmount(amount: number | null, currency: string | null): string | null {
  if (amount === null || !currency) return null;
  if (currency === "USD") return usd.format(amount);
  if (currency === "BRL") return brl.format(amount);
  try {
    return new Intl.NumberFormat("pt-BR", { style: "currency", currency }).format(amount);
  } catch {
    return null;
  }
}

export function formatObservedDate(observedAt: string | null): string | null {
  if (!observedAt) return null;
  const at = Date.parse(observedAt);
  return Number.isFinite(at) ? dateFmt.format(at) : null;
}

export type PriceDetail = {
  state: PriceState;
  /** Valor em R$ (só quando há preço). */
  amount: string | null;
  /** "NM · Holográfica reversa" (variante) ou "NM · preço geral da carta". */
  headline: string;
  /** Linhas rótulo/valor (fonte, data, valor original, câmbio). */
  facts: { label: string; value: string }[];
  /** Avisos curtos, em ordem: fallback, manual, desatualizado, idioma. */
  notes: string[];
};

/**
 * Conteúdo do detalhe (popover e painel do exemplar). `variantName` é o nome
 * do acabamento no NOSSO catálogo — usado só quando o preço é da variante.
 */
export function priceDetail(
  price: VariantPrice | null | undefined,
  context: { variantName: string | null; languageCode: string | null; now: number },
): PriceDetail {
  const state = priceState(price, context.now);
  const international = isInternationalReference(context.languageCode);
  if (!price || !isPriceShown(state)) {
    return {
      state,
      amount: null,
      headline:
        state === "FX_UNAVAILABLE"
          ? "Preço de referência indisponível no momento (sem cotação do câmbio)."
          : "Sem preço de referência para esta carta.",
      facts: [],
      notes: [],
    };
  }

  const fallback = price.basis !== "VARIANT";
  const facts: { label: string; value: string }[] = [{ label: "Fonte", value: price.origin === "MANUAL" ? "Curadoria MMKYU" : "JustTCG" }];
  const date = formatObservedDate(price.observedAt);
  facts.push({ label: "Data de referência", value: date ?? "Não disponível" });
  const original = formatSourceAmount(price.sourceAmount, price.sourceCurrency);
  if (original && price.sourceCurrency !== "BRL") facts.push({ label: "Valor original", value: original });
  if (price.sourceCurrency === "USD") facts.push({ label: "Câmbio", value: "PTAX (Banco Central)" });

  const notes: string[] = [];
  if (fallback) {
    const printing = printingLabelPt(price.printingLabel);
    notes.push(
      printing
        ? `Preço geral da carta (impressão ${printing}). Esta variante ainda não tem preço próprio — pode não corresponder ao seu exemplar.`
        : "Preço geral da carta. Esta variante ainda não tem preço próprio — pode não corresponder ao seu exemplar.",
    );
  }
  if (price.origin === "MANUAL") notes.push("Valor definido manualmente pela curadoria.");
  if (state === "STALE") {
    const age = daysSince(price.observedAt, context.now);
    notes.push(`Atualizado há ${age} dias — pode estar desatualizado.`);
  }
  if (state === "DATE_UNKNOWN") {
    notes.push(
      observedDateIssue(price.observedAt, context.now) === "future"
        ? "Data de referência posterior à data atual: não é possível confirmar que o preço é recente."
        : "Data de referência não disponível: não é possível confirmar que o preço é recente.",
    );
  }
  if (international) notes.push("Referência do mercado internacional — o preço não é específico do idioma deste exemplar.");

  const variant = !fallback && context.variantName ? context.variantName : null;
  return {
    state,
    amount: formatBrl(price.brlAmount as number),
    headline: variant ? `NM · ${variant}` : fallback ? "NM · preço geral da carta" : "NM",
    facts,
    notes,
  };
}

/** Texto para leitores de tela (nome acessível do cartão ou do bolso). */
export function priceAccessibleText(price: VariantPrice | null | undefined, now: number): string | null {
  const state = priceState(price, now);
  if (!price || !isPriceShown(state) || price.brlAmount === null) return null;
  const parts = [`referência NM ${formatBrl(price.brlAmount)}`];
  if (price.basis !== "VARIANT") parts.push("preço geral da carta");
  if (state === "STALE") parts.push("desatualizado");
  if (state === "DATE_UNKNOWN") parts.push("sem data confirmada");
  return parts.join(", ");
}

/**
 * Estado de uma leitura de preços em lote (PRICING TIMEOUT CORRECTION-01):
 * `complete` = tudo lido; `partial` = parte dos blocos falhou; `unavailable` =
 * nada lido. Falha de leitura nunca é "sem cotação" nem preço zero.
 */
export type VariantPricesStatus = "complete" | "partial" | "unavailable";

/**
 * Aviso discreto da página quando a leitura não foi completa; `null` quando
 * não há nada a avisar (leitura completa ou sem leitura de preço).
 */
export function priceReadNoticeText(status: VariantPricesStatus | null | undefined): string | null {
  if (status === "partial") {
    return "Alguns preços de referência não puderam ser carregados agora. Cartas sem etiqueta podem ter cotação — recarregue a página em instantes.";
  }
  if (status === "unavailable") return "Os preços de referência não puderam ser carregados agora. Recarregue a página em instantes.";
  return null;
}

/**
 * Estado agregado de várias leituras da mesma grade (página do servidor +
 * "Mostrar mais"): nada a avisar só se todas foram completas; todas
 * indisponíveis = indisponível; qualquer outra mistura = parcial.
 */
export function combinePriceIssue(current: VariantPricesStatus | null, next: VariantPricesStatus): VariantPricesStatus | null {
  if (current === null && next === "complete") return null;
  if (current === "unavailable" && next === "unavailable") return "unavailable";
  return "partial";
}

export const NM_REFERENCE_NOTE = "Referência de mercado em condição Near Mint. Não reflete o estado do seu exemplar.";

export type CompactPriceDetail = {
  state: PriceState;
  /** Valor em R$; `null` = sem preço (ver `message`). */
  amount: string | null;
  /** Uma linha quando não há preço (D5: o detalhe informa, nunca R$ 0). */
  message: string | null;
  /** Acabamento só quando o preço é da própria variante; senão `null`. */
  finish: string | null;
  /** Preço geral da carta (CARD_FALLBACK) — sempre visível, nunca só no detalhe. */
  generalCardPrice: boolean;
  source: string | null;
  /** Atualização — visível na camada principal, com o estado (D1/C3). */
  freshness: { tone: "current" | "stale" | "unknown"; text: string } | null;
  /** Camada secundária (sob demanda): rótulo/valor e avisos completos. */
  facts: { label: string; value: string }[];
  notes: string[];
};

/**
 * Composição compacta do preço no detalhe do exemplar (V1-09, REFINEMENT-06).
 * Primário: valor, acabamento (ou "preço geral da carta"), fonte e
 * atualização. Secundário: data completa, valor original, câmbio, nota NM,
 * fallback, origem manual, data inconsistente e limitação de idioma — o mesmo
 * conteúdo de `priceDetail`, reorganizado; nenhum estado crítico fica oculto.
 */
export function compactPriceDetail(
  price: VariantPrice | null | undefined,
  context: { variantName: string | null; languageCode: string | null; now: number },
): CompactPriceDetail {
  const detail = priceDetail(price, context);
  if (detail.amount === null || !price) {
    return { state: detail.state, amount: null, message: detail.headline, finish: null, generalCardPrice: false, source: null, freshness: null, facts: [], notes: [] };
  }
  const generalCardPrice = price.basis !== "VARIANT";
  const date = formatObservedDate(price.observedAt);
  let freshness: NonNullable<CompactPriceDetail["freshness"]>;
  if (detail.state === "STALE") {
    freshness = { tone: "stale", text: `Desatualizado · há ${daysSince(price.observedAt, context.now)} dias` };
  } else if (detail.state === "DATE_UNKNOWN") {
    freshness = {
      tone: "unknown",
      text: observedDateIssue(price.observedAt, context.now) === "future" ? "Data inconsistente" : "Data não disponível",
    };
  } else {
    freshness = { tone: "current", text: `Atualizado em ${date}` };
  }
  return {
    state: detail.state,
    amount: detail.amount,
    message: null,
    finish: !generalCardPrice && context.variantName ? context.variantName : null,
    generalCardPrice,
    source: detail.facts.find((fact) => fact.label === "Fonte")?.value ?? null,
    freshness,
    facts: detail.facts.filter((fact) => fact.label !== "Fonte"),
    notes: [NM_REFERENCE_NOTE, ...detail.notes],
  };
}
