/**
 * Pokédex — vincular cartas às posições (PKX-03). Camada pura: leitura das
 * linhas dos contratos 5208–5211, classificação de erros e textos. Sem
 * Supabase, sem React — testável com `node --test`.
 *
 * Contratos:
 * - 5208 candidatos por posição (SPECIES = mesma espécie; ACERVO = exceção);
 * - 5209 exemplares vinculados a uma posição;
 * - 5210 vincular UM exemplar (normal sem confirmação; exceção com confirmação);
 * - 5211 prévia do lote (um exemplar livre sugerido por Pokémon que falta).
 * Reutilizados: 5046 (lote), 6124 (retirar o vínculo), 6125 (representante),
 * 5047 (tirar da coleção).
 */
import { formatDex } from "./pokedex.ts";

/** Escopo de busca da 5208. */
export type LinkScope = "SPECIES" | "ACERVO";

/** Página da 5208 (1..100). */
export const LINK_CANDIDATES_PAGE_SIZE = 24;
/** Teto da 5046 por chamada — o mesmo da prévia do lote (5211). */
export const POKEDEX_BULK_MAX = 500;
/** Busca da exceção: o contrato aceita até 100 caracteres. */
export const LINK_QUERY_MAX = 100;

export type CopyAttributes = {
  variantLabel: string | null;
  isDefaultVariant: boolean;
  languageCode: string;
  languageName: string;
  storageName: string | null;
};

export type PokedexLinkCandidate = CopyAttributes & {
  physicalCardId: string;
  cardName: string;
  collectorNumber: string;
  setCode: string;
  setName: string;
  imagePath: string | null;
  addedAt: string;
  /** Já está nesta coleção, sem posição (depois de "retirar desta posição"). */
  inThisCollection: boolean;
  /** Espécie principal da carta no catálogo (nula: Treinador, Energia ou sem espécie resolvida). */
  cardSpeciesName: string | null;
  cardSpeciesNumber: number | null;
  speciesMatch: boolean;
};

export type PokedexPositionCopy = CopyAttributes & {
  allocationId: string;
  physicalCardId: string;
  cardName: string;
  collectorNumber: string;
  setCode: string;
  setName: string;
  imagePath: string | null;
  basis: "SPECIES_MATCH" | "USER_OVERRIDE";
  assignedAt: string;
  isRepresentative: boolean;
  cardSpeciesName: string | null;
  cardSpeciesNumber: number | null;
};

export type BulkPreviewItem = {
  positionId: string;
  number: number;
  speciesName: string;
  artworkPath: string | null;
  eligibleCount: number;
  physicalCardId: string;
  cardName: string;
  collectorNumber: string;
  setCode: string;
  variantLabel: string | null;
  languageCode: string;
  languageName: string;
  storageName: string | null;
  imagePath: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function int(value: unknown): number | null {
  const parsed = typeof value === "number" ? value : typeof value === "string" ? Number(value) : Number.NaN;
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

function uuid(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value) ? value : null;
}

function attributes(row: Record<string, unknown>): CopyAttributes {
  return {
    variantLabel: text(row.variant_label),
    isDefaultVariant: row.is_default_variant === true,
    languageCode: text(row.language_code) ?? "",
    languageName: text(row.language_name) ?? text(row.language_code) ?? "",
    storageName: text(row.storage_name),
  };
}

/** Linhas da 5208 → candidatos válidos + total antes da paginação. Linha malformada é descartada. */
export function parsePokedexLinkCandidates(rows: unknown): { items: PokedexLinkCandidate[]; total: number } {
  if (!Array.isArray(rows)) return { items: [], total: 0 };
  const items: PokedexLinkCandidate[] = [];
  let total = 0;
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const id = uuid(row.physical_card_id);
    const name = text(row.card_name);
    if (!id || !name) continue;
    total = Math.max(total, int(row.total_count) ?? 0);
    items.push({
      ...attributes(row),
      physicalCardId: id,
      cardName: name,
      collectorNumber: text(row.collector_number) ?? "",
      setCode: text(row.card_set_code) ?? "",
      setName: text(row.card_set_name) ?? "",
      imagePath: text(row.image_path),
      addedAt: text(row.added_at) ?? "",
      inThisCollection: row.in_this_collection === true,
      cardSpeciesName: text(row.card_species_name),
      cardSpeciesNumber: int(row.card_species_number),
      speciesMatch: row.species_match === true,
    });
  }
  return { items, total: Math.max(total, items.length) };
}

