/**
 * Meu acervo — adicionar cartas (MY-INVENTORY-ACTIONS-01).
 *
 * Regras puras do cliente e do servidor para os dois fluxos de cadastro, sem
 * nenhuma regra de domínio própria: quem decide é o banco.
 *
 * - Cartas avulsas → `preview_bulk_operation` (B1, 5151/5158) e
 *   `register_physical_cards_bulk` (5150/5155).
 * - Set inteiro → `preview_bulk_operation` (B2, 5158) e `register_card_set_bulk`
 *   (5157, BULK-04).
 *
 * Aqui ficam só: montagem dos envelopes (chaves fechadas, exatamente as do
 * contrato), consolidação da seleção (a mesma carta+variante+idioma vira uma
 * linha — o banco recusa par duplicado), leitura defensiva das respostas e a
 * tradução de códigos/erros para a linguagem do colecionador.
 */

/** Teto por operação — o mesmo dos contratos B1/B2 (o banco é a autoridade; aqui só evita uma ida inútil). */
export const ADD_MAX_TOTAL = 1000;
/** Limite de quantidade por linha na interface (o banco aceita mais; acima disso, quem tem tantas cópias usa várias linhas). */
export const ADD_MAX_QUANTITY = 99;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}

export type AddLanguage = { id: string; code: string; name: string };

export type AddVariant = { id: string; label: string | null; isDefault: boolean };

/** Uma linha da seleção: uma carta, numa variante e num idioma, com quantidade. */
export type DraftLine = {
  cardId: string;
  cardName: string;
  setCode: string;
  setName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imageUrl: string | null;
  variantId: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  languageId: string;
  quantity: number;
};

export type RegisterItem = { card_variant_id: string; language_id: string; quantity: number };

export function lineKey(line: Pick<DraftLine, "variantId" | "languageId">): string {
  return `${line.variantId}:${line.languageId}`;
}

function clampQuantity(value: number): number {
  if (!Number.isFinite(value)) return 1;
  return Math.min(ADD_MAX_QUANTITY, Math.max(1, Math.trunc(value)));
}

/**
 * Acrescenta uma linha. Se a mesma variante+idioma já está na seleção, soma as
 * quantidades (multiplicidade é só por quantidade, nunca por linha repetida).
 */
export function addLine(lines: readonly DraftLine[], line: DraftLine): DraftLine[] {
  const key = lineKey(line);
  const index = lines.findIndex((existing) => lineKey(existing) === key);
  if (index === -1) return [...lines, { ...line, quantity: clampQuantity(line.quantity) }];
  return lines.map((existing, i) =>
    i === index ? { ...existing, quantity: clampQuantity(existing.quantity + line.quantity) } : existing,
  );
}

/**
 * Altera variante, idioma ou quantidade da linha `index`. Se a troca colidir
 * com outra linha (mesma variante+idioma), as duas se fundem na posição da
 * primeira — nunca ficam duas linhas iguais.
 */
export function updateLine(
  lines: readonly DraftLine[],
  index: number,
  patch: Partial<Pick<DraftLine, "variantId" | "variantLabel" | "isDefaultVariant" | "languageId" | "quantity">>,
): DraftLine[] {
  const current = lines[index];
  if (!current) return [...lines];
  const updated: DraftLine = {
    ...current,
    ...patch,
    quantity: clampQuantity(patch.quantity ?? current.quantity),
  };
  const key = lineKey(updated);
  const other = lines.findIndex((line, i) => i !== index && lineKey(line) === key);
  if (other === -1) return lines.map((line, i) => (i === index ? updated : line));
  const keep = Math.min(index, other);
  const drop = Math.max(index, other);
  const merged = { ...updated, quantity: clampQuantity(updated.quantity + (lines[other]?.quantity ?? 0)) };
  return lines.filter((_, i) => i !== drop).map((line, i) => (i === keep ? merged : line));
}

export function removeLine(lines: readonly DraftLine[], index: number): DraftLine[] {
  return lines.filter((_, i) => i !== index);
}

