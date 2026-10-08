// Project Mimikyu — Semântica de exibição de Card Variant (VARIANT-DISPLAY-SEMANTICS-01 / F1).
//
// Módulo puro e sem dependências (nem React, nem Supabase, nem rede): recebe
// linhas de `card_variant` já lidas e devolve um modelo determinístico para
// apresentação. Nenhuma consulta, nenhum efeito colateral, nenhum cache.
//
// POR QUE EXISTE. A galeria e os relatórios do catálogo mostram só o nome do
// acabamento (`card_variant_type.name`). Duas variantes distintas da mesma
// carta — mesmo acabamento, tiragem ou Edition Context diferentes — aparecem
// como duas "Holográfica" indistinguíveis. Depois da 2213 isso ficou mais
// frequente: as variantes legadas decompostas passaram a compartilhar o
// acabamento com variantes irmãs, diferindo só pelo Edition Context.
//
// DECISÕES APROVADAS (Fabrício, VARIANT-DISPLAY-SEMANTICS-01):
//   M1 — modelo estruturado sem perda: identidade, apresentação e metadados
//        administrativos separados. Eixo opcional ausente = `null`.
//   M2 — legado só por EVIDÊNCIA POSITIVA. Código desconhecido nunca vira
//        legado; sem evidência suficiente o estado é INDETERMINATE.
//   M3 — rótulos iguais não implicam variantes iguais: detectar colisão,
//        nunca deduplicar, nunca acrescentar UUID ao rótulo.
//
// INVARIANTES (testados em card-variant-display.test.ts):
//   I1 identidade = card_variant.id          I5 ordem: finish → printing → EC → id
//   I2 nenhum id de eixo se perde            I6 colisão detectada, nunca removida
//   I3 N entradas → N saídas                 I7 separador sempre parâmetro; sem parse reverso
//   I4 NULL legítimo não gera texto          I8 fail-closed: dado inválido → erro, sem fallback
//
// Unicidade que sustenta o modelo: `uq_card_variant_identity` (Query 2209),
// UNIQUE (card_id, variant_type_id, printing_profile_id,
// edition_context_profile_id) NULLS NOT DISTINCT. `name` NÃO é único em
// nenhuma das três entidades de eixo (150, 2166, 2204) — por isso M3.

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------

/** Eixo embutido como lido do banco (FK escalar resolvida). */
export type CardVariantAxisInput = {
  id: string;
  name: string;
  displayOrder: number;
};

/** Acabamento: além do eixo, o `code` do Variant Type — usado SÓ pela classificação de legado. */
export type CardVariantFinishInput = CardVariantAxisInput & {
  code: string | null;
};

/**
 * Uma linha de `card_variant`. As colunas FK vêm junto com os embeds para que
 * a coerência seja verificável: FK preenchida com embed ausente (por exemplo,
 * RLS ocultando a linha do eixo) é erro, nunca "sem eixo".
 */
export type CardVariantDisplayInput = {
  id: string;
  cardId: string;
  variantTypeId: string;
  printingProfileId: string | null;
  editionContextProfileId: string | null;
  finish: CardVariantFinishInput | null;
  printing: CardVariantAxisInput | null;
  editionContext: CardVariantAxisInput | null;
  /** `card_set.code` — só necessário para Variant Types cuja natureza depende do Set (SET_LOGO_*). */
  cardSetCode?: string | null;
};

// ---------------------------------------------------------------------------
// Saída
// ---------------------------------------------------------------------------

/** Identidade: só ids e relacionamentos. Espelha os 4 componentes de uq_card_variant_identity. */
export type CardVariantIdentity = {
  variantId: string;
  cardId: string;
  variantTypeId: string;
  printingProfileId: string | null;
  editionContextProfileId: string | null;
};

/** Apresentação de um eixo: só nome e ordem. Nunca usada como identidade. */
export type CardVariantAxisPresentation = {
  name: string;
  displayOrder: number;
};

export type CardVariantPresentation = {
  finish: CardVariantAxisPresentation;
  printing: CardVariantAxisPresentation | null;
  editionContext: CardVariantAxisPresentation | null;
};

