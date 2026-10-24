// Meu acervo — classificação visual do acabamento (MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01).
//
// Função pura: recebe os códigos estáveis do catálogo (card_variant_type.code e
// rarity.code, devolvidos pela 5261/5262) e decide QUAL efeito a galeria e o
// detalhe podem desenhar sem mentir sobre a carta física.
//
// Duas perguntas separadas — acabamento não é raridade:
//   1. Acabamento (código da variante): padrão, holográfica, reversa ou especial.
//   2. Geometria (código da raridade + número): onde fica a arte — janela da
//      ilustração ou carta inteira (full art). Raridade e número nunca decidem
//      se há brilho; só decidem ONDE o brilho pode ser desenhado.
//      Carta secreta do Set (número acima do total impresso, ex.: 133/132):
//      brilho na carta toda, qualquer que seja a raridade (regra de Fabrício,
//      2026-10-24).
//
// Regra conservadora: qualquer dúvida (código desconhecido, acabamento com
// textura própria, geometria sem evidência, códigos ausentes) → sem efeito.
// A carta aparece como é, e o chip textual da variante continua informando.
//
// Protótipo aprovado em 1×: docs/development/prototypes/2026-10-24-holo-variants/.

export type FinishEffect = "none" | "holo-window" | "holo-full" | "reverse-body";

export type FinishNoneReason =
  | "standard" // variante padrão: a carta original, sem brilho adicional
  | "special" // acabamento com textura/geometria própria (Metal, Lenticular, Rainbow…)
  | "unknown-type" // código de variante fora das listas (novo, inativo ou promocional)
  | "unsafe-geometry" // holográfica/reversa, mas a raridade não garante onde fica a arte
  | "missing"; // contrato sem os códigos (frontend antes da 5261/5262)

export type CardFinish =
  | { effect: "none"; reason: FinishNoneReason }
  | { effect: Exclude<FinishEffect, "none"> };

/** Holográficas tradicionais: brilho na arte. Cosmos usa o mesmo lugar (textura aproximada). */
const HOLO_TYPES = new Set(["HOLO", "COSMOS_HOLO"]);

/**
 * Reversas: brilho no corpo, arte fosca. As reversas com padrão (Poké Bola,
 * Energia, Master Ball…) têm o MESMO lugar físico do brilho; a textura do padrão
 * não é reproduzida (o arco-íris é genérico).
 */
const REVERSE_TYPES = new Set([
  "REVERSE_HOLO",
  "POKE_BALL_REVERSE",
  "MASTER_BALL_REVERSE",
  "ENERGY_REVERSE",
  "LOVE_BALL_REVERSE",
  "FRIEND_BALL_REVERSE",
  "QUICK_BALL_REVERSE",
  "DUSK_BALL_REVERSE",
  "ROCKET_REVERSE",
  "COSMOS_REVERSE",
  "TINSEL_REVERSE",
]);

/** Acabamentos especiais: textura ou área própria que o efeito genérico distorceria. */
const SPECIAL_TYPES = new Set([
  "RAINBOW_HOLO",
  "GOLD_HOLO",
  "CRACKED_ICE_HOLO",
  "GALAXY_HOLO",
  "TINSEL_HOLO",
  "MASTER_BALL_HOLO",
  "METAL",
  "METAL_GOLD",
  "LENTICULAR",
]);

/**
 * Raridades com moldura tradicional e janela de ilustração na proporção do
 * protótipo (cartas modernas). Só estas recebem brilho na janela (holo) ou no
 * corpo (reversa).
 */
const WINDOW_RARITIES = new Set(["COMMON", "UNCOMMON", "RARE", "RARE_HOLO", "DOUBLE_RARE", "ACE_SPEC_RARE"]);

