/**
 * Minhas coleções — regras puras de apresentação, URL e tradução de erros
 * (MY-COLLECTIONS-FRONTEND-01).
 *
 * Sem React, sem Supabase, sem rede: testável com
 * `node --experimental-strip-types --test lib/colecoes/colecoes.test.ts`.
 *
 * Contratos (LIVE, 5166–5170): CT-01 `create_my_card_set_collection`,
 * R1 `get_my_collections`, R2 `get_my_collection_positions`,
 * R3 `get_my_collection_link_candidates`. A escrita do vínculo continua sendo
 * `allocate_physical_cards_to_collection` (5046). Nenhuma regra de domínio
 * mora aqui — só forma, texto e decisões de interface.
 */

import { POKEDEX_COLLECTION_ENABLED } from "./pokedex.ts";

export const COLECOES_PATH = "/colecoes/colecoes";
/** Página da Biblioteca — R1 aceita até 100. */
export const LIBRARY_PAGE_SIZE = 48;
/** R2 aceita até 500; o maior Set do catálogo tem 300 cartas — uma página basta. */
export const POSITIONS_PAGE_SIZE = 500;
/** Teto por chamada de 5046 e de R3. */
export const LINK_BATCH_SIZE = 500;
/** Limite de nome no formulário (o banco só exige não vazio). */
export const COLLECTION_NAME_MAX = 80;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SET_CODE = /^[A-Za-z0-9.-]{1,32}$/;
const MAX_PAGE = 2000;