/**
 * LEGACY_PROVEN exige prova INDIVIDUAL — pertença da própria `card_variant.id`
 * a uma população adjudicada e congelada (HOLD 107 de H1, Pricing 80 de H6).
 * Essas listas de ids NÃO estão versionadas no repositório nem chegam a esta
 * biblioteca; código de tipo é evidência sobre o TIPO e sobre uma população
 * histórica, nunca sobre uma variante individual (F1-CORRECTION-01). Por isso,
 * em F1, nenhuma entrada produz LEGACY_PROVEN: o estado existe no contrato
 * para quando a evidência individual for fornecida por fonte verificável (F0).
 */
export type CardVariantLegacyStatus =
  | "LEGACY_PROVEN"
  | "NOT_IDENTIFIED_AS_LEGACY"
  | "INDETERMINATE";

export type CardVariantLegacyReason =
  /**
   * code é tipo contaminado adjudicado cuja população histórica AINDA existe
   * (HOLD-MANIFEST H1 / H6), mas a pertença desta variante a ela não é provável
   * sem a lista congelada de ids.
   */
  | "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN"
  /**
   * code é tipo contaminado adjudicado cuja população foi decomposta INTEIRA
   * pela 2213 (READY_UNCONDITIONED residual 0). Uma ocorrência atual está, por
   * definição, fora da população provada — p.ex. tipo histórico reutilizado
   * por importação posterior.
   */
  | "HISTORICAL_LEGACY_TYPE_OUTSIDE_PROVEN_POPULATION"
  /** code consta da lista FINISH adjudicada (C3, 2213 PASSO 0C). */
  | "ADJUDICATED_FINISH_CODE"
  /** code não consta de nenhuma lista adjudicada — nunca presumido legado. */
  | "UNKNOWN_CODE"
  /** code ausente na entrada. */
  | "FINISH_CODE_UNAVAILABLE"
  /** tipo SET_LOGO_* sem `cardSetCode`: a natureza depende do Set. */
  | "SET_CONTEXT_REQUIRED"
  /** tipo SET_LOGO_* em EX7–EX16: eixo FINISH pendente (HOLD-MANIFEST H2), sem prova de legado. */
  | "EX_ERA_SET_LOGO_UNRESOLVED"
  /** code legado em variante que já tem Edition Context: inconsistente, não se decide. */
  | "LEGACY_CODE_WITH_EDITION_CONTEXT";

export type CardVariantLegacyClassification = {
  status: CardVariantLegacyStatus;
  reason: CardVariantLegacyReason;
  /** Documento normativo que sustenta a classificação, quando há. */
  evidenceRef: string | null;
};

export type CardVariantLabelCollision = {
  /** true quando outra variante da MESMA carta tem os mesmos nomes de eixo. */
  collides: boolean;
  /** ids das outras variantes com quem colide (ordem determinística). */
  collidingVariantIds: string[];
};

/** Metadados administrativos: nunca entram no rótulo do colecionador. */
export type CardVariantAdminMetadata = {
  legacy: CardVariantLegacyClassification;
  labelCollision: CardVariantLabelCollision;
};

export type CardVariantDisplay = {
  identity: CardVariantIdentity;
  presentation: CardVariantPresentation;
  admin: CardVariantAdminMetadata;
};

export type CardVariantDisplayErrorCode =
  | "INPUT_NOT_ARRAY"
  | "INVALID_RECORD"
  | "INVALID_VARIANT_ID"
  | "INVALID_CARD_ID"
  | "INVALID_VARIANT_TYPE_ID"
  | "FINISH_MISSING"
  | "FINISH_ID_MISMATCH"
  | "PRINTING_EMBED_MISSING"
  | "PRINTING_EMBED_WITHOUT_FK"
  | "PRINTING_ID_MISMATCH"
  | "EDITION_CONTEXT_EMBED_MISSING"
  | "EDITION_CONTEXT_EMBED_WITHOUT_FK"
  | "EDITION_CONTEXT_ID_MISMATCH"
  | "INVALID_AXIS_NAME"
  | "INVALID_DISPLAY_ORDER"
  | "INVALID_FINISH_CODE"
  | "INVALID_CARD_SET_CODE"
  | "DUPLICATE_VARIANT_ID"
  | "DUPLICATE_IDENTITY";