export function totalQuantity(lines: readonly Pick<DraftLine, "quantity">[]): number {
  return lines.reduce((sum, line) => sum + line.quantity, 0);
}

export function toRegisterItems(lines: readonly DraftLine[]): RegisterItem[] {
  return lines.map((line) => ({ card_variant_id: line.variantId, language_id: line.languageId, quantity: line.quantity }));
}

/** Motivo para não seguir para a revisão, em linguagem do colecionador; `null` = pode revisar. */
export function draftProblem(lines: readonly DraftLine[]): string | null {
  if (lines.length === 0) return "Escolha ao menos uma carta.";
  const total = totalQuantity(lines);
  if (total > ADD_MAX_TOTAL) {
    return `São ${total} cartas — o máximo por vez é ${ADD_MAX_TOTAL}. Divida em mais de uma adição.`;
  }
  return null;
}

/** Validação de entrada no servidor (a autoridade final continua sendo o banco). */
export function validRegisterItems(items: unknown): items is RegisterItem[] {
  if (!Array.isArray(items) || items.length === 0 || items.length > ADD_MAX_TOTAL) return false;
  let total = 0;
  const seen = new Set<string>();
  for (const item of items) {
    if (typeof item !== "object" || item === null) return false;
    const { card_variant_id, language_id, quantity } = item as Record<string, unknown>;
    if (!isUuid(card_variant_id) || !isUuid(language_id)) return false;
    if (typeof quantity !== "number" || !Number.isInteger(quantity) || quantity < 1 || quantity > ADD_MAX_QUANTITY) return false;
    const key = `${card_variant_id}:${language_id}`;
    if (seen.has(key)) return false;
    seen.add(key);
    total += quantity;
  }
  return total <= ADD_MAX_TOTAL;
}

// ---- envelopes (chaves fechadas, exatamente as dos contratos) ----

// `collectionId` (V1-06, Fluxos 2 e 5 a partir da coleção): os envelopes 5150/
// 5157 já aceitam a coleção de destino — o banco cria os exemplares E a
// alocação na mesma transação (tudo ou nada), conferindo dono, coleção ativa,
// Game e o Set de referência. Revisão e confirmação levam a MESMA coleção (o
// fingerprint a inclui). `storageId` (V1-06 COMPLETE-01): local escolhido
// EXPLICITAMENTE na interface (NS-13 — nunca presumido), gravado no mesmo
// INSERT do exemplar (5153); nulo = "Sem localização definida".

export function previewCardsRequest(items: RegisterItem[], collectionId: string | null = null, storageId: string | null = null) {
  return { operation_type: "REGISTER_PHYSICAL_CARDS", items, collection_id: collectionId, storage_container_id: storageId };
}

export function confirmCardsRequest(
  idempotencyKey: string,
  previewFingerprint: string,
  items: RegisterItem[],
  collectionId: string | null = null,
  storageId: string | null = null,
) {
  return {
    idempotency_key: idempotencyKey,
    preview_fingerprint: previewFingerprint,
    items,
    collection_id: collectionId,
    storage_container_id: storageId,
  };
}

export function previewSetRequest(cardSetId: string, languageId: string, collectionId: string | null = null, storageId: string | null = null) {
  return {
    operation_type: "REGISTER_CARD_SET",
    card_set_id: cardSetId,
    language_id: languageId,
    collection_id: collectionId,
    storage_container_id: storageId,
  };
}

export function confirmSetRequest(
  idempotencyKey: string,
  previewFingerprint: string,
  cardSetId: string,
  languageId: string,
  collectionId: string | null = null,
  storageId: string | null = null,
) {
  return {
    idempotency_key: idempotencyKey,
    preview_fingerprint: previewFingerprint,
    card_set_id: cardSetId,
    language_id: languageId,
    collection_id: collectionId,
    storage_container_id: storageId,
  };
}

// ---- respostas ----

export type PreviewIssue = { code: string; count: number };

export type PreviewResult = {
  ok: boolean;
  fingerprint: string | null;
  distinctItems: number;
  totalQuantity: number;
  issues: PreviewIssue[];
};