/** Linhas da 5209 → exemplares vinculados (representante primeiro, como o banco devolve). */
export function parsePokedexPositionCopies(rows: unknown): { items: PokedexPositionCopy[]; total: number } {
  if (!Array.isArray(rows)) return { items: [], total: 0 };
  const items: PokedexPositionCopy[] = [];
  let total = 0;
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const allocationId = uuid(row.collection_allocation_id);
    const id = uuid(row.physical_card_id);
    const name = text(row.card_name);
    const basis = row.assignment_basis;
    if (!allocationId || !id || !name || (basis !== "SPECIES_MATCH" && basis !== "USER_OVERRIDE")) continue;
    total = Math.max(total, int(row.total_count) ?? 0);
    items.push({
      ...attributes(row),
      allocationId,
      physicalCardId: id,
      cardName: name,
      collectorNumber: text(row.collector_number) ?? "",
      setCode: text(row.card_set_code) ?? "",
      setName: text(row.card_set_name) ?? "",
      imagePath: text(row.image_path),
      basis,
      assignedAt: text(row.assigned_at) ?? "",
      isRepresentative: row.is_representative === true,
      cardSpeciesName: text(row.card_species_name),
      cardSpeciesNumber: int(row.card_species_number),
    });
  }
  return { items, total: Math.max(total, items.length) };
}

/** Linhas da 5211 → prévia do lote; `missingTotal` = posições que faltam no filtro (com ou sem carta). */
export function parseBulkPreview(rows: unknown): { items: BulkPreviewItem[]; missingTotal: number; total: number } {
  if (!Array.isArray(rows)) return { items: [], missingTotal: 0, total: 0 };
  const items: BulkPreviewItem[] = [];
  const seenCopies = new Set<string>();
  let missingTotal = 0;
  let total = 0;
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const positionId = uuid(row.pokedex_position_id);
    const copyId = uuid(row.physical_card_id);
    const number = int(row.position_number);
    const speciesName = text(row.species_name);
    const cardName = text(row.card_name);
    if (!positionId || !copyId || number === null || !speciesName || !cardName) continue;
    // Um exemplar nunca entra duas vezes (o banco já garante; aqui é defesa).
    if (seenCopies.has(copyId)) continue;
    seenCopies.add(copyId);
    missingTotal = Math.max(missingTotal, int(row.missing_total) ?? 0);
    total = Math.max(total, int(row.total_count) ?? 0);
    items.push({
      positionId,
      number,
      speciesName,
      artworkPath: text(row.species_artwork_path),
      eligibleCount: Math.max(1, int(row.eligible_count) ?? 1),
      physicalCardId: copyId,
      cardName,
      collectorNumber: text(row.collector_number) ?? "",
      setCode: text(row.card_set_code) ?? "",
      variantLabel: text(row.variant_label),
      languageCode: text(row.language_code) ?? "",
      languageName: text(row.language_name) ?? text(row.language_code) ?? "",
      storageName: text(row.storage_name),
      imagePath: text(row.image_path),
    });
  }
  return { items, missingTotal: Math.max(missingTotal, items.length), total: Math.max(total, items.length) };
}

/** "Português · Holo · Caixa azul" — idioma, acabamento/edição e local, nessa ordem; só o que existe. */
export function copyAttributesLine(copy: CopyAttributes): string {
  return [copy.languageName, copy.variantLabel ?? (copy.isDefaultVariant ? null : "Variante"), copy.storageName]
    .filter((part): part is string => typeof part === "string" && part.trim() !== "")
    .join(" · ");
}

/** "SVI · 025/198" */
export function cardIdentityLine(card: { setCode: string; collectorNumber: string }): string {
  return [card.setCode.toUpperCase(), card.collectorNumber].filter((part) => part !== "").join(" · ");
}

/** "Pikachu (#0025)" ou, sem espécie catalogada, null. */
export function speciesLabel(name: string | null, number: number | null): string | null {
  if (!name) return null;
  return number !== null && number > 0 ? `${name} (#${formatDex(number)})` : name;
}

/**
 * Aviso do vínculo excepcional — explica a divergência sem jargão e deixa
 * claro que o catálogo não muda.
 */
export function exceptionWarning(input: {
  cardName: string;
  cardSpeciesName: string | null;
  cardSpeciesNumber: number | null;
  positionSpeciesName: string;
  positionNumber: number;
}): { title: string; body: string } {
  const target = speciesLabel(input.positionSpeciesName, input.positionNumber) ?? input.positionSpeciesName;
  const own = speciesLabel(input.cardSpeciesName, input.cardSpeciesNumber);
  return {
    title: own ? `Esta carta é de ${own}` : "Esta carta não tem um Pokémon catalogado",
    body: own
      ? `“${input.cardName}” vai ocupar a posição de ${target} só nesta coleção. No catálogo, ela continua sendo de ${input.cardSpeciesName}.`
      : `“${input.cardName}” vai ocupar a posição de ${target} só nesta coleção. No catálogo, nada muda.`,
  };
}