export type CardVariantDisplayError = {
  code: CardVariantDisplayErrorCode;
  /** posição na entrada; null para erros do lote inteiro. */
  index: number | null;
  /** id da variante quando legível; nunca inventado. */
  variantId: string | null;
  message: string;
};

/** Resultado fail-closed: ou o lote inteiro, ou só erros — nunca um lote truncado. */
export type CardVariantDisplayResult =
  | { ok: true; variants: CardVariantDisplay[] }
  | { ok: false; errors: CardVariantDisplayError[] };

// ---------------------------------------------------------------------------
// Evidência adjudicada (espelhos de contratos existentes — nada novo)
// ---------------------------------------------------------------------------

const EDITION_CONTEXT_AXIS_DIR = "database/proposals/2026-09-18-edition-context-axis";

/**
 * Lista FINISH adjudicada (C3), copiada LITERALMENTE de
 * 2213_decompose_legacy_card_variants.sql, PASSO 0C (inclusive as grafias
 * históricas `STANDARDS_SNOWFLAKE` e `SHOWFLAKE_HOLO`). Paridade verificada por
 * teste que lê o arquivo SQL.
 */
export const ADJUDICATED_FINISH_CODES: readonly string[] = Object.freeze([
  "STANDARD", "HOLO", "COSMOS_HOLO", "REVERSE_HOLO",
  "ENERGY_REVERSE", "POKE_BALL_REVERSE", "LOVE_BALL_REVERSE",
  "FRIEND_BALL_REVERSE", "QUICK_BALL_REVERSE", "DUSK_BALL_REVERSE",
  "ROCKET_REVERSE", "MASTER_BALL_REVERSE", "GOLD_HOLO", "TINSEL_HOLO",
  "TINSEL_REVERSE", "CRACKED_ICE_HOLO", "GALAXY_HOLO", "RAINBOW_HOLO",
  "METAL", "METAL_GOLD", "LENTICULAR", "COSMOS_REVERSE",
  "MASTER_BALL_PATTERN", "POKE_BALL_PATTERN", "MASTER_BALL_HOLO",
  "SNOWFLAKE_COSMOS_HOLO", "STANDARDS_SNOWFLAKE", "SHOWFLAKE_HOLO",
]);

/**
 * Variant Types com contexto embutido no acabamento, NOMEADOS em manifestos
 * adjudicados. Só nomes exatos: famílias por prefixo (ex.: os 21
 * `STANDARDS_WORLDS_*`) e os "24 tipos, 1 cada" sem nome não entram.
 *
 * É evidência sobre o TIPO (o code codifica contexto) e sobre a população
 * medida à época — não sobre uma variante individual atual. O classificador
 * nunca produz LEGACY_PROVEN a partir desta tabela.
 */
export const ADJUDICATED_LEGACY_CODES: Readonly<Record<string, string>> = Object.freeze({
  // HOLD-MANIFEST.md H6 — READY_PRICING_CONDITIONED (não decompostas pela 2213).
  STAFF_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/HOLD-MANIFEST.md#H6`,
  // HOLD-MANIFEST.md H1 / H4 — HOLD legado (não decomposto).
  PROMO_STAMPED: `${EDITION_CONTEXT_AXIS_DIR}/HOLD-MANIFEST.md#H1`,
  // MIGRATION-MAP-365.md — tipos nomeados decompostos pela 2213.
  SATANDARD_REWARDS: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  REWARDS_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  POKEMON_CENTER_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  COSMOS_REWARDS_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  COSMOS_REWARDS_REVERSE: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  COSMOS_PROFESSOR_REVERSE: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARDS_TEACHER_PROGRAM: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_GYM_CHALLENGE: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  GAMESTOP_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_REGIONAL_CHAMPIONSHIPS: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  EBGAMES_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_PIKACHU_WORLD_2000: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  W_PROMO_STAMPED: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_FIRST_MOVIE: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_FIRST_MOVIE_INVERTED: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARDS_LEAGUE: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARD_WORLDS_2024: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  STANDARDS_HORIZONS: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  GYM_CHALLENGE_HOLO: `${EDITION_CONTEXT_AXIS_DIR}/MIGRATION-MAP-365.md`,
  // 2213, regra histórica H-PLAYER-REWARD (decisão D4).
  PLAYER_REWARD_REVERSE: `${EDITION_CONTEXT_AXIS_DIR}/2213_decompose_legacy_card_variants.sql#H-PLAYER-REWARD`,
});

