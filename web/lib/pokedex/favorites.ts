/**
 * Espécie favorita — regras puras (Pokédex P6, 2026-10-15).
 *
 * Contrato do banco (Queries 6136/6137, implantadas na P6.2): a identidade é sempre
 * `auth.uid()` — o cliente nunca envia `user_id`. `get_my_pokedex_favorites()` devolve
 * os números nacionais favoritos em ordem; `set_pokedex_species_favorite(número,
 * desejado)` DEFINE o estado (não alterna) e é idempotente.
 *
 * Este módulo não faz I/O: recorte da galeria, a máquina de intenção por espécie
 * (otimista, serializada, última intenção vence) e os textos de anúncio/erro. Testado
 * por `favorites.test.ts` (node --test).
 */

// ---------------------------------------------------------------------------
// Recorte da galeria
// ---------------------------------------------------------------------------

/**
 * Recorte da página Pokémons Favoritos: mantém, na ordem recebida (nacional), só as
 * espécies favoritas. Aplicado sobre a lista que já veio de 6131 (pesquisa/geração),
 * antes do filtro por tipo (P5a) — nenhuma consulta por card.
 */
export function applyFavoritesFilter<T extends { national_dex_number: number }>(
  species: readonly T[],
  favorites: ReadonlySet<number>,
): T[] {
  return species.filter((item) => favorites.has(item.national_dex_number));
}

/**
 * Página Pokémons Favoritos — galeria contínua (Correção de UX-01, 2026-10-15): a
 * geração é um filtro, não uma divisão da grade. A lista vem de 6131 sem filtro de
 * geração (só a pesquisa), e a geração é aplicada aqui — assim o filtro compacto sabe
 * quantos favoritos existem em cada geração sem nenhuma leitura extra.
 */
export function filterByGeneration<T extends { generation_ordinal: number }>(species: readonly T[], generation: number | null): T[] {
  return generation === null ? [...species] : species.filter((item) => item.generation_ordinal === generation);
}

/** Quantos itens por geração (ordinal) — contagens do filtro compacto de geração. */
export function countByGeneration(species: readonly { generation_ordinal: number }[]): Map<number, number> {
  const counts = new Map<number, number>();
  for (const item of species) counts.set(item.generation_ordinal, (counts.get(item.generation_ordinal) ?? 0) + 1);
  return counts;
}

/** Números válidos de espécie (mesma faixa da função SQL: 1..9999). */
export function isValidNationalDexNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= 1 && value <= 9999;
}

/**
 * Normaliza as linhas de `get_my_pokedex_favorites()` num conjunto. Linhas fora do
 * contrato (número ausente, não inteiro ou fora da faixa) são descartadas, nunca
 * propagadas para a interface.
 */
export function toFavoriteSet(rows: readonly { national_dex_number?: unknown }[]): Set<number> {
  const set = new Set<number>();
  for (const row of rows) {
    const value = typeof row.national_dex_number === "string" ? Number(row.national_dex_number) : row.national_dex_number;
    if (isValidNationalDexNumber(value)) set.add(value);
  }
  return set;
}

// ---------------------------------------------------------------------------
// Máquina de intenção por espécie (otimista, serializada, última intenção vence)
// ---------------------------------------------------------------------------

/**
 * Estado de uma espécie na interface.
 * - `confirmed`: último estado confirmado pelo servidor (ou o estado inicial da página).
 * - `desired`: o que a interface mostra — a última intenção do usuário.
 * - `inFlight`: há uma gravação em andamento para esta espécie.
 *
 * Invariante: no máximo UMA gravação por espécie em andamento. Cliques durante a
 * gravação só mudam `desired`; quando a gravação termina, se `desired` ainda diverge
 * do confirmado, uma nova gravação é enviada com o valor ATUAL. Assim o estado final
 * no servidor é sempre a última intenção, e uma resposta atrasada nunca inverte a tela.
 */
export type FavoriteEntry = { confirmed: boolean; desired: boolean; inFlight: boolean };

/** Gravação a disparar: `set_pokedex_species_favorite(number, value)`. */
export type FavoriteSend = { number: number; value: boolean };

export type FavoriteStep = { entry: FavoriteEntry; send: FavoriteSend | null };

export function initialFavoriteEntry(isFavorite: boolean): FavoriteEntry {
  return { confirmed: isFavorite, desired: isFavorite, inFlight: false };
}

