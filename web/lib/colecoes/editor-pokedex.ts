/**
 * V1-13 · E3 / F3-1 — Pokédex colaborativa do EDITOR: contratos, resultados e privacidade.
 * Regras puras, sem rede e sem interface (o painel é a F3-2).
 *
 * Contratos conferidos no SQL implantado (database/schema/5391 e 5392, 2026-11-27):
 *
 *  - get_editor_pokedex_position_copies(p_collection_id uuid, p_pokedex_position_id uuid,
 *      p_scope text, p_query text = null, p_limit int = 30, p_offset int = 0)
 *    → copy_token, card_name, collector_number, card_set_code, variant_label, language_code,
 *      image_path, species_match, current_position_id, current_position_number,
 *      assignment_basis, is_primary_representative, is_effective_representative,
 *      position_representative_mode, total_count.
 *    Escopo AT_POSITION (exemplares da posição; representante preenchida) ou ASSIGNABLE
 *    (alocados à coleção e fora da posição; colunas de representante NULL). Busca só em
 *    ASSIGNABLE, até 64 caracteres (1–4 dígitos = número nacional). Limite 1–100,
 *    deslocamento 0–10000 (INVALID_PAGE). Sem acesso, sem Pokédex ou posição fora do
 *    escopo → ZERO linhas (indistinguível de "nenhuma cópia").
 *    copy_token = 'pc1.' + HMAC-SHA256(alocação|participação|época): muda quando a
 *    participação ou a época do papel muda; o servidor só aceita o da época vigente.
 *
 *  - editor_move_pokedex_copy(p_collection_id, p_copy_token, p_target_position_id,
 *      p_expected_position_id, p_confirm_override = false)
 *    → (operation CREATED | MOVED | UNCHANGED, pokedex_position_id, previous_position_id,
 *       assignment_basis, representative_cleared)
 *  - editor_unassign_pokedex_copy(p_collection_id, p_copy_token, p_expected_position_id)
 *    → (operation REMOVED | UNCHANGED, previous_position_id, representative_cleared)
 *  - editor_choose_pokedex_representative(p_collection_id, p_copy_token,
 *      p_expected_position_id, p_expected_representative_token = null)
 *    → (operation SET | REPLACED | UNCHANGED, pokedex_position_id)
 *  - editor_restore_pokedex_automatic_representative(p_collection_id, p_pokedex_position_id,
 *      p_expected_representative_token)
 *    → (operation CLEARED | UNCHANGED)
 *
 * Recusas (mensagem da exceção; hint/detail nunca são lidos): CAPABILITY_NOT_ENABLED
 * (42501, barreira), not_authenticated (28000), INVALID_ARGUMENT/INVALID_PAGE (22023),
 * COLLECTION_NOT_FOUND (P0002), COLLECTION_ARCHIVED (55000), NOT_POKEDEX_COLLECTION,
 * POKEDEX_POSITION_NOT_FOUND, STATE_CHANGED, CONFIRMATION_REQUIRED (22023),
 * COPY_NOT_FOUND (P0002), trava ocupada (55P03).
 *
 * Privacidade: este módulo nunca aceita nem produz identificador físico (exemplar,
 * alocação, usuário, local). O único identificador de exemplar é o copy_token da 5391,
 * descartado quando a lista é invalidada. O caminho legado (5373/5380) não é usado.
 */

// E3-7b: token e chaves proibidas num módulo neutro (também usado pelo fichário do EDITOR, 5397).
import { type CopyToken, hasForbiddenKey, isCopyToken } from "./copy-token.ts";
export { type CopyToken, hasForbiddenKey, isCopyToken };

export const EDITOR_POKEDEX_RPC = {
  copies: "get_editor_pokedex_position_copies",
  move: "editor_move_pokedex_copy",
  unassign: "editor_unassign_pokedex_copy",
  choose: "editor_choose_pokedex_representative",
  restore: "editor_restore_pokedex_automatic_representative",
} as const;

export const COPY_PAGE_DEFAULT = 30;
export const COPY_PAGE_MAX = 100;
export const COPY_OFFSET_MAX = 10000;
export const COPY_QUERY_MAX = 64;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type CopyScope = "AT_POSITION" | "ASSIGNABLE";
export type AssignmentBasis = "SPECIES_MATCH" | "USER_OVERRIDE";
export type RepresentativeMode = "CHOSEN" | "AUTOMATIC";

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value);
}


// ---------------------------------------------------------------------------
// Leitura (5391)