/** Explicação curta de um vínculo excepcional já feito (lista "Nesta posição"). */
export function exceptionNote(copy: { cardSpeciesName: string | null; cardSpeciesNumber: number | null }): string {
  const own = speciesLabel(copy.cardSpeciesName, copy.cardSpeciesNumber);
  return own ? `Exceção · carta de ${own}` : "Exceção · carta sem Pokémon catalogado";
}

export type LinkFailure =
  | "not_authenticated"
  | "confirmation_required"
  | "copy_elsewhere"
  | "copy_already_linked"
  | "copy_not_found"
  | "position_out_of_scope"
  | "already_linked"
  | "not_found"
  | "archived"
  | "invalid"
  | "disabled"
  | "not_deployed"
  | "unavailable";

/** Pelo SQLSTATE e pela mensagem estável dos contratos (5210, 5046, 6122, 6124, 6125) — o texto cru nunca chega ao usuário. */
export function classifyLinkFailure(code: string | null | undefined, message: string | null | undefined): LinkFailure {
  const textValue = message ?? "";
  // Contrato ainda não aplicado no banco (PostgREST não acha a função / função inexistente).
  if (code === "PGRST202" || code === "42883") return "not_deployed";
  if (code === "28000" || code === "42501" || textValue === "not_authenticated" || textValue === "authentication required") {
    return "not_authenticated";
  }
  if (textValue === "EXCEPTION_CONFIRMATION_REQUIRED" || textValue.startsWith("SET_POKEDEX_POSITION_ASSIGNMENT_CONFIRMATION_REQUIRED")) {
    return "confirmation_required";
  }
  if (textValue === "COPY_IN_OTHER_COLLECTION") return "copy_elsewhere";
  if (textValue === "COPY_ALREADY_LINKED") return "copy_already_linked";
  if (textValue === "COPY_NOT_FOUND") return "copy_not_found";
  if (textValue === "POSITION_NOT_IN_SCOPE") return "position_out_of_scope";
  // 5046: exemplar alocado por outra ação entre a revisão e a confirmação (ou UNIQUE).
  if (code === "23505" || textValue.includes("já estão alocadas")) return "already_linked";
  if (textValue.includes("NOT_FOUND") || textValue.includes("NOT_ALLOCATED") || textValue === "COLLECTION_NOT_FOUND" || code === "P0002") {
    return "not_found";
  }
  if (textValue === "COLLECTION_ARCHIVED" || textValue.includes("ARCHIVED") || textValue.includes("archived")) return "archived";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unavailable";
}

export function linkFailureMessage(reason: LinkFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "confirmation_required":
      return "Esta carta é de outro Pokémon. Confirme a exceção para colocá-la nesta posição.";
    case "copy_elsewhere":
      return "Esta carta está em outra coleção. Tire-a de lá antes — nada foi alterado.";
    case "copy_already_linked":
      return "Esta carta já ocupa outra posição desta coleção. Retire-a de lá antes — nada foi alterado.";
    case "copy_not_found":
      return "Esta carta não está mais no seu acervo. A lista foi atualizada.";
    case "position_out_of_scope":
      return "Este Pokémon não faz parte das gerações desta coleção. Inclua a geração em Ajustes, se quiser.";
    case "already_linked":
      return "Uma das cartas mudou de lugar enquanto você revisava. Nada foi adicionado — revise de novo.";
    case "not_found":
      return "Isso não está mais disponível. A coleção foi atualizada — tente de novo.";
    case "archived":
      return "Esta coleção está arquivada e não aceita mudanças. Nada foi alterado.";
    case "invalid":
      return "Algo no pedido não está certo. Revise e tente de novo.";
    case "not_deployed":
      return "O vínculo de cartas ainda não foi ativado no banco de dados deste ambiente. Nada foi alterado.";
    case "disabled":
      return "Este recurso ainda não está disponível.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente em instantes.";
  }
}

/** Ids do lote: únicos, válidos e dentro do teto da 5046. `null` = pedido inválido. */
export function normalizeBulkIds(value: unknown): string[] | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const ids = [...new Set(value)];
  if (ids.length > POKEDEX_BULK_MAX) return null;
  return ids.every((id) => typeof id === "string" && UUID.test(id)) ? (ids as string[]) : null;
}

/** O que ficou de fora do lote, em linguagem de colecionador. */
export function bulkLeftover(input: { missingTotal: number; offered: number; linked: number }): string | null {
  const notOffered = Math.max(0, input.missingTotal - input.offered);
  const skipped = Math.max(0, input.offered - input.linked);
  const parts: string[] = [];
  if (skipped > 0) parts.push(`${skipped} ${skipped === 1 ? "ficou desmarcado" : "ficaram desmarcados"}`);
  if (notOffered > 0) {
    parts.push(
      `${notOffered} ${notOffered === 1 ? "Pokémon ainda não tem" : "Pokémon ainda não têm"} carta livre da mesma espécie no seu acervo`,
    );
  }
  return parts.length > 0 ? `${parts.join("; ")}.` : null;
}