/** Clique no coração: inverte o que está na tela e grava, se nada estiver em andamento. */
export function toggleFavorite(number: number, entry: FavoriteEntry): FavoriteStep {
  const desired = !entry.desired;
  if (entry.inFlight || desired === entry.confirmed) {
    // Em andamento: a gravação seguinte (se ainda necessária) sai no settle.
    // Sem andamento e voltou ao confirmado: nada a gravar.
    return { entry: { ...entry, desired }, send: null };
  }
  return { entry: { ...entry, desired, inFlight: true }, send: { number, value: desired } };
}

export type FavoriteOutcome = { ok: true; value: boolean } | { ok: false };

export type FavoriteSettle = FavoriteStep & {
  /** A gravação falhou e a tela voltou ao último estado confirmado. */
  reverted: boolean;
};

/**
 * Fim de uma gravação.
 * - Sucesso: `confirmed` passa ao valor gravado; se o usuário mudou de ideia nesse
 *   meio-tempo, uma nova gravação sai com a intenção atual.
 * - Falha: a tela volta ao último estado confirmado (nada fica "favoritado de
 *   mentira") e a falha é sinalizada para a mensagem inline.
 */
export function settleFavorite(number: number, entry: FavoriteEntry, outcome: FavoriteOutcome): FavoriteSettle {
  if (!outcome.ok) {
    return { entry: { confirmed: entry.confirmed, desired: entry.confirmed, inFlight: false }, send: null, reverted: true };
  }
  const confirmed = outcome.value;
  if (entry.desired !== confirmed) {
    return { entry: { confirmed, desired: entry.desired, inFlight: true }, send: { number, value: entry.desired }, reverted: false };
  }
  return { entry: { confirmed, desired: entry.desired, inFlight: false }, send: null, reverted: false };
}

// ---------------------------------------------------------------------------
// Resultado da Server Action e textos
// ---------------------------------------------------------------------------

export type FavoriteFailureReason = "not_authenticated" | "invalid" | "not_found" | "unavailable" | "failed";

export type SetFavoriteResult = { ok: true; favorite: boolean } | { ok: false; reason: FavoriteFailureReason };

/** PostgREST: função ausente no cache de schema. */
const FUNCTION_NOT_FOUND = "PGRST202";

/** SQLSTATE/código do erro do banco -> motivo exibível (sem detalhes técnicos). */
export function favoriteFailureReason(code: string | null | undefined): FavoriteFailureReason {
  switch (code) {
    case "28000":
    case "42501":
      return "not_authenticated";
    case "22023":
      return "invalid";
    case "P0002":
      return "not_found";
    case FUNCTION_NOT_FOUND:
      return "unavailable";
    default:
      return "failed";
  }
}

/**
 * Nome acessível do botão-coração da galeria. Constante: o estado vai em `aria-pressed`
 * (padrão WAI-ARIA de botão de alternância — "Favoritar Pikachu, pressionado"); trocar o
 * nome e o estado ao mesmo tempo faria o leitor de tela anunciar o contrário.
 */
export function favoriteToggleLabel(speciesName: string): string {
  return `${TOGGLE_LABEL_PREFIX}${speciesName}`;
}

const TOGGLE_LABEL_PREFIX = "Favoritar ";

/**
 * Nome da espécie a partir do nome acessível do botão da galeria (o card não repete o
 * nome num atributo próprio — HTML mínimo por card). `null` se o rótulo não for o
 * esperado.
 */
export function favoriteSpeciesNameFromLabel(label: string | null | undefined): string | null {
  if (!label || !label.startsWith(TOGGLE_LABEL_PREFIX)) return null;
  const name = label.slice(TOGGLE_LABEL_PREFIX.length).trim();
  return name === "" ? null : name;
}

/** Dica visual (atributo `title`) com a ação que o próximo clique fará (ficha). */
export function favoriteActionHint(isFavorite: boolean): string {
  return isFavorite ? "Remover dos favoritos" : "Adicionar aos favoritos";
}

/** Anúncio da região aria-live após a confirmação. */
export function favoriteAnnouncement(speciesName: string, isFavorite: boolean): string {
  return isFavorite ? `${speciesName} adicionado aos favoritos.` : `${speciesName} removido dos favoritos.`;
}

/** Mensagem inline de falha (STD-004): o que aconteceu e o que fazer. */
export function favoriteErrorMessage(speciesName: string, reason: FavoriteFailureReason): string {
  switch (reason) {
    case "not_authenticated":
      return `Sua sessão expirou. Entre novamente para favoritar ${speciesName}.`;
    case "not_found":
      return `${speciesName} não está disponível para favoritar no momento.`;
    case "unavailable":
      return "Os favoritos estão indisponíveis no momento. Tente novamente mais tarde.";
    case "invalid":
    case "failed":
    default:
      return `Não foi possível atualizar ${speciesName}. Nada foi alterado — tente novamente.`;
  }
}