export type CopiesQuery = {
  collectionId: string;
  positionId: string;
  scope: CopyScope;
  query?: string | null;
  limit?: number;
  offset?: number;
};

export type RpcCall<A> = { fn: string; args: A };

export type CopiesArgs = {
  p_collection_id: string;
  p_pokedex_position_id: string;
  p_scope: CopyScope;
  p_query: string | null;
  p_limit: number;
  p_offset: number;
};

function validInt(n: unknown, min: number, max: number): n is number {
  return typeof n === "number" && Number.isInteger(n) && n >= min && n <= max;
}

/** Monta a leitura só com parâmetros que o servidor aceita; inválido → null (não chama). */
export function buildCopiesCall(q: CopiesQuery): RpcCall<CopiesArgs> | null {
  if (!q || !isUuid(q.collectionId) || !isUuid(q.positionId)) return null;
  if (q.scope !== "AT_POSITION" && q.scope !== "ASSIGNABLE") return null;
  const limit = q.limit ?? COPY_PAGE_DEFAULT;
  const offset = q.offset ?? 0;
  if (!validInt(limit, 1, COPY_PAGE_MAX) || !validInt(offset, 0, COPY_OFFSET_MAX)) return null;
  const query = typeof q.query === "string" ? q.query.trim() : null;
  const p_query = query ? query : null;
  if (p_query !== null && (q.scope !== "ASSIGNABLE" || p_query.length > COPY_QUERY_MAX)) return null;
  return {
    fn: EDITOR_POKEDEX_RPC.copies,
    args: {
      p_collection_id: q.collectionId.toLowerCase(),
      p_pokedex_position_id: q.positionId.toLowerCase(),
      p_scope: q.scope,
      p_query,
      p_limit: limit,
      p_offset: offset,
    },
  };
}

export type EditorPokedexCopy = {
  token: CopyToken;
  cardName: string;
  collectorNumber: string | null;
  setCode: string | null;
  variantLabel: string | null;
  languageCode: string | null;
  imagePath: string | null;
  speciesMatch: boolean;
  /** Posição atual (catálogo), não identidade do exemplar. NULL = sem posição. */
  currentPositionId: string | null;
  currentPositionNumber: number | null;
  assignmentBasis: AssignmentBasis | null;
  /** Só AT_POSITION. */
  isPrimaryRepresentative: boolean | null;
  isEffectiveRepresentative: boolean | null;
  representativeMode: RepresentativeMode | null;
};

export type CopiesPage = {
  scope: CopyScope;
  /** Contexto a que os tokens pertencem: usá-los em outra coleção é recusado aqui. */
  collectionId: string;
  positionId: string;
  items: EditorPokedexCopy[];
  total: number;
  offset: number;
  hasMore: boolean;
};

/** Zero linhas: sem cópias OU sem acesso (o servidor não distingue). Depois da 1ª página: estado mudou. */
export type CopiesEmptyKind = "none_or_unavailable" | "stale";

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function bigintLike(v: unknown): number | null {
  if (typeof v === "number" && Number.isSafeInteger(v) && v >= 0) return v;
  if (typeof v === "string" && /^\d{1,15}$/.test(v)) return Number(v);
  return null;
}

function parseCopyRow(raw: unknown, scope: CopyScope, positionId: string): EditorPokedexCopy | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  if (hasForbiddenKey(raw)) return null; // falha fechada: contrato nunca traz identidade física
  const r = raw as Record<string, unknown>;
  const token = r.copy_token;
  const name = str(r.card_name);
  if (!isCopyToken(token) || !name || typeof r.species_match !== "boolean") return null;
  const cur = r.current_position_id;
  if (cur !== null && !isUuid(cur)) return null;
  const num = r.current_position_number;
  if (num !== null && !validInt(num, 1, 100000)) return null;
  const basis = r.assignment_basis;
  if (basis !== null && basis !== "SPECIES_MATCH" && basis !== "USER_OVERRIDE") return null;
  const prim = r.is_primary_representative;
  const eff = r.is_effective_representative;
  const mode = r.position_representative_mode;
  if (scope === "AT_POSITION") {
    if (typeof prim !== "boolean" || typeof eff !== "boolean" || (mode !== "CHOSEN" && mode !== "AUTOMATIC")) return null;
    if (typeof cur !== "string" || cur.toLowerCase() !== positionId || basis === null) return null;
  } else {
    if (prim !== null || eff !== null || mode !== null) return null;
    if (typeof cur === "string" && cur.toLowerCase() === positionId) return null;
    if ((cur === null) !== (basis === null)) return null;
  }
  return {
    token,
    cardName: name,
    collectorNumber: str(r.collector_number),
    setCode: str(r.card_set_code),
    variantLabel: str(r.variant_label),
    languageCode: str(r.language_code),
    imagePath: str(r.image_path),
    speciesMatch: r.species_match,
    currentPositionId: typeof cur === "string" ? cur.toLowerCase() : null,
    currentPositionNumber: (num as number | null) ?? null,
    assignmentBasis: basis as AssignmentBasis | null,
    isPrimaryRepresentative: scope === "AT_POSITION" ? (prim as boolean) : null,
    isEffectiveRepresentative: scope === "AT_POSITION" ? (eff as boolean) : null,
    representativeMode: scope === "AT_POSITION" ? (mode as RepresentativeMode) : null,
  };
}