function asRecord(value: unknown): Record<string, unknown> | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function asCount(value: unknown): number {
  const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
  return Number.isFinite(n) && n >= 0 ? Math.trunc(n) : 0;
}

/**
 * Lê a resposta de `preview_bulk_operation`. Contrato binário: `ok` só vale
 * com fingerprint preenchido; qualquer forma inesperada vira `null` (erro).
 */
export function parsePreview(raw: unknown): PreviewResult | null {
  const data = asRecord(raw);
  if (!data || typeof data.ok !== "boolean") return null;
  const summary = asRecord(data.summary) ?? {};
  const issues = Array.isArray(data.issues)
    ? data.issues.flatMap((issue) => {
        const record = asRecord(issue);
        if (!record || typeof record.code !== "string") return [];
        return [{ code: record.code, count: Array.isArray(record.offenders) ? record.offenders.length : 0 }];
      })
    : [];
  const fingerprint = typeof data.preview_fingerprint === "string" && data.preview_fingerprint.trim() !== "" ? data.preview_fingerprint : null;
  if (data.ok && !fingerprint) return null;
  return {
    ok: data.ok && fingerprint !== null,
    fingerprint,
    distinctItems: asCount(summary.distinct_items),
    totalQuantity: asCount(summary.total_quantity),
    issues,
  };
}

export type RegisterResult = { replay: boolean; createdCount: number; distinctItems: number; physicalCardIds: string[] };

/** Lê o retorno das confirmações B1/B2 (`outcome` CREATED ou REPLAY — os dois são sucesso). */
export function parseRegister(raw: unknown): RegisterResult | null {
  const data = asRecord(raw);
  if (!data || (data.outcome !== "CREATED" && data.outcome !== "REPLAY")) return null;
  const summary = asRecord(data.result_summary);
  if (!summary) return null;
  return {
    replay: data.outcome === "REPLAY",
    createdCount: asCount(summary.created_count),
    distinctItems: asCount(summary.distinct_items),
    // Exemplares criados (5155/5157 `physical_card_ids`; o REPLAY devolve o mesmo resumo).
    physicalCardIds: Array.isArray(summary.physical_card_ids)
      ? summary.physical_card_ids.filter((id): id is string => typeof id === "string" && isUuid(id))
      : [],
  };
}

// ---- erros ----

export type AddFailure =
  | "stale"
  | "conflict"
  | "inactive_variant"
  | "default_variant_missing"
  | "too_many"
  | "set_not_found"
  | "set_empty"
  | "allocated"
  | "not_authenticated"
  | "invalid"
  | "unavailable";

/**
 * Classifica uma exceção das RPCs pelo SQLSTATE e pelo prefixo estável da
 * mensagem (os contratos usam prefixos em maiúsculas justamente para isso).
 * O texto cru nunca chega ao usuário.
 */
export function classifyFailure(code: string | null | undefined, message: string | null | undefined): AddFailure {
  const text = message ?? "";
  if (code === "28000" || code === "42501") return "not_authenticated";
  if (text.startsWith("PREVIEW_STALE")) return "stale";
  if (text.startsWith("BULK_IDEMPOTENCY_CONFLICT")) return "conflict";
  if (text.startsWith("CARD_VARIANT_INACTIVE")) return "inactive_variant";
  if (text.startsWith("CARD_DEFAULT_VARIANT_MISSING")) return "default_variant_missing";
  if (text.includes("excede o limite")) return "too_many";
  if (text === "card set not found") return "set_not_found";
  if (text === "card set has no active cards") return "set_empty";
  if (text.startsWith("PHYSICAL_CARD_ALLOCATED")) return "allocated";
  if (code === "22023" || code === "22P02" || code === "P0002") return "invalid";
  return "unavailable";
}