type Params = Record<string, string | string[] | undefined>;

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export function isCollectionId(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

export function isSetCode(value: unknown): value is string {
  return typeof value === "string" && SET_CODE.test(value);
}

// ---------------------------------------------------------------------------
// URL
// ---------------------------------------------------------------------------

/** Filtro da coleção: Todas · Tenho · Faltam (N10). Valor na URL em pt-BR. */
export type PositionFilter = "todas" | "tenho" | "faltam";

export function parseLibraryPage(params: Params): number {
  const raw = first(params.pagina) ?? "";
  const page = /^\d{1,4}$/.test(raw) ? Number(raw) : 1;
  return Math.min(Math.max(page, 1), MAX_PAGE);
}

export function libraryHref(page = 1): string {
  return page > 1 ? `${COLECOES_PATH}?pagina=${page}` : COLECOES_PATH;
}

/**
 * Modo de visualização da Biblioteca (North Star NS-17): Cards (padrão), Lista
 * e Carrossel. Os três mostram os mesmos dados da mesma página — trocar de modo
 * não consulta nada. A preferência fica na URL (`?modo=`) e num cookie do
 * próprio navegador (sem banco, sem configuração de conta); a URL vence o cookie.
 */
export const LIBRARY_MODES = ["cards", "lista", "carrossel"] as const;
export type LibraryMode = (typeof LIBRARY_MODES)[number];
export const LIBRARY_MODE_PARAM = "modo";
export const LIBRARY_MODE_COOKIE = "mmkyu_colecoes_modo";

export function isLibraryMode(value: unknown): value is LibraryMode {
  return typeof value === "string" && (LIBRARY_MODES as readonly string[]).includes(value);
}

/** URL primeiro, depois o cookie; qualquer valor estranho cai em Cards. */
export function resolveLibraryMode(params: Params, cookieValue: string | undefined): LibraryMode {
  const fromUrl = first(params[LIBRARY_MODE_PARAM]);
  if (isLibraryMode(fromUrl)) return fromUrl;
  return isLibraryMode(cookieValue) ? cookieValue : "cards";
}

/** Busca da URL com o modo aplicado (Cards some da URL), preservando os demais parâmetros. */
export function librarySearchWithMode(search: string, mode: LibraryMode): string {
  const params = new URLSearchParams(search);
  if (mode === "cards") params.delete(LIBRARY_MODE_PARAM);
  else params.set(LIBRARY_MODE_PARAM, mode);
  const query = params.toString();
  return query ? `?${query}` : "";
}

export function parsePositionFilter(params: Params): PositionFilter {
  const raw = first(params.ver);
  return raw === "tenho" || raw === "faltam" ? raw : "todas";
}

export function collectionHref(id: string, filter: PositionFilter = "todas"): string {
  const base = `${COLECOES_PATH}/${id}`;
  return filter === "todas" ? base : `${base}?ver=${filter}`;
}

/** Filtro da interface → parâmetro de R2. */
export function toPositionsRpcFilter(filter: PositionFilter): "ALL" | "OWNED" | "MISSING" {
  if (filter === "tenho") return "OWNED";
  if (filter === "faltam") return "MISSING";
  return "ALL";
}

export function libraryTotalPages(total: number): number {
  return Math.max(1, Math.ceil(total / LIBRARY_PAGE_SIZE));
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

/** "146 de 158" (N10). */
export function progressLabel(satisfied: number, total: number): string {
  const format = new Intl.NumberFormat("pt-BR");
  return `${format.format(satisfied)} de ${format.format(total)}`;
}

/** Percentual inteiro para leitura e para a barra (0–100, nunca arredonda 99,6 para 100). */
export function progressPercent(satisfied: number, total: number): number {
  if (total <= 0) return 0;
  if (satisfied >= total) return 100;
  return Math.min(99, Math.floor((satisfied / total) * 100));
}

/**
 * Percentual para leitura (UX-02): com ao menos uma conquista, nunca "0%" —
 * 1 de 1.025 vira "<1%", para a conquista não parecer não ter contado.
 */
export function progressPercentText(satisfied: number, total: number): string {
  const percent = progressPercent(satisfied, total);
  return percent === 0 && satisfied > 0 && total > 0 ? "<1%" : `${percent}%`;
}

/** Largura da barra (0–100): com ao menos uma conquista, um mínimo visível (1%). */
export function progressBarPercent(satisfied: number, total: number): number {
  const percent = progressPercent(satisfied, total);
  return percent === 0 && satisfied > 0 && total > 0 ? 1 : percent;
}

/**
 * Resumo do conjunto para o cabeçalho da Biblioteca. Só existe quando a página
 * contém TODAS as coleções (total ≤ tamanho da página): somar uma página parcial
 * mostraria números errados, então nesse caso devolve `null` e o cabeçalho
 * mostra só o total (que vem do banco). Coleções sem universo (Coleção livre)
 * não entram no progresso geral. A Pokédex também fica fora de "cartas
 * reunidas" e do progresso geral: suas posições são Pokémon conquistados, não
 * cartas — somá-las misturaria grandezas. O progresso dela aparece na própria
 * coleção; "completas" continua contando todas.
 */
export type LibrarySummary = {
  collections: number;
  ownedCards: number;
  targetCards: number;
  overallPercent: number;
  complete: number;
};

export function librarySummary(
  items: readonly {
    satisfiedPositions: number;
    totalPositions: number;
    isComplete: boolean;
    completionPolicy?: string | null;
  }[],
  total: number,
): LibrarySummary | null {
  if (total <= 0 || items.length < total) return null;
  let ownedCards = 0;
  let targetCards = 0;
  let complete = 0;
  for (const item of items) {
    if (item.totalPositions > 0 && item.completionPolicy !== "REFERENCE_POSITION") {
      ownedCards += Math.min(item.satisfiedPositions, item.totalPositions);
      targetCards += item.totalPositions;
    }
    if (item.isComplete) complete += 1;
  }
  return { collections: total, ownedCards, targetCards, overallPercent: progressPercent(ownedCards, targetCards), complete };
}

/**
 * Leitura do progresso de uma coleção para Lista e Carrossel. Coleção sem
 * universo (Coleção livre, 0 posições) não tem meta: mostra quantas cartas
 * reúne em vez de "0 de 0".
 */
export type CollectionProgressView =
  | { kind: "goal"; percent: number; percentText: string; barPercent: number; label: string; complete: boolean }
  | { kind: "free"; copies: number };

export function collectionProgressView(collection: {
  totalPositions: number;
  satisfiedPositions: number;
  isComplete: boolean;
  copiesCount: number;
}): CollectionProgressView {
  if (collection.totalPositions <= 0) return { kind: "free", copies: Math.max(0, collection.copiesCount) };
  return {
    kind: "goal",
    percent: progressPercent(collection.satisfiedPositions, collection.totalPositions),
    percentText: progressPercentText(collection.satisfiedPositions, collection.totalPositions),
    barPercent: progressBarPercent(collection.satisfiedPositions, collection.totalPositions),
    label: progressLabel(collection.satisfiedPositions, collection.totalPositions),
    complete: collection.isComplete,
  };
}

/** "Base Set · BS" ou, sem Set, o tipo da coleção em linguagem de colecionador. */
export function collectionSubtitle(collection: {
  cardSetName: string | null;
  cardSetCode: string | null;
  completionPolicy: string | null;
  /** Código opcional da Coleção livre (5179); ausente/nulo = sem código. */
  coverCode?: string | null;
}): string {
  const code = collection.cardSetCode?.toUpperCase() ?? null;
  if (collection.cardSetName) return `${collection.cardSetName}${code ? ` · ${code}` : ""}`;
  const kind = collectionKindLabel(collection.completionPolicy);
  return collection.coverCode ? `${kind} · ${collection.coverCode}` : kind;
}

/**
 * Cartas do hero de uma coleção (COLLECTION DETAIL UX REFINEMENT-01).
 *
 * Determinístico e só com dados já lidos (R2): não há raridade em R2, então
 * "secreta" = número de colecionador numérico acima do total impresso
 * (ex.: 158/128). Ordem: secretas do número mais alto para o mais baixo (o fim
 * do Set concentra as artes especiais); com menos de 5 secretas, completa com
 * as cartas de número mais alto (FAN REFINEMENT-03). Só entram cartas com imagem.
 * Representa o Set, não a posse: cada item informa se o colecionador já tem a
 * carta, para a interface não sugerir posse que não existe.
 */
export type HeroCardSource = {
  cardId: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  imagePath: string | null;
  isSatisfied: boolean;
};

export type HeroSelection<T extends HeroCardSource> = { cards: T[]; secret: number };

function numericCollector(value: string): number | null {
  return /^\d+$/.test(value) ? Number(value) : null;
}

/**
 * Curadoria editorial do hero por Card Set (código em minúsculas → números de
 * colecionador, na ordem dos slots: frente, esquerda, direita, extrema
 * esquerda, extrema direita). Só escolhe entre cartas do próprio Set que têm
 * imagem; o que faltar é completado pela regra automática. Vale para qualquer
 * coleção do Set — representa o Set, não a posse.
 */
const HERO_CURATION: Readonly<Record<string, readonly number[]>> = {
  // Celebração de 30 Anos: 158 no lugar da 156 e 149 no lugar da 158 (2026-10-17).
  "me5.5": [149, 157, 158, 155, 154],
  // Coleção Clássica 30 Anos: 030 no lugar da 028 e 001 no lugar da 030 (2026-10-17).
  "me5.5cc": [1, 29, 30, 27, 26],
};

/**
 * Seleção determinística (FAN REFINEMENT-03): até `max` cartas distintas com
 * imagem — primeiro a curadoria do Set (se houver), depois as secretas (número
 * > total impresso), as de número mais alto e por último as de número não
 * numérico (ex.: TG01), em ordem estável. Nunca repete nem inventa: com menos
 * elegíveis, devolve só as que há.
 */
export function pickHeroCards<T extends HeroCardSource>(
  positions: readonly T[],
  max = 5,
  setCode: string | null = null,
): HeroSelection<T> {
  const withArt = positions.filter((position) => position.imagePath);
  const ranked = withArt
    .map((position) => ({ position, number: numericCollector(position.collectorNumber) }))
    .filter((entry): entry is { position: T; number: number } => entry.number !== null)
    .sort((a, b) => b.number - a.number || a.position.cardId.localeCompare(b.position.cardId));
  const isSecret = (entry: { position: T; number: number }) =>
    entry.position.collectorTotal !== null && entry.position.collectorTotal > 0 && entry.number > entry.position.collectorTotal;
  const secretIds = new Set(ranked.filter(isSecret).map((entry) => entry.position.cardId));
  const curated = (setCode ? HERO_CURATION[setCode.toLowerCase()] : undefined) ?? [];
  const byNumber = new Map<number, T>();
  for (const entry of ranked) if (!byNumber.has(entry.number)) byNumber.set(entry.number, entry.position);
  const candidates = [
    ...curated.map((number) => byNumber.get(number)).filter((position): position is T => position !== undefined),
    ...ranked.filter(isSecret).map((entry) => entry.position),
    ...ranked.map((entry) => entry.position),
    ...withArt
      .filter((position) => numericCollector(position.collectorNumber) === null)
      .sort((a, b) => a.collectorNumber.localeCompare(b.collectorNumber) || a.cardId.localeCompare(b.cardId)),
  ];
  const cards: T[] = [];
  const seen = new Set<string>();
  for (const position of candidates) {
    if (cards.length >= max) break;
    if (seen.has(position.cardId)) continue;
    seen.add(position.cardId);
    cards.push(position);
  }
  return { cards, secret: cards.filter((card) => secretIds.has(card.cardId)).length };
}

export function missingCount(satisfied: number, total: number): number {
  return Math.max(0, total - satisfied);
}

/** NS-14 / N8–N9: a política aparece para o colecionador assim — nunca o enum. */
export function collectionKindLabel(policy: string | null): string {
  if (policy === "STANDARD_SET") return "Set padrão — uma de cada carta";
  if (policy === "MASTER_SET") return "Master Set — os acabamentos que você escolher";
  if (policy === "NONE") return "Coleção livre";
  if (policy === "REFERENCE_POSITION") return "Completar a Pokédex";
  return "Coleção";
}

/**
 * Selo de tipo da coleção na Biblioteca (UX-08) — o mesmo nos modos Cards,
 * Lista e Carrossel. Antes, o tipo dependia da capa (a Pokébola da placa
 * tipográfica sumia com imagem própria). `null` = política desconhecida (sem selo).
 */
export type CollectionKindBadgeKind = "set" | "master" | "pokedex" | "free";

export function collectionKindBadge(policy: string | null): { kind: CollectionKindBadgeKind; label: string } | null {
  if (policy === "STANDARD_SET") return { kind: "set", label: "Set" };
  if (policy === "MASTER_SET") return { kind: "master", label: "Master Set" };
  if (policy === "REFERENCE_POSITION") return { kind: "pokedex", label: "Pokédex" };
  if (policy === "NONE") return { kind: "free", label: "Livre" };
  return null;
}

/**
 * Nome falado do tipo + detalhe, para o `aria-label` dos links da Biblioteca
 * (AUDIT CORRECTION-01, A1). O selo visual é `aria-hidden`; aqui o tipo é dito
 * uma única vez: "Set padrão, Nome · CÓD", "Master Set, Nome · CÓD",
 * "Completar a Pokédex…", "Coleção livre…" (as duas últimas já trazem o tipo em
 * `collectionSubtitle`, sem repetição).
 */
export function collectionSpokenSubtitle(collection: {
  cardSetName: string | null;
  cardSetCode: string | null;
  completionPolicy: string | null;
  coverCode?: string | null;
}): string {
  const subtitle = collectionSubtitle(collection);
  if (!collection.cardSetName) return subtitle;
  if (collection.completionPolicy === "STANDARD_SET") return `Set padrão, ${subtitle}`;
  if (collection.completionPolicy === "MASTER_SET") return `Master Set, ${subtitle}`;
  return subtitle;
}

/**
 * O que acompanha o selo: o Set (código – nome) nas coleções de Set; o código
 * próprio, se houver, na Livre e na Pokédex; senão uma descrição curta.
 * O nome falado vem de `collectionSpokenSubtitle` (tipo por extenso, uma vez).
 */
export function collectionKindDetail(collection: {
  cardSetName: string | null;
  cardSetCode: string | null;
  completionPolicy: string | null;
  coverCode?: string | null;
}): string {
  const code = collection.cardSetCode?.toUpperCase() ?? null;
  // Código antes do nome do Set (decisão de Fabrício): "ME5 – Escuridão Absoluta".
  // Sempre os dois — o título é livre e pode não ser o nome do Set.
  if (collection.cardSetName) return code ? `${code} – ${collection.cardSetName}` : collection.cardSetName;
  if (collection.coverCode) return collection.coverCode;
  if (collection.completionPolicy === "REFERENCE_POSITION") return "Pokédex Nacional";
  if (collection.completionPolicy === "NONE") return "Organizada do seu jeito";
  return collectionKindLabel(collection.completionPolicy);
}

/** Nome sugerido no formulário: o próprio nome do Set. */
export function suggestCollectionName(setName: string | null | undefined): string {
  return (setName ?? "").trim().slice(0, COLLECTION_NAME_MAX);
}

/** Nome pronto para envio, ou `null` se vazio. */
export function normalizeCollectionName(raw: string): string | null {
  const name = raw.replace(/\s+/g, " ").trim();
  if (name === "") return null;
  return name.slice(0, COLLECTION_NAME_MAX);
}

// ---------------------------------------------------------------------------
// Regra D-A (local) — decisão de interface espelhando CT-01
// ---------------------------------------------------------------------------

/**
 * Um local do próprio acervo. `kindCode` (5212, opcional) só serve para falar
 * do local em linguagem natural ("neste fichário") — WHERE-05A.
 */
export type StorageOption = { id: string; name: string; kindCode?: string | null };

/**
 * D-A (Fabrício, 2026-10-17): sem nenhum local, CT-01 cria "Local padrão" e a
 * interface não pergunta nada; com um ou mais locais, a escolha é explícita —
 * sem pré-seleção, nem quando só existe um. O banco reconfere (55000).
 */
export function storageStep(locations: readonly StorageOption[]): "auto" | "choose" {
  return locations.length === 0 ? "auto" : "choose";
}

export function canSubmitCreate(input: {
  /** Tipo escolhido no primeiro passo; ausente = "Completar um Set" (compatível com a criação original). */
  kind?: CollectionKind;
  setCode: string | null;
  name: string;
  locations: readonly StorageOption[];
  storageId: string | null;
  /** Só "Completar a Pokédex": quantas gerações estão marcadas. */
  generationCount?: number;
}): boolean {
  const kind = input.kind ?? "card_set";
  if (kind === "card_set" && !input.setCode) return false;
  // Pokédex: as gerações são conferidas no passo próprio (e de novo pelo banco, 5202).
  if (kind === "pokedex" && (input.generationCount ?? 0) < 1) return false;
  if (normalizeCollectionName(input.name) === null) return false;
  if (storageStep(input.locations) === "choose") {
    return input.storageId !== null && input.locations.some((location) => location.id === input.storageId);
  }
  return true;
}

// ---------------------------------------------------------------------------
// Tipos de criação (North Star NS-18, Fluxo 1.2) — COLLECTIONS-FUNCTIONAL-RECOVERY-01
// ---------------------------------------------------------------------------

/**
 * Tipos que o colecionador pode escolher ao criar. "Completar a Pokédex"
 * (PKX-02) só aparece com `POKEDEX_COLLECTION_ENABLED` — e, até lá, nem
 * aparece desabilitado (NS-18). Master Set não é tipo de criação: é ajuste de
 * uma coleção de Set.
 */
export type CollectionKind = "card_set" | "free" | "pokedex";

/**
 * Coleção livre: ligada em FREE-COLLECTION-FRONTEND-COMPLETION-01, quando as
 * três peças existem de ponta a ponta — criação segura
 * (`create_my_free_collection`, Query 5175, no LIVE e validada por 5832),
 * página da coleção sem Set e sem progresso (C-20) e "Adicionar cartas do meu
 * acervo" (5159 + 5162 + 5046). Desligar volta a criação a só "Completar um Set".
 */
export const FREE_COLLECTION_ENABLED = true;

export function availableCreationKinds(
  freeEnabled: boolean = FREE_COLLECTION_ENABLED,
  pokedexEnabled: boolean = POKEDEX_COLLECTION_ENABLED,
): CollectionKind[] {
  const kinds: CollectionKind[] = ["card_set"];
  if (freeEnabled) kinds.push("free");
  if (pokedexEnabled) kinds.push("pokedex");
  return kinds;
}

export type CreationStep = "type" | "set" | "objective" | "generations" | "details";

/**
 * Jornada progressiva: tipo → configuração do tipo (só Set) → [objetivo:
 * Set padrão × Master Set, só com o Master Set ligado] → nome e local.
 * O passo "tipo" só existe quando há mais de um tipo disponível
 * (FREE-COLLECTION-READINESS-01): com um só, a criação abre direto nele.
 */
export function creationSteps(
  kind: CollectionKind | null,
  kindCount: number = availableCreationKinds().length,
  /** Passo "Objetivo" (Set padrão × Master Set) depois do Set — só com o Master Set ligado. */
  withObjective: boolean = false,
): CreationStep[] {
  const steps: CreationStep[] =
    kind === "free"
      ? ["type", "details"]
      : kind === "pokedex"
        ? ["type", "generations", "details"]
        : withObjective
          ? ["type", "set", "objective", "details"]
          : ["type", "set", "details"];
  return kindCount > 1 ? steps : steps.slice(1);
}

/** Tipo pré-escolhido quando só existe um: a criação começa direto nele. */
export function initialCreationKind(kinds: readonly CollectionKind[] = availableCreationKinds()): CollectionKind | null {
  return kinds.length === 1 ? (kinds[0] ?? null) : null;
}

/** Nome sugerido pelo tipo (Fluxo 1.4) — editável, nunca identidade. */
export function suggestFreeCollectionName(): string {
  return "Minha coleção";
}

// ---------------------------------------------------------------------------
// Vínculo "1 de cada" (D-C) — alternativas
// ---------------------------------------------------------------------------

/** Um grupo do acervo (variante + idioma) ainda fora de coleção. */
export type LinkOption = {
  cardVariantId: string;
  languageCode: string;
  languageName: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  copies: number;
  imagePath: string | null;
};

export type LinkCandidate = {
  physicalCardId: string;
  cardId: string;
  collectorNumber: string;
  cardName: string;
  languageCode: string | null;
};

export type LinkChoice = {
  cardId: string;
  collectorNumber: string;
  cardName: string;
  options: LinkOption[];
  /** Grupo que R3 escolheria (variante padrão, depois o exemplar mais antigo). */
  suggestedKey: string;
};

export function optionKey(option: Pick<LinkOption, "cardVariantId" | "languageCode">): string {
  return `${option.cardVariantId}.${option.languageCode}`;
}

/**
 * Cartas com mais de um grupo elegível (outra variante ou outro idioma) — só
 * essas pedem escolha. Exemplares do mesmo grupo são equivalentes para o
 * progresso e não viram pergunta. A ligação entre R3 e os grupos do acervo é
 * pelo número de colecionador dentro do Set (os dois vêm do mesmo Set).
 */
export function findAlternatives(
  candidates: readonly LinkCandidate[],
  groups: readonly (LinkOption & { collectorNumber: string })[],
): LinkChoice[] {
  const byNumber = new Map<string, (LinkOption & { collectorNumber: string })[]>();
  for (const group of groups) {
    const list = byNumber.get(group.collectorNumber) ?? [];
    list.push(group);
    byNumber.set(group.collectorNumber, list);
  }
  const choices: LinkChoice[] = [];
  for (const candidate of candidates) {
    const options = byNumber.get(candidate.collectorNumber) ?? [];
    if (options.length < 2) continue;
    const ordered = [...options].sort(
      (a, b) =>
        Number(b.isDefaultVariant) - Number(a.isDefaultVariant) ||
        Number(b.languageCode === candidate.languageCode) - Number(a.languageCode === candidate.languageCode),
    );
    const suggested =
      ordered.find((option) => option.isDefaultVariant && option.languageCode === candidate.languageCode) ?? ordered[0];
    if (!suggested) continue;
    choices.push({
      cardId: candidate.cardId,
      collectorNumber: candidate.collectorNumber,
      cardName: candidate.cardName,
      options: ordered.map((option) => ({
        cardVariantId: option.cardVariantId,
        languageCode: option.languageCode,
        languageName: option.languageName,
        variantLabel: option.variantLabel,
        isDefaultVariant: option.isDefaultVariant,
        copies: option.copies,
        imagePath: option.imagePath,
      })),
      suggestedKey: optionKey(suggested),
    });
  }
  return choices;
}

/** Escolhas que diferem da sugestão — só essas viajam para o servidor. */
export function changedChoices(
  choices: readonly LinkChoice[],
  selected: Readonly<Record<string, string>>,
): { cardId: string; collectorNumber: string; cardVariantId: string; languageCode: string }[] {
  const changed: { cardId: string; collectorNumber: string; cardVariantId: string; languageCode: string }[] = [];
  for (const choice of choices) {
    const key = selected[choice.cardId];
    if (!key || key === choice.suggestedKey) continue;
    const option = choice.options.find((candidate) => optionKey(candidate) === key);
    if (!option) continue;
    changed.push({
      cardId: choice.cardId,
      collectorNumber: choice.collectorNumber,
      cardVariantId: option.cardVariantId,
      languageCode: option.languageCode,
    });
  }
  return changed;
}

/** Uma carta que falta e pode entrar (uma de cada — R3), com a arte para a escolha. */
export type LinkItem = { cardId: string; collectorNumber: string; cardName: string; imagePath: string | null };

/**
 * Lista da escolha "Adicionar as que já tenho": cada carta que falta e está no
 * acervo (um exemplar por carta — repetidas nunca entram aqui), com a arte do
 * grupo que entraria (a variante padrão no idioma do candidato, senão
 * qualquer grupo do mesmo número). Ordem de R3 preservada.
 */
export function linkItems(
  candidates: readonly LinkCandidate[],
  groups: readonly (Pick<LinkOption, "imagePath" | "isDefaultVariant" | "languageCode"> & { collectorNumber: string })[],
): LinkItem[] {
  return candidates.map((candidate) => {
    const same = groups.filter((group) => group.collectorNumber === candidate.collectorNumber && group.imagePath);
    const best =
      same.find((group) => group.isDefaultVariant && group.languageCode === candidate.languageCode) ??
      same.find((group) => group.isDefaultVariant) ??
      same[0];
    return {
      cardId: candidate.cardId,
      collectorNumber: candidate.collectorNumber,
      cardName: candidate.cardName,
      imagePath: best?.imagePath ?? null,
    };
  });
}

/** Ids escolhidos, sem repetição e só os que estão na lista atual. */
export function selectedCardIds(items: readonly Pick<LinkItem, "cardId">[], picked: ReadonlySet<string>): string[] {
  return items.filter((item) => picked.has(item.cardId)).map((item) => item.cardId);
}

export function chunk<T>(items: readonly T[], size: number): T[][] {
  if (size < 1) throw new Error("size must be >= 1");
  const out: T[][] = [];
  for (let index = 0; index < items.length; index += size) out.push(items.slice(index, index + size));
  return out;
}

// ---------------------------------------------------------------------------
// Erros
// ---------------------------------------------------------------------------

export type CollectionFailure =
  | "not_authenticated"
  | "storage_required"
  | "storage_invalid"
  | "set_not_found"
  | "set_empty"
  | "conflict"
  | "invalid"
  | "already_linked"
  | "not_linked"
  | "not_found"
  | "generation_unavailable"
  | "pokedex_unavailable"
  | "unavailable";

/**
 * Classifica pelo SQLSTATE e pelo prefixo estável da mensagem (CT-01 usa
 * códigos em maiúsculas; 5046 usa mensagens fixas). O texto cru nunca chega
 * ao usuário.
 */
export function classifyCollectionFailure(code: string | null | undefined, message: string | null | undefined): CollectionFailure {
  const text = message ?? "";
  if (code === "28000" || code === "42501" || text === "authentication required") return "not_authenticated";
  // Capa da Coleção livre (5178/5180): coleção alheia/inexistente ou de Set — mesma resposta, sem enumerar.
  if (text === "COLLECTION_NOT_FOUND" || text === "NOT_FREE_COLLECTION") return "not_found";
  if (code === "55000" || text.startsWith("STORAGE_CONTAINER_REQUIRED")) return "storage_required";
  if (text.startsWith("STORAGE_CONTAINER_INVALID") || text.startsWith("storage container does not belong")) return "storage_invalid";
  if (text.startsWith("CARD_SET_NOT_FOUND") || text === "card_set not found") return "set_not_found";
  if (text.startsWith("IDEMPOTENCY_KEY_REUSED")) return "conflict";
  // 5047: "uma ou mais physical_card_ids não estão alocadas a esta Collection" (fail-closed, nada removido).
  if (text.includes("não estão alocadas a esta Collection")) return "not_linked";
  // 5046: "uma ou mais physical_card_ids já estão alocadas a uma Collection" (fail-closed, nada gravado).
  if (code === "23505" || text.includes("já está alocad") || text.includes("já estão alocad") || text.includes("already allocated")) {
    return "already_linked";
  }
  if (text.startsWith("collection not found") || text.startsWith("collection is archived")) return "not_found";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unavailable";
}

export function collectionFailureMessage(reason: CollectionFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "storage_required":
      return "Escolha onde esta coleção fica guardada para continuar.";
    case "storage_invalid":
      return "Esse local não está mais disponível. Escolha outro.";
    case "set_not_found":
      return "Não encontramos esse Set no catálogo. Escolha outro.";
    case "set_empty":
      return "Esse Set ainda não tem cartas no catálogo.";
    case "conflict":
      return "Este envio já foi usado para outro pedido. Revise e tente de novo.";
    case "already_linked":
      return "Algumas cartas mudaram desde a revisão (provavelmente já entraram em uma coleção). Revise de novo para continuar.";
    case "not_linked":
      return "Este exemplar já não estava nesta coleção. A lista foi atualizada — nada mais mudou.";
    case "not_found":
      return "Esta coleção não está disponível para receber cartas.";
    case "invalid":
      return "Algo no pedido não está certo. Revise e tente de novo.";
    case "generation_unavailable":
      return "Uma das gerações escolhidas não está mais disponível. Volte e revise as gerações.";
    case "pokedex_unavailable":
      return "A Pokédex Nacional está indisponível no momento. Nada foi criado — tente mais tarde.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente em instantes.";
  }
}