/**
 * Converte a resposta da 5391. Qualquer linha fora do contrato → null (nunca exibe
 * dados parciais). Zero linhas → página vazia; o chamador decide com `emptyKind`.
 */
export function parseCopiesPage(data: unknown, call: RpcCall<CopiesArgs>): CopiesPage | null {
  if (!Array.isArray(data)) return null;
  const { p_scope: scope, p_collection_id: collectionId, p_pokedex_position_id: positionId, p_offset: offset, p_limit: limit } = call.args;
  const items: EditorPokedexCopy[] = [];
  let total: number | null = data.length === 0 ? 0 : null;
  const seen = new Set<string>();
  for (const raw of data) {
    const item = parseCopyRow(raw, scope, positionId);
    if (!item || seen.has(item.token)) return null;
    seen.add(item.token);
    const t = bigintLike((raw as Record<string, unknown>).total_count);
    if (t === null || (total !== null && t !== total)) return null;
    total = t;
    items.push(item);
  }
  // Zero linhas não trazem total_count (nem com deslocamento > 0): o total fica 0 e emptyKind decide.
  if (items.length > limit || (items.length > 0 && (total as number) < offset + items.length)) return null;
  if (scope === "AT_POSITION" && items.length > 0 && offset === 0) {
    // Exatamente a primeira linha é a representante efetiva (ordem do servidor).
    if (!items[0]?.isEffectiveRepresentative || items.slice(1).some((i) => i.isEffectiveRepresentative)) return null;
  }
  return { scope, collectionId, positionId, items, total: total as number, offset, hasMore: offset + items.length < (total as number) };
}

export function emptyKind(page: CopiesPage): CopiesEmptyKind | null {
  if (page.items.length > 0) return null;
  return page.offset > 0 ? "stale" : "none_or_unavailable";
}

/** Próximo deslocamento, ou null no fim / além do teto do servidor. */
export function nextOffset(page: CopiesPage, limit = COPY_PAGE_DEFAULT): number | null {
  if (!page.hasMore) return null;
  const next = page.offset + page.items.length;
  return next <= COPY_OFFSET_MAX && validInt(limit, 1, COPY_PAGE_MAX) ? next : null;
}

/** Representante efetiva da posição (AT_POSITION), como a tela a viu. */
export function seenRepresentative(page: CopiesPage): { token: CopyToken; mode: RepresentativeMode } | null {
  if (page.scope !== "AT_POSITION" || page.offset !== 0) return null;
  const first = page.items[0];
  return first && first.isEffectiveRepresentative && first.representativeMode ? { token: first.token, mode: first.representativeMode } : null;
}

// ---------------------------------------------------------------------------
// Tokens: pertencem a UMA lista (coleção + posição + época). Invalidar = descartar.

export type TokenScope = { collectionId: string; generation: number };

/** Nova geração de tokens: depois de COPY_NOT_FOUND, STATE_CHANGED, perda de acesso ou troca de papel. */
export function invalidateTokens(scope: TokenScope): TokenScope {
  return { collectionId: scope.collectionId, generation: scope.generation + 1 };
}

/** O token pode ser usado nesta coleção, vindo de uma página desta geração? */
export function tokenUsable(token: unknown, page: CopiesPage | null, scope: TokenScope, pageGeneration: number): token is CopyToken {
  return isCopyToken(token) && !!page && page.collectionId === scope.collectionId && pageGeneration === scope.generation
    && page.items.some((i) => i.token === token);
}

