// Referência mínima de Card Variant para a galeria de `/catalogo/cartas`
// (VARIANT-GALLERY-REACT-KEY-01).
//
// A tooltip de variantes da galeria usava o NOME do tipo como chave React.
// Duas Card Variants distintas podem compartilhar o mesmo tipo (ex.: Dark
// Alakazam: "Holográfica" e "Holográfica" + 1ª Edição), o que gerava chaves
// duplicadas. A identidade de uma Card Variant é o seu `card_variant.id`;
// este módulo transporta esse id até a UI sem alterar ordem, quantidade nem
// o texto exibido. A semântica definitiva de rótulos (F1,
// `card-variant-display.ts`) NÃO é aplicada aqui.
//
// F2.1 (VARIANT-DISPLAY-SEMANTICS-01, F2.1-DATA-INTEGRATION-IMPLEMENTATION-01):
// este módulo também integra a F1 aos dados da galeria — ver a seção
// "Estado semântico (F2.1)" abaixo. A regra legada (`mapCartaVariants`) fica
// INALTERADA até os consumidores migrarem (F2.2/F2.3).

import {
  buildCardVariantDisplays,
  findRenderedLabelCollisions,
  getCardVariantLabelParts,
  type CardVariantDisplay,
  type CardVariantDisplayError,
  type CardVariantDisplayErrorCode,
  type CardVariantLabelPart,
} from "./card-variant-display.ts";

export type CartaVariantRawRow = {
  id: string;
  card_variant_type: { name: string; display_order: number } | null;
};

export type CartaVariantRef = {
  /** `card_variant.id` — identidade persistente; usada como chave React. */
  id: string;
  /** Nome do `card_variant_type` — mesmo texto exibido antes desta correção. */
  name: string;
};

/**
 * Mesma regra de antes para `variantNames`: descarta Variants sem tipo
 * embutido e ordena por `card_variant_type.display_order` (sort estável —
 * empates mantêm a ordem recebida, exatamente como antes). Não deduplica.
 */
export function mapCartaVariants(rows: readonly CartaVariantRawRow[] | null | undefined): CartaVariantRef[] {
  return (rows ?? [])
    .filter(
      (variant): variant is CartaVariantRawRow & { card_variant_type: { name: string; display_order: number } } =>
        variant.card_variant_type !== null,
    )
    .sort((a, b) => a.card_variant_type.display_order - b.card_variant_type.display_order)
    .map((variant) => ({ id: variant.id, name: variant.card_variant_type.name }));
}

// ---------------------------------------------------------------------------
// Estado semântico (F2.1) — integração da F1 aos dados da galeria
// ---------------------------------------------------------------------------
//
// Três camadas (F2.1-PLAN-CORRECTION-01, A2):
//   1. linha bruta do PostgREST          → só no servidor
//   2. CartaVariantDisplayState (F1 integral, inclusive admin.legacy) → só no servidor
//   3. CartaVariantViewState (projeção)  → único formato que atravessa para o cliente
//
// Regras (A1): o adaptador só renomeia chaves PRESENTES; não fabrica valores;
// estruturas inválidas seguem intactas para a F1 validar; nenhuma regra de
// validação, ordenação, colisão ou legado é reimplementada aqui.

/** D1 (CLOSED): separador textual explícito. A fronteira entre eixos continua estrutural (partes da F1). */
export const CARD_VARIANT_LABEL_SEPARATOR = " / ";

/** Eixo embutido como devolvido pelo PostgREST. */
export type CartaVariantAxisRaw = { id: string; name: string; display_order: number };

/** Linha `card_variant` completa lida por `getCartasCompletas` (F2.1). Superconjunto de `CartaVariantRawRow`. */
export type CartaVariantSemanticRawRow = {
  id: string;
  card_id: string;
  variant_type_id: string;
  printing_profile_id: string | null;
  edition_context_profile_id: string | null;
  card_variant_type: (CartaVariantAxisRaw & { code: string | null }) | null;
  card_printing_profile: CartaVariantAxisRaw | null;
  card_edition_context_profile: CartaVariantAxisRaw | null;
};

/** A F1 não tem código para exceção inesperada (lacuna A1-L2): sinalizada à parte, sem fabricar código F1. */
export type CartaVariantFault = "UNEXPECTED_EXCEPTION";

/**
 * Estado COMPLETO por carta — exclusivamente no servidor.
 * `rawCount` = linhas `card_variant` recebidas para a carta nesta consulta,
 * antes de qualquer transformação; `null` quando a lista não chegou como
 * array. NÃO é a contagem persistida no banco (gate G-COMP pendente).
 */
export type CartaVariantDisplayState =
  | { status: "NONE"; rawCount: 0 }
  | {
      status: "OK";
      rawCount: number;
      /** Resultado integral da F1, na ordem canônica da F1. */
      variants: CardVariantDisplay[];
      /** variantId → ids com o MESMO texto renderizado com CARD_VARIANT_LABEL_SEPARATOR (só quem colide). */
      renderedLabelCollisions: Record<string, string[]>;
    }
  | {
      status: "ERROR";
      rawCount: number | null;
      /** Erros estruturados da F1, intactos. */
      errors: CardVariantDisplayError[];
      fault: CartaVariantFault | null;
    };

/** Uma variante na projeção de cliente: só o necessário à apresentação (F2.2). */
export type CartaVariantView = {
  /** `card_variant.id` — identidade persistente e chave React. */
  id: string;
  /** Partes do rótulo por eixo, na ordem de eixo (F1 `getCardVariantLabelParts`). */
  parts: CardVariantLabelPart[];
  /** Outras variantes da carta com a mesma tupla de nomes (F1 `admin.labelCollision`). */
  collidesWith: string[];
  /** Outras variantes da carta com o mesmo texto renderizado com " / ". */
  renderedCollidesWith: string[];
};