/**
 * Populações de tipos contaminados que AINDA existem depois da 2213:
 * HOLD-MANIFEST H6 (STAFF_HOLO 40, Pricing) e H1/H4 (PROMO_STAMPED). Os demais
 * códigos de ADJUDICATED_LEGACY_CODES tiveram a população decomposta inteira
 * (LIVE-2213-V10-APPLY-RECORD.md §7.4: READY_UNCONDITIONED residual 0).
 */
const RETAINED_POPULATION_CODES: ReadonlySet<string> = new Set(["STAFF_HOLO", "PROMO_STAMPED"]);

/**
 * Tipos SET_LOGO_* nomeados em HOLD-MANIFEST H1/H6 e MIGRATION-MAP-365. A
 * natureza depende do Set, pelo mesmo predicado adjudicado da 2213 (PASSO 0 e
 * 0C): em EX7–EX16 o eixo é FINISH pendente (HOLD-MANIFEST H2, alvo de
 * SET-LOGO-EX-ERA-FINISH-01); fora disso o tipo é contaminado, com populações
 * retidas em H1 (HOLD) e H6 (Pricing) — pertença individual não provável aqui.
 */
export const ADJUDICATED_SET_LOGO_CODES: readonly string[] = Object.freeze([
  "SET_LOGO_STANDARDS",
  "SET_LOGO_REVERSE",
  "SET_LOGO_COSMOS_HOLO",
  "SET_LOGO_STAFF_HOLO",
]);

/** Mesmo predicado da 2213: `cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$'`. */
const EX_ERA_SET_CODE = /^EX(7|8|9|10|11|12|13|14|15|16)$/;

const FINISH_CODE_SET = new Set(ADJUDICATED_FINISH_CODES);
const SET_LOGO_CODE_SET = new Set(ADJUDICATED_SET_LOGO_CODES);

// ---------------------------------------------------------------------------
// Validação
// ---------------------------------------------------------------------------

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

function isNonBlankString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Chave canônica de UUID para comparação (Postgres devolve minúsculas; o id original é preservado). */
function uuidKey(id: string): string {
  return id.toLowerCase();
}

type AxisKind = "PRINTING" | "EDITION_CONTEXT";

/**
 * Valida um eixo. Finish exige display_order inteiro ≥ 0 (NOT NULL em 150);
 * Printing/EC exigem > 0 (CHECK em 2166/2204) — 0 é a sentinela de ausência
 * da ordenação e não pode colidir com um perfil real.
 */
function validateAxis(
  axis: unknown,
  minDisplayOrder: number,
  index: number,
  variantId: string | null,
  label: string,
  errors: CardVariantDisplayError[],
): axis is CardVariantAxisInput {
  if (!isObject(axis)) {
    errors.push({ code: "INVALID_RECORD", index, variantId, message: `${label}: eixo não é um objeto.` });
    return false;
  }
  let ok = true;
  if (!isUuid(axis.id)) {
    errors.push({ code: "INVALID_RECORD", index, variantId, message: `${label}: id do eixo não é UUID.` });
    ok = false;
  }
  if (!isNonBlankString(axis.name)) {
    errors.push({ code: "INVALID_AXIS_NAME", index, variantId, message: `${label}: nome ausente ou vazio.` });
    ok = false;
  }
  const order = axis.displayOrder;
  if (typeof order !== "number" || !Number.isSafeInteger(order) || order < minDisplayOrder) {
    errors.push({
      code: "INVALID_DISPLAY_ORDER",
      index,
      variantId,
      message: `${label}: displayOrder deve ser inteiro ≥ ${minDisplayOrder}.`,
    });
    ok = false;
  }
  return ok;
}