export function failureMessage(reason: AddFailure): string {
  switch (reason) {
    case "stale":
      return "Algo mudou no catálogo desde a revisão. Revise de novo antes de confirmar.";
    case "conflict":
      return "Esta adição já foi usada para outro pedido. Revise de novo para continuar.";
    case "inactive_variant":
      return "Uma das variantes escolhidas deixou de estar disponível. Revise a seleção.";
    case "default_variant_missing":
      return "Algumas cartas deste Set ainda não têm a versão padrão definida no catálogo, então o Set não pode ser adicionado inteiro agora.";
    case "too_many":
      return `O máximo por vez é ${ADD_MAX_TOTAL} cartas. Divida em mais de uma adição.`;
    case "set_not_found":
      return "Não encontramos este Set no catálogo.";
    case "set_empty":
      return "Este Set ainda não tem cartas disponíveis no catálogo.";
    case "allocated":
      return "Este exemplar está em uma coleção. Retire-o da coleção antes de removê-lo.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "invalid":
      return "Não conseguimos entender este pedido. Revise a seleção e tente de novo.";
    case "unavailable":
      return "Não conseguimos concluir agora. Suas cartas não foram alteradas — tente novamente.";
  }
}

/** Erros em que repetir a MESMA confirmação (mesma chave) é seguro e pode dar certo. */
export function isRetryable(reason: AddFailure): boolean {
  return reason === "unavailable";
}

/** Tradução dos `issues[].code` do Preview (B1 + B2) para o colecionador. */
export function issueMessage(issue: PreviewIssue): string {
  const n = issue.count;
  switch (issue.code) {
    case "CARD_VARIANT_NOT_FOUND":
      return n === 1 ? "Uma das cartas escolhidas não está mais disponível." : `${n} cartas escolhidas não estão mais disponíveis.`;
    case "LANGUAGE_NOT_FOUND":
      return "Um dos idiomas escolhidos não está disponível.";
    case "DUPLICATE_ITEM":
      return "A mesma carta aparece repetida na seleção.";
    case "INVENTORY_NOT_FOUND":
      return "Seu acervo ainda não está pronto. Saia e entre de novo; se continuar, fale com o suporte.";
    case "CARD_SET_NOT_FOUND":
      return "Não encontramos este Set no catálogo.";
    case "CARD_SET_EMPTY":
      return "Este Set ainda não tem cartas disponíveis no catálogo.";
    case "CARD_DEFAULT_VARIANT_MISSING":
      return n === 1
        ? "Uma carta deste Set ainda não tem a versão padrão definida no catálogo, então o Set não pode ser adicionado inteiro agora. Adicione as cartas uma a uma."
        : `${n} cartas deste Set ainda não têm a versão padrão definida no catálogo, então o Set não pode ser adicionado inteiro agora. Adicione as cartas uma a uma.`;
    case "COLLECTION_ARCHIVED":
      return "A coleção está arquivada. Reative-a para adicionar cartas.";
    case "NOT_ELIGIBLE_FOR_REFERENCE":
      return n === 1 ? "Uma das cartas não é do Set desta coleção." : `${n} cartas não são do Set desta coleção.`;
    case "GAME_MISMATCH":
      return "Algumas cartas são de outro jogo e não podem entrar nesta coleção.";
    case "COLLECTION_NOT_ACCESSIBLE":
    case "STORAGE_NOT_ACCESSIBLE":
      return "O destino escolhido não aceita estas cartas.";
    default:
      return "Há um impedimento para adicionar estas cartas.";
  }
}

export type AddCardsTotals = { copies: number; distinct: number };

/** "12 cartas · 5 diferentes" */
export function selectionLabel({ copies, distinct }: AddCardsTotals): string {
  const c = copies === 1 ? "1 carta" : `${copies.toLocaleString("pt-BR")} cartas`;
  if (distinct <= 1) return c;
  return `${c} · ${distinct.toLocaleString("pt-BR")} diferentes`;
}

/** Idioma inicial da seleção: português, se existir; senão o primeiro da lista. */
export function defaultLanguageId(languages: readonly AddLanguage[]): string | null {
  return (languages.find((language) => language.code === "pt-BR") ?? languages[0])?.id ?? null;
}

/** Variante inicial de uma carta: a padrão; senão a primeira (o banco já ordena padrão primeiro). */
export function defaultVariant(variants: readonly AddVariant[]): AddVariant | null {
  return variants.find((variant) => variant.isDefault) ?? variants[0] ?? null;
}