// ---------------------------------------------------------------------------
// Escritas (5392): só identificadores opacos e posições de catálogo.

export type MoveArgs = { p_collection_id: string; p_copy_token: CopyToken; p_target_position_id: string; p_expected_position_id: string | null; p_confirm_override: boolean };
export type UnassignArgs = { p_collection_id: string; p_copy_token: CopyToken; p_expected_position_id: string };
export type ChooseArgs = { p_collection_id: string; p_copy_token: CopyToken; p_expected_position_id: string; p_expected_representative_token: CopyToken | null };
export type RestoreArgs = { p_collection_id: string; p_pokedex_position_id: string; p_expected_representative_token: CopyToken };

const low = (s: string) => s.toLowerCase();

/** Atribuir (expectedPositionId = null: a tela viu o exemplar sem posição) ou mover. */
export function buildMoveCall(i: { collectionId: string; copyToken: unknown; targetPositionId: string; expectedPositionId: string | null; confirmOverride?: boolean }): RpcCall<MoveArgs> | null {
  if (!i || !isUuid(i.collectionId) || !isCopyToken(i.copyToken) || !isUuid(i.targetPositionId)) return null;
  if (i.expectedPositionId !== null && !isUuid(i.expectedPositionId)) return null;
  if (i.confirmOverride !== undefined && typeof i.confirmOverride !== "boolean") return null;
  return {
    fn: EDITOR_POKEDEX_RPC.move,
    args: {
      p_collection_id: low(i.collectionId),
      p_copy_token: i.copyToken,
      p_target_position_id: low(i.targetPositionId),
      p_expected_position_id: i.expectedPositionId === null ? null : low(i.expectedPositionId),
      p_confirm_override: i.confirmOverride === true,
    },
  };
}

export function buildUnassignCall(i: { collectionId: string; copyToken: unknown; expectedPositionId: string }): RpcCall<UnassignArgs> | null {
  if (!i || !isUuid(i.collectionId) || !isCopyToken(i.copyToken) || !isUuid(i.expectedPositionId)) return null;
  return { fn: EDITOR_POKEDEX_RPC.unassign, args: { p_collection_id: low(i.collectionId), p_copy_token: i.copyToken, p_expected_position_id: low(i.expectedPositionId) } };
}

/** expectedRepresentativeToken = null: a tela viu a escolha AUTOMÁTICA. */
export function buildChooseCall(i: { collectionId: string; copyToken: unknown; expectedPositionId: string; expectedRepresentativeToken: unknown | null }): RpcCall<ChooseArgs> | null {
  if (!i || !isUuid(i.collectionId) || !isCopyToken(i.copyToken) || !isUuid(i.expectedPositionId)) return null;
  const exp = i.expectedRepresentativeToken;
  if (exp !== null && !isCopyToken(exp)) return null;
  return {
    fn: EDITOR_POKEDEX_RPC.choose,
    args: { p_collection_id: low(i.collectionId), p_copy_token: i.copyToken, p_expected_position_id: low(i.expectedPositionId), p_expected_representative_token: exp as CopyToken | null },
  };
}

/** Exige o token da representante ESCOLHIDA que a tela viu (o servidor recusa NULL). */
export function buildRestoreCall(i: { collectionId: string; positionId: string; expectedRepresentativeToken: unknown }): RpcCall<RestoreArgs> | null {
  if (!i || !isUuid(i.collectionId) || !isUuid(i.positionId) || !isCopyToken(i.expectedRepresentativeToken)) return null;
  return { fn: EDITOR_POKEDEX_RPC.restore, args: { p_collection_id: low(i.collectionId), p_pokedex_position_id: low(i.positionId), p_expected_representative_token: i.expectedRepresentativeToken } };
}

// ---------------------------------------------------------------------------
// Resultados efetivos

export type MoveResult = { operation: "CREATED" | "MOVED" | "UNCHANGED"; positionId: string; previousPositionId: string | null; basis: AssignmentBasis | null; representativeCleared: boolean };
export type UnassignResult = { operation: "REMOVED" | "UNCHANGED"; previousPositionId: string | null; representativeCleared: boolean };
export type ChooseResult = { operation: "SET" | "REPLACED" | "UNCHANGED"; positionId: string };
export type RestoreResult = { operation: "CLEARED" | "UNCHANGED" };

function oneRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data;
  if (!row || typeof row !== "object" || Array.isArray(row) || hasForbiddenKey(row)) return null;
  return row as Record<string, unknown>;
}