function validateOptionalAxis(
  kind: AxisKind,
  fk: unknown,
  embed: unknown,
  index: number,
  variantId: string | null,
  errors: CardVariantDisplayError[],
): boolean {
  const label = kind === "PRINTING" ? "printing" : "editionContext";
  const codes =
    kind === "PRINTING"
      ? { missing: "PRINTING_EMBED_MISSING", orphan: "PRINTING_EMBED_WITHOUT_FK", mismatch: "PRINTING_ID_MISMATCH" }
      : {
          missing: "EDITION_CONTEXT_EMBED_MISSING",
          orphan: "EDITION_CONTEXT_EMBED_WITHOUT_FK",
          mismatch: "EDITION_CONTEXT_ID_MISMATCH",
        };

  if (fk === null) {
    if (embed !== null) {
      errors.push({
        code: codes.orphan as CardVariantDisplayErrorCode,
        index,
        variantId,
        message: `${label}: eixo embutido presente sem FK correspondente.`,
      });
      return false;
    }
    return true;
  }
  if (!isUuid(fk)) {
    errors.push({ code: "INVALID_RECORD", index, variantId, message: `${label}: FK não é UUID nem null.` });
    return false;
  }
  if (embed === null || embed === undefined) {
    // Fail-closed: FK preenchida sem eixo visível NUNCA vira "sem eixo".
    errors.push({
      code: codes.missing as CardVariantDisplayErrorCode,
      index,
      variantId,
      message: `${label}: FK preenchida, mas o eixo não foi fornecido (RLS ou embed ausente).`,
    });
    return false;
  }
  if (!validateAxis(embed, 1, index, variantId, label, errors)) return false;
  if (uuidKey(embed.id) !== uuidKey(fk)) {
    errors.push({
      code: codes.mismatch as CardVariantDisplayErrorCode,
      index,
      variantId,
      message: `${label}: id do eixo difere da FK da variante.`,
    });
    return false;
  }
  return true;
}

function validateRecord(
  record: unknown,
  index: number,
  errors: CardVariantDisplayError[],
): record is CardVariantDisplayInput {
  if (!isObject(record)) {
    errors.push({ code: "INVALID_RECORD", index, variantId: null, message: "registro não é um objeto." });
    return false;
  }
  const before = errors.length;
  const variantId = isUuid(record.id) ? record.id : null;

  if (variantId === null) {
    errors.push({ code: "INVALID_VARIANT_ID", index, variantId: null, message: "card_variant.id ausente ou não é UUID." });
  }
  if (!isUuid(record.cardId)) {
    errors.push({ code: "INVALID_CARD_ID", index, variantId, message: "card_id ausente ou não é UUID." });
  }
  if (!isUuid(record.variantTypeId)) {
    errors.push({ code: "INVALID_VARIANT_TYPE_ID", index, variantId, message: "variant_type_id ausente ou não é UUID." });
  }

  const finish = record.finish;
  if (finish === null || finish === undefined) {
    errors.push({ code: "FINISH_MISSING", index, variantId, message: "acabamento obrigatório ausente." });
  } else if (validateAxis(finish, 0, index, variantId, "finish", errors)) {
    if (isUuid(record.variantTypeId) && uuidKey(finish.id) !== uuidKey(record.variantTypeId)) {
      errors.push({ code: "FINISH_ID_MISMATCH", index, variantId, message: "finish.id difere de variant_type_id." });
    }
    const code = (finish as Record<string, unknown>).code;
    if (code !== null && code !== undefined && !isNonBlankString(code)) {
      errors.push({ code: "INVALID_FINISH_CODE", index, variantId, message: "finish.code deve ser texto não vazio ou null." });
    }
  }

  if (!("printingProfileId" in record) || !("editionContextProfileId" in record)) {
    errors.push({
      code: "INVALID_RECORD",
      index,
      variantId,
      message: "FKs printingProfileId e editionContextProfileId são obrigatórias (null quando o eixo não existe).",
    });
  } else {
    validateOptionalAxis("PRINTING", record.printingProfileId, record.printing ?? null, index, variantId, errors);
    validateOptionalAxis(
      "EDITION_CONTEXT",
      record.editionContextProfileId,
      record.editionContext ?? null,
      index,
      variantId,
      errors,
    );
  }

  const setCode = record.cardSetCode;
  if (setCode !== undefined && setCode !== null && !isNonBlankString(setCode)) {
    errors.push({ code: "INVALID_CARD_SET_CODE", index, variantId, message: "cardSetCode deve ser texto não vazio ou null." });
  }

  return errors.length === before;
}