export type CartaVariantViewError = {
  code: CardVariantDisplayErrorCode;
  index: number | null;
  variantId: string | null;
};

/** Projeção serializada para o cliente (`CartaCompletaRow.variantView`). Sem classificação de legado (D3). */
export type CartaVariantViewState =
  | { status: "NONE"; rawCount: 0 }
  | { status: "OK"; rawCount: number; variants: CartaVariantView[] }
  | { status: "ERROR"; rawCount: number | null; errors: CartaVariantViewError[]; fault: CartaVariantFault | null };

function hasOwn(value: object, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Renomeia só as chaves presentes; não-objeto (null, array, primitivo) segue intacto para a F1 decidir. */
function adaptAxis(value: unknown, withCode: boolean): unknown {
  if (!isPlainObject(value)) return value;
  const out: Record<string, unknown> = {};
  if (hasOwn(value, "id")) out.id = value.id;
  if (hasOwn(value, "name")) out.name = value.name;
  if (hasOwn(value, "display_order")) out.displayOrder = value.display_order;
  if (withCode && hasOwn(value, "code")) out.code = value.code;
  return out;
}

const ROW_KEY_MAP: readonly (readonly [string, string])[] = [
  ["id", "id"],
  ["card_id", "cardId"],
  ["variant_type_id", "variantTypeId"],
  ["printing_profile_id", "printingProfileId"],
  ["edition_context_profile_id", "editionContextProfileId"],
];

/**
 * Adaptador puro linha PostgREST → entrada F1. Não valida: chave ausente
 * continua ausente (a F1 acusa), `null` continua `null`, linha não-objeto
 * segue intacta (a F1 devolve INVALID_RECORD). `cardSetCode === undefined`
 * significa "não fornecido" e não gera a chave.
 */
export function toCardVariantDisplayInput(row: unknown, cardSetCode: unknown): unknown {
  if (!isPlainObject(row)) return row;
  const out: Record<string, unknown> = {};
  for (const [from, to] of ROW_KEY_MAP) {
    if (hasOwn(row, from)) out[to] = row[from];
  }
  if (hasOwn(row, "card_variant_type")) out.finish = adaptAxis(row.card_variant_type, true);
  if (hasOwn(row, "card_printing_profile")) out.printing = adaptAxis(row.card_printing_profile, false);
  if (hasOwn(row, "card_edition_context_profile")) out.editionContext = adaptAxis(row.card_edition_context_profile, false);
  if (cardSetCode !== undefined) out.cardSetCode = cardSetCode;
  return out;
}

/** `card_set.code` como recebido: objeto com a chave → valor sem coerção; qualquer outra forma → não fornecido. */
export function readCardSetCode(cardSet: unknown): unknown {
  return isPlainObject(cardSet) && hasOwn(cardSet, "code") ? cardSet.code : undefined;
}

/**
 * Estado COMPLETO de UMA carta. Nunca lança: exceção inesperada vira
 * ERROR com `fault`, afetando só esta carta. Erro nunca vira NONE e nunca há
 * fallback para a regra legada.
 */
export function buildCartaVariantDisplayState(rows: unknown, cardSetCode: unknown): CartaVariantDisplayState {
  const rawCount = Array.isArray(rows) ? rows.length : null;
  try {
    if (!Array.isArray(rows)) {
      // A própria F1 produz INPUT_NOT_ARRAY.
      const result = buildCardVariantDisplays(rows);
      return { status: "ERROR", rawCount: null, errors: result.ok ? [] : result.errors, fault: null };
    }
    if (rows.length === 0) return { status: "NONE", rawCount: 0 };
    const result = buildCardVariantDisplays(rows.map((row: unknown) => toCardVariantDisplayInput(row, cardSetCode)));
    if (!result.ok) return { status: "ERROR", rawCount: rows.length, errors: result.errors, fault: null };
    const rendered = findRenderedLabelCollisions(result.variants, { separator: CARD_VARIANT_LABEL_SEPARATOR });
    return {
      status: "OK",
      rawCount: rows.length,
      variants: result.variants,
      renderedLabelCollisions: Object.fromEntries(rendered),
    };
  } catch {
    return { status: "ERROR", rawCount, errors: [], fault: "UNEXPECTED_EXCEPTION" };
  }
}

/** Projeção de cliente: identidade, partes do rótulo e colisões; sem legado (D3) e sem mensagens internas. */
export function projectCartaVariantView(state: CartaVariantDisplayState): CartaVariantViewState {
  if (state.status === "NONE") return { status: "NONE", rawCount: 0 };
  if (state.status === "ERROR") {
    return {
      status: "ERROR",
      rawCount: state.rawCount,
      errors: state.errors.map((error) => ({ code: error.code, index: error.index, variantId: error.variantId })),
      fault: state.fault,
    };
  }
  return {
    status: "OK",
    rawCount: state.rawCount,
    variants: state.variants.map((variant) => ({
      id: variant.identity.variantId,
      parts: getCardVariantLabelParts(variant),
      collidesWith: [...variant.admin.labelCollision.collidingVariantIds],
      renderedCollidesWith: [...(state.renderedLabelCollisions[variant.identity.variantId] ?? [])],
    })),
  };
}

/** Estado completo → projeção, para uma carta. Nunca lança (isolamento entre cartas). */
export function buildCartaVariantView(rows: unknown, cardSetCode: unknown): CartaVariantViewState {
  try {
    return projectCartaVariantView(buildCartaVariantDisplayState(rows, cardSetCode));
  } catch {
    return {
      status: "ERROR",
      rawCount: Array.isArray(rows) ? rows.length : null,
      errors: [],
      fault: "UNEXPECTED_EXCEPTION",
    };
  }
}