const uuidOrNull = (v: unknown): v is string | null => v === null || isUuid(v);

/** Resultado fora do contrato → null (tratado como incerto: nunca repetir sozinho). */
export function parseMoveResult(data: unknown): MoveResult | null {
  const r = oneRow(data);
  if (!r) return null;
  const op = r.operation;
  if (op !== "CREATED" && op !== "MOVED" && op !== "UNCHANGED") return null;
  if (!isUuid(r.pokedex_position_id) || !uuidOrNull(r.previous_position_id) || typeof r.representative_cleared !== "boolean") return null;
  const basis = r.assignment_basis;
  if (basis !== null && basis !== "SPECIES_MATCH" && basis !== "USER_OVERRIDE") return null;
  if (op === "CREATED" && (r.previous_position_id !== null || r.representative_cleared || basis === null)) return null;
  if (op === "MOVED" && (r.previous_position_id === null || basis === null || r.previous_position_id === r.pokedex_position_id)) return null;
  if (op === "UNCHANGED" && (r.previous_position_id !== r.pokedex_position_id || r.representative_cleared)) return null;
  return { operation: op, positionId: low(r.pokedex_position_id), previousPositionId: r.previous_position_id === null ? null : low(r.previous_position_id as string), basis: basis as AssignmentBasis | null, representativeCleared: r.representative_cleared };
}

export function parseUnassignResult(data: unknown): UnassignResult | null {
  const r = oneRow(data);
  if (!r) return null;
  const op = r.operation;
  if (op !== "REMOVED" && op !== "UNCHANGED") return null;
  if (!uuidOrNull(r.previous_position_id) || typeof r.representative_cleared !== "boolean") return null;
  if (op === "REMOVED" && r.previous_position_id === null) return null;
  if (op === "UNCHANGED" && (r.previous_position_id !== null || r.representative_cleared)) return null;
  return { operation: op, previousPositionId: r.previous_position_id === null ? null : low(r.previous_position_id as string), representativeCleared: r.representative_cleared };
}

export function parseChooseResult(data: unknown): ChooseResult | null {
  const r = oneRow(data);
  if (!r) return null;
  const op = r.operation;
  if ((op !== "SET" && op !== "REPLACED" && op !== "UNCHANGED") || !isUuid(r.pokedex_position_id)) return null;
  return { operation: op, positionId: low(r.pokedex_position_id) };
}

export function parseRestoreResult(data: unknown): RestoreResult | null {
  const r = oneRow(data);
  if (!r) return null;
  const op = r.operation;
  return op === "CLEARED" || op === "UNCHANGED" ? { operation: op } : null;
}

export type AnyResult = MoveResult | UnassignResult | ChooseResult | RestoreResult;

/** Houve escrita? UNCHANGED nunca é sucesso de escrita. */
export function resultChanged(r: AnyResult): boolean {
  return r.operation !== "UNCHANGED";
}

export function resultMessage(r: AnyResult): string {
  switch (r.operation) {
    case "CREATED":
      return "A carta foi colocada nesta posição.";
    case "MOVED":
      return (r as MoveResult).representativeCleared
        ? "A carta foi movida para esta posição. Ela deixou de ser a representante da posição anterior."
        : "A carta foi movida para esta posição.";
    case "REMOVED":
      return (r as UnassignResult).representativeCleared
        ? "A carta saiu da posição. A posição voltou à representante automática."
        : "A carta saiu da posição.";
    case "SET":
      return "Esta carta agora representa a posição.";
    case "REPLACED":
      return "Esta carta passou a representar a posição.";
    case "CLEARED":
      return "A posição voltou à representante automática.";
    default:
      return "Nada mudou: a posição já estava assim.";
  }
}

// ---------------------------------------------------------------------------
// Recusas e política de reação

export type EditorPokedexFailure =
  | "barrier_closed"
  | "unavailable"
  | "not_authenticated"
  | "access_lost"
  | "archived"
  | "not_pokedex"
  | "state_changed"
  | "confirmation_required"
  | "copy_not_found"
  | "position_not_found"
  | "lock_busy"
  | "invalid"
  | "unknown";