// ---------------------------------------------------------------------------
// Classificação de legado (M2 — evidência positiva)
// ---------------------------------------------------------------------------

export function classifyCardVariantLegacy(input: {
  finishCode: string | null | undefined;
  editionContextProfileId: string | null;
  cardSetCode?: string | null;
}): CardVariantLegacyClassification {
  const code = input.finishCode;
  if (code === null || code === undefined || code.trim() === "") {
    return { status: "INDETERMINATE", reason: "FINISH_CODE_UNAVAILABLE", evidenceRef: null };
  }

  if (FINISH_CODE_SET.has(code)) {
    return {
      status: "NOT_IDENTIFIED_AS_LEGACY",
      reason: "ADJUDICATED_FINISH_CODE",
      evidenceRef: `${EDITION_CONTEXT_AXIS_DIR}/2213_decompose_legacy_card_variants.sql#PASSO-0C`,
    };
  }

  let evidenceRef: string | null = null;
  let populationRetained = false;
  if (SET_LOGO_CODE_SET.has(code)) {
    const setCode = input.cardSetCode;
    if (setCode === null || setCode === undefined || setCode.trim() === "") {
      return { status: "INDETERMINATE", reason: "SET_CONTEXT_REQUIRED", evidenceRef: null };
    }
    if (EX_ERA_SET_CODE.test(setCode)) {
      return {
        status: "INDETERMINATE",
        reason: "EX_ERA_SET_LOGO_UNRESOLVED",
        evidenceRef: `${EDITION_CONTEXT_AXIS_DIR}/HOLD-MANIFEST.md#H2`,
      };
    }
    evidenceRef = `${EDITION_CONTEXT_AXIS_DIR}/HOLD-MANIFEST.md#H1`;
    populationRetained = true;
  } else if (Object.prototype.hasOwnProperty.call(ADJUDICATED_LEGACY_CODES, code)) {
    evidenceRef = ADJUDICATED_LEGACY_CODES[code] ?? null;
    populationRetained = RETAINED_POPULATION_CODES.has(code);
  }

  if (evidenceRef === null) {
    // Código desconhecido: nunca presumido legado (M2).
    return { status: "INDETERMINATE", reason: "UNKNOWN_CODE", evidenceRef: null };
  }
  if (input.editionContextProfileId !== null) {
    // Tipo contaminado COM Edition Context: estado que nenhum contrato produz.
    return { status: "INDETERMINATE", reason: "LEGACY_CODE_WITH_EDITION_CONTEXT", evidenceRef };
  }
  // Evidência de TIPO, nunca de variante individual: sem a lista congelada de
  // ids não há LEGACY_PROVEN (F1-CORRECTION-01).
  return {
    status: "INDETERMINATE",
    reason: populationRetained
      ? "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN"
      : "HISTORICAL_LEGACY_TYPE_OUTSIDE_PROVEN_POPULATION",
    evidenceRef,
  };
}

// ---------------------------------------------------------------------------
// Ordenação (I5)
// ---------------------------------------------------------------------------

/** Sentinela de ausência: perfis reais têm display_order > 0 (CHECK em 2166/2204). */
const ABSENT_AXIS_ORDER = 0;