/**
 * Raridades cuja arte ocupa a carta inteira (full art): Ilustração Rara,
 * Ilustração Rara Especial, Rara Ultra (EX/GX/V/ex de arte total), Hiper Rara,
 * Mega Rara Hiper e Ultra Rara Shiny. Holo → brilho na carta toda. Reversa
 * full art não existe fisicamente → sem efeito.
 *
 * Fora das duas listas (e por isso sem efeito até haver evidência, salvo carta
 * secreta): PROMO (há promos full art e de moldura comum), PIKACHU_RARE
 * (geometria não confirmada), MEGA_ATTACK_RARE, FUTURISTIC_RARE,
 * CLASSIC_COLLECTION (molduras antigas), SHINY_RARE, RARE_HOLO_V/VMAX/VSTAR/LV_X, RARE_PRIME,
 * RARE_LEGEND, RADIANT_RARE, demais e NONE.
 */
const FULL_ART_RARITIES = new Set([
  "RARE_SECRET",
  "ILLUSTRATION_RARE",
  "SPECIAL_ILLUSTRATION_RARE",
  "ULTRA_RARE",
  "HYPER_RARE",
  "MEGA_HYPER_RARE",
  "SHINY_ULTRA_RARE",
]);

function normalize(code: string | null | undefined): string | null {
  if (typeof code !== "string") return null;
  const trimmed = code.trim().toUpperCase();
  return trimmed === "" ? null : trimmed;
}

/**
 * Carta secreta do Set: número puramente numérico acima do total impresso
 * (133/132, 295/217). Números com prefixo (TG05, SWSH031) ou sem total não
 * contam — sem evidência, a regra não se aplica.
 */
export function isSecretNumber(collectorNumber: string | null | undefined, collectorTotal: number | null | undefined): boolean {
  if (typeof collectorNumber !== "string" || typeof collectorTotal !== "number") return false;
  const trimmed = collectorNumber.trim();
  if (!/^[0-9]+$/.test(trimmed) || !Number.isInteger(collectorTotal) || collectorTotal <= 0) return false;
  return Number(trimmed) > collectorTotal;
}

export type FinishNumbering = { collectorNumber?: string | null; collectorTotal?: number | null };

export function classifyFinish(
  variantTypeCode: string | null | undefined,
  rarityCode: string | null | undefined,
  numbering: FinishNumbering = {},
): CardFinish {
  const type = normalize(variantTypeCode);
  if (type === null) return { effect: "none", reason: "missing" };
  if (type === "STANDARD") return { effect: "none", reason: "standard" };
  if (SPECIAL_TYPES.has(type)) return { effect: "none", reason: "special" };

  const isHolo = HOLO_TYPES.has(type);
  const isReverse = REVERSE_TYPES.has(type);
  if (!isHolo && !isReverse) return { effect: "none", reason: "unknown-type" };

  const rarity = normalize(rarityCode);
  if (rarity === null) return { effect: "none", reason: "missing" };

  if (isHolo) {
    // Secreta prevalece sobre a raridade: a arte ocupa a carta toda.
    if (isSecretNumber(numbering.collectorNumber, numbering.collectorTotal)) return { effect: "holo-full" };
    if (WINDOW_RARITIES.has(rarity)) return { effect: "holo-window" };
    if (FULL_ART_RARITIES.has(rarity)) return { effect: "holo-full" };
    return { effect: "none", reason: "unsafe-geometry" };
  }
  // Reversa de carta secreta não existe fisicamente: sem efeito em vez de chutar.
  if (isSecretNumber(numbering.collectorNumber, numbering.collectorTotal)) return { effect: "none", reason: "unsafe-geometry" };
  return WINDOW_RARITIES.has(rarity) ? { effect: "reverse-body" } : { effect: "none", reason: "unsafe-geometry" };
}

/**
 * Camadas a desenhar para um efeito (consumido por `CardFinishLayers`).
 * `null` = nada sobre a imagem (nem nó no DOM).
 */
export function finishLayerSpec(finish: CardFinish): { area: "window" | "full" | "body"; tone: "holo" | "reverse" } | null {
  switch (finish.effect) {
    case "holo-window":
      return { area: "window", tone: "holo" };
    case "holo-full":
      return { area: "full", tone: "holo" };
    case "reverse-body":
      return { area: "body", tone: "reverse" };
    default:
      return null;
  }
}