/** Só o código e o NOME da exceção; hint/detail nunca são lidos. */
export function classifyEditorPokedexFailure(code: string | null | undefined, message: string | null | undefined): EditorPokedexFailure {
  const text = (message ?? "").trim();
  switch (text) {
    case "CAPABILITY_NOT_ENABLED":
      return "barrier_closed";
    case "STATE_CHANGED":
      return "state_changed";
    case "CONFIRMATION_REQUIRED":
      return "confirmation_required";
    case "COPY_NOT_FOUND":
      return "copy_not_found";
    case "POKEDEX_POSITION_NOT_FOUND":
      return "position_not_found";
    case "COLLECTION_NOT_FOUND":
      return "access_lost";
    case "COLLECTION_ARCHIVED":
      return "archived";
    case "NOT_POKEDEX_COLLECTION":
      return "not_pokedex";
    case "INVALID_ARGUMENT":
    case "INVALID_PAGE":
      return "invalid";
    case "not_authenticated":
      return "not_authenticated";
  }
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (code === "55P03") return "lock_busy";
  if (code === "28000") return "not_authenticated";
  if (code === "42501") return "access_lost";
  return "unknown";
}

export type FailurePolicy = {
  reason: EditorPokedexFailure;
  message: string;
  /** Nada foi gravado (recusa antes da escrita). */
  nothingWritten: boolean;
  /** Ações da Pokédex ficam indisponíveis nesta tela. */
  disables: boolean;
  /** Reler posição e lista antes de qualquer nova ação. */
  reloadState: boolean;
  /** Descartar todos os tokens já recebidos (nova geração). */
  invalidateTokens: boolean;
  /** Pedir confirmação explícita e só então reenviar com confirmação. */
  requireConfirmation: boolean;
  /** O usuário pode tentar de novo (manualmente). Nunca há repetição automática. */
  manualRetry: boolean;
  /** Pode ter sido gravado: conferir antes de repetir. */
  uncertain: boolean;
};

const MESSAGES: Record<EditorPokedexFailure, string> = {
  barrier_closed: "A edição compartilhada da Pokédex ainda não está disponível.",
  unavailable: "A edição compartilhada da Pokédex ainda não está disponível.",
  not_authenticated: "Sua sessão expirou. Entre de novo para continuar.",
  access_lost: "Sua permissão para organizar esta coleção mudou.",
  archived: "A coleção está arquivada. A Pokédex fica só para leitura.",
  not_pokedex: "Esta coleção não é uma Pokédex.",
  state_changed: "Esta posição mudou desde que você abriu. Atualizamos para você revisar.",
  confirmation_required: "Esta carta não é da espécie desta posição. Confirme se quer colocá-la mesmo assim.",
  copy_not_found: "Esta carta não está mais disponível como antes. A lista foi atualizada.",
  position_not_found: "Esta posição não faz parte da Pokédex desta coleção.",
  lock_busy: "A coleção está sendo alterada. Tente de novo em instantes.",
  invalid: "Não foi possível concluir. Nada foi alterado.",
  unknown: "Não foi possível confirmar o resultado. Atualize antes de tentar de novo.",
};

export function failurePolicy(reason: EditorPokedexFailure): FailurePolicy {
  const disables = ["barrier_closed", "unavailable", "not_authenticated", "access_lost", "archived", "not_pokedex"].includes(reason);
  return {
    reason,
    message: MESSAGES[reason],
    nothingWritten: reason !== "unknown",
    disables,
    reloadState: ["state_changed", "copy_not_found", "position_not_found", "unknown", "access_lost"].includes(reason),
    invalidateTokens: ["state_changed", "copy_not_found", "access_lost", "not_authenticated", "barrier_closed", "unknown"].includes(reason),
    requireConfirmation: reason === "confirmation_required",
    manualRetry: reason === "lock_busy" || reason === "state_changed" || reason === "copy_not_found",
    uncertain: reason === "unknown",
  };
}

/** Registro seguro: só a função e o motivo. Nunca token, ids, mensagem ou detalhe do banco. */
export function safeLogFields(fn: string, reason: EditorPokedexFailure): { fn: string; reason: EditorPokedexFailure } {
  const known = (Object.values(EDITOR_POKEDEX_RPC) as string[]).includes(fn) ? fn : "editor_pokedex_unknown";
  return { fn: known, reason };
}

/** Controles aparecem? Configuração D1 ligada, papel EDITOR, coleção ativa e barreira não recusada nesta tela. */
export function canShowEditorPokedexActions(i: { flagOn: boolean; role: "EDITOR" | "VIEWER" | null; archived: boolean; refusal: EditorPokedexFailure | null }): boolean {
  return i.flagOn && i.role === "EDITOR" && !i.archived && !(i.refusal && failurePolicy(i.refusal).disables);
}