function compareNumbers(a: number, b: number): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/** Comparação por unidade de código — independe de locale (nunca localeCompare). */
function compareStrings(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * Ordem total: finish.displayOrder → printing.displayOrder (ausente = 0) →
 * editionContext.displayOrder (ausente = 0) → card_variant.id. `variant_order`
 * não participa.
 */
export function compareCardVariantDisplay(a: CardVariantDisplay, b: CardVariantDisplay): number {
  return (
    compareNumbers(a.presentation.finish.displayOrder, b.presentation.finish.displayOrder) ||
    compareNumbers(
      a.presentation.printing?.displayOrder ?? ABSENT_AXIS_ORDER,
      b.presentation.printing?.displayOrder ?? ABSENT_AXIS_ORDER,
    ) ||
    compareNumbers(
      a.presentation.editionContext?.displayOrder ?? ABSENT_AXIS_ORDER,
      b.presentation.editionContext?.displayOrder ?? ABSENT_AXIS_ORDER,
    ) ||
    compareStrings(uuidKey(a.identity.variantId), uuidKey(b.identity.variantId))
  );
}

/** Devolve cópia ordenada; não altera a entrada. */
export function sortCardVariantDisplays(variants: readonly CardVariantDisplay[]): CardVariantDisplay[] {
  return [...variants].sort(compareCardVariantDisplay);
}

// ---------------------------------------------------------------------------
// Rótulo (I4, I7)
// ---------------------------------------------------------------------------

export type CardVariantLabelAxis = "FINISH" | "PRINTING" | "EDITION_CONTEXT";

export type CardVariantLabelPart = {
  axis: CardVariantLabelAxis;
  text: string;
};

/**
 * Partes do rótulo em ordem de eixo, sem eixos ausentes. A fronteira entre
 * eixos é ESTRUTURAL (uma parte por eixo) — independe de qualquer separador e
 * de os nomes conterem "·" ou "—".
 */
export function getCardVariantLabelParts(variant: CardVariantDisplay): CardVariantLabelPart[] {
  const parts: CardVariantLabelPart[] = [{ axis: "FINISH", text: variant.presentation.finish.name }];
  if (variant.presentation.printing !== null) {
    parts.push({ axis: "PRINTING", text: variant.presentation.printing.name });
  }
  if (variant.presentation.editionContext !== null) {
    parts.push({ axis: "EDITION_CONTEXT", text: variant.presentation.editionContext.name });
  }
  return parts;
}

/**
 * Rótulo em linha única. O separador é OBRIGATÓRIO e não tem padrão: a decisão
 * D1 está aberta. Nunca produz "null", segmento vazio ou separador solto.
 * O texto resultante não deve ser parseado de volta — use as partes.
 */
export function formatCardVariantLabel(variant: CardVariantDisplay, options: { separator: string }): string {
  if (typeof options.separator !== "string" || options.separator.length === 0) {
    throw new TypeError("formatCardVariantLabel: separator deve ser texto não vazio.");
  }
  return getCardVariantLabelParts(variant)
    .map((part) => part.text)
    .join(options.separator);
}

// ---------------------------------------------------------------------------
// Colisões (I6, M3)
// ---------------------------------------------------------------------------

/**
 * Agrupa por chave dentro da MESMA carta e devolve, para cada variante, os
 * ids das outras com a mesma chave. O(n) via Map; nenhuma variante é removida.
 */
function computeCollisions(
  variants: readonly CardVariantDisplay[],
  keyOf: (variant: CardVariantDisplay) => string,
): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (const variant of variants) {
    const key = JSON.stringify([uuidKey(variant.identity.cardId), keyOf(variant)]);
    const ids = groups.get(key);
    if (ids) ids.push(variant.identity.variantId);
    else groups.set(key, [variant.identity.variantId]);
  }
  const result = new Map<string, string[]>();
  for (const ids of groups.values()) {
    const sorted = [...ids].sort((a, b) => compareStrings(uuidKey(a), uuidKey(b)));
    for (const id of ids) {
      result.set(id, sorted.filter((other) => other !== id));
    }
  }
  return result;
}

/** Chave semântica: tupla de nomes por eixo — independente de separador. */
function semanticLabelKey(variant: CardVariantDisplay): string {
  return JSON.stringify([
    variant.presentation.finish.name,
    variant.presentation.printing?.name ?? null,
    variant.presentation.editionContext?.name ?? null,
  ]);
}

/**
 * Colisões do texto RENDERIZADO com um separador específico. Pega também o
 * caso em que nomes diferentes viram o mesmo texto porque um nome contém o
 * separador (ex.: "A · B" + "C" × "A" + "B · C" com " · ").
 */
export function findRenderedLabelCollisions(
  variants: readonly CardVariantDisplay[],
  options: { separator: string },
): Map<string, string[]> {
  const collisions = computeCollisions(variants, (variant) => formatCardVariantLabel(variant, options));
  for (const [id, others] of collisions) {
    if (others.length === 0) collisions.delete(id);
  }
  return collisions;
}

// ---------------------------------------------------------------------------
// Construção (I1–I4, I6, I8)
// ---------------------------------------------------------------------------

/**
 * Transforma linhas de `card_variant` no modelo de exibição, ordenado.
 * Fail-closed: qualquer registro inválido invalida o lote — devolve só erros,
 * nunca um lote parcial. Não lança exceção para dado inválido.
 */
export function buildCardVariantDisplays(input: unknown): CardVariantDisplayResult {
  if (!Array.isArray(input)) {
    return {
      ok: false,
      errors: [{ code: "INPUT_NOT_ARRAY", index: null, variantId: null, message: "entrada deve ser um array." }],
    };
  }

  const errors: CardVariantDisplayError[] = [];
  const valid: { record: CardVariantDisplayInput; index: number }[] = [];
  input.forEach((record: unknown, index: number) => {
    if (validateRecord(record, index, errors)) valid.push({ record, index });
  });

  // Duplicidades: mesmo id (I1) ou mesma identidade de 4 componentes (2209).
  const seenIds = new Map<string, number>();
  const seenIdentities = new Map<string, number>();
  input.forEach((record: unknown, index: number) => {
    if (!isObject(record) || !isUuid(record.id)) return;
    const idKey = uuidKey(record.id);
    const firstIdIndex = seenIds.get(idKey);
    if (firstIdIndex !== undefined) {
      errors.push({
        code: "DUPLICATE_VARIANT_ID",
        index,
        variantId: record.id,
        message: `card_variant.id repetido (primeira ocorrência no índice ${firstIdIndex}).`,
      });
    } else {
      seenIds.set(idKey, index);
    }
  });
  for (const { record, index } of valid) {
    const identityKey = JSON.stringify([
      uuidKey(record.cardId),
      uuidKey(record.variantTypeId),
      record.printingProfileId === null ? null : uuidKey(record.printingProfileId),
      record.editionContextProfileId === null ? null : uuidKey(record.editionContextProfileId),
    ]);
    const first = seenIdentities.get(identityKey);
    if (first === undefined) {
      seenIdentities.set(identityKey, index);
    } else if (seenIds.get(uuidKey(record.id)) === index) {
      // Ids diferentes com a mesma identidade (id repetido já foi reportado acima).
      errors.push({
        code: "DUPLICATE_IDENTITY",
        index,
        variantId: record.id,
        message: `identidade de 4 componentes repetida (índice ${first}); viola uq_card_variant_identity.`,
      });
    }
  }

  if (errors.length > 0) {
    return { ok: false, errors: [...errors].sort((a, b) => compareNumbers(a.index ?? -1, b.index ?? -1)) };
  }

  const built: CardVariantDisplay[] = valid.map(({ record }) => {
    const finish = record.finish as CardVariantFinishInput;
    return {
      identity: {
        variantId: record.id,
        cardId: record.cardId,
        variantTypeId: record.variantTypeId,
        printingProfileId: record.printingProfileId,
        editionContextProfileId: record.editionContextProfileId,
      },
      presentation: {
        finish: { name: finish.name, displayOrder: finish.displayOrder },
        printing:
          record.printing === null || record.printing === undefined
            ? null
            : { name: record.printing.name, displayOrder: record.printing.displayOrder },
        editionContext:
          record.editionContext === null || record.editionContext === undefined
            ? null
            : { name: record.editionContext.name, displayOrder: record.editionContext.displayOrder },
      },
      admin: {
        legacy: classifyCardVariantLegacy({
          finishCode: finish.code,
          editionContextProfileId: record.editionContextProfileId,
          cardSetCode: record.cardSetCode ?? null,
        }),
        labelCollision: { collides: false, collidingVariantIds: [] },
      },
    };
  });

  const collisions = computeCollisions(built, semanticLabelKey);
  for (const variant of built) {
    const others = collisions.get(variant.identity.variantId) ?? [];
    variant.admin.labelCollision = { collides: others.length > 0, collidingVariantIds: others };
  }

  return { ok: true, variants: sortCardVariantDisplays(built) };
}
