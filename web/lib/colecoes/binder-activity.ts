// Histórico de Atividades do Fichário (P3-B S7) — regras puras de apresentação.
//
// Lê o contrato LIVE da 5269 (`get_my_binder_activity`, `get_my_binder_activity_coverage`)
// e transforma cada evento numa frase pt-BR do colecionador (§3.3), sem
// expor ids, enums ou nomes de tabela. Sem dependências: testável com
// `node --experimental-strip-types --test lib/colecoes/binder-activity.test.ts` (a partir de web/).
//
// Regras de honestidade: quando o evento tem mais itens do que a leitura traz
// (`items_truncated`, até 50 por evento), contagens por efeito NÃO são inferidas
// dos itens parciais — usa-se o total do evento (`item_count`) ou uma frase sem número.

// ---------------------------------------------------------------------------
// Tipos e vocabulário (espelham os CHECKs de binder_activity_event/_item)
// ---------------------------------------------------------------------------

export const ACTIVITY_EVENT_TYPES = [
  "BINDER_ASSEMBLED",
  "CARD_PLACED",
  "CARD_MOVED",
  "CARDS_SWAPPED",
  "CARDS_REMOVED",
  "CARDS_LEFT_BY_STORAGE",
  "CARDS_LEFT_BY_COLLECTION_STORAGE",
  "CARD_LEFT_BY_INVENTORY_EXIT",
  "POCKET_RESERVED",
  "RESERVATIONS_RELEASED",
  "POCKETS_LOCKED",
  "POCKETS_UNLOCKED",
  "GAP_OPENED",
  "GAP_CLOSED",
  "PAGES_ADDED",
  "PAGE_REMOVED",
  "PAGES_REORDERED",
  "CATALOG_NOVELTIES_INCORPORATED",
  "COLLECTION_ATTACHED",
  "COLLECTION_DETACHED",
  "BINDER_DISMANTLED",
  "BINDER_DELETED_EMPTY",
  "BINDER_OWNERSHIP_TRANSFERRED",
  "LEGACY_CATALOG_INCORPORATION",
] as const;
export type ActivityEventType = (typeof ACTIVITY_EVENT_TYPES)[number];

export const ACTIVITY_CATEGORIES = ["CARDS", "RESERVATIONS", "LOCKS", "PAGES", "CATALOG", "BINDER"] as const;
export type ActivityCategory = (typeof ACTIVITY_CATEGORIES)[number];

/** Filtros da §3.3, na ordem da especificação. `null` = Todas. */
export type ActivityFilterKey = "ALL" | ActivityCategory;
export const ACTIVITY_FILTERS: readonly { key: ActivityFilterKey; label: string }[] = [
  { key: "ALL", label: "Todas" },
  { key: "CARDS", label: "Cartas" },
  { key: "RESERVATIONS", label: "Reservas" },
  { key: "LOCKS", label: "Fixação" },
  { key: "PAGES", label: "Páginas" },
  { key: "CATALOG", label: "Catálogo" },
  { key: "BINDER", label: "Fichário" },
];

export function filterCategories(key: ActivityFilterKey): ActivityCategory[] | null {
  return key === "ALL" ? null : [key];
}

/** Mesma regra da 5269 `binder_activity_category` (usada quando a linha não trouxer a categoria). */
export function categoryOf(type: string): ActivityCategory | null {
  switch (type) {
    case "CARD_PLACED":
    case "CARD_MOVED":
    case "CARDS_SWAPPED":
    case "CARDS_REMOVED":
    case "CARDS_LEFT_BY_STORAGE":
    case "CARDS_LEFT_BY_COLLECTION_STORAGE":
    case "CARD_LEFT_BY_INVENTORY_EXIT":
      return "CARDS";
    case "POCKET_RESERVED":
    case "RESERVATIONS_RELEASED":
      return "RESERVATIONS";
    case "POCKETS_LOCKED":
    case "POCKETS_UNLOCKED":
      return "LOCKS";
    case "GAP_OPENED":
    case "GAP_CLOSED":
    case "PAGES_ADDED":
    case "PAGE_REMOVED":
    case "PAGES_REORDERED":
      return "PAGES";
    case "CATALOG_NOVELTIES_INCORPORATED":
    case "LEGACY_CATALOG_INCORPORATION":
      return "CATALOG";
    case "BINDER_ASSEMBLED":
    case "COLLECTION_ATTACHED":
    case "COLLECTION_DETACHED":
    case "BINDER_DISMANTLED":
    case "BINDER_DELETED_EMPTY":
    case "BINDER_OWNERSHIP_TRANSFERRED":
      return "BINDER";
    default:
      return null;
  }
}

export type ActivityPosition = { page: number; row: number | null; col: number | null };

export type ActivityItem = {
  ordinal: number;
  kind: string;
  effect: string;
  cardName: string | null;
  collectorNumber: string | null;
  setCode: string | null;
  variantName: string | null;
  from: ActivityPosition | null;
  to: ActivityPosition | null;
  detail: Record<string, unknown> | null;
};

export type ActivityEvent = {
  id: number;
  occurredAt: string; // ISO
  type: string;
  category: ActivityCategory | null;
  source: string;
  legacy: boolean;
  collectionName: string | null;
  binderName: string | null;
  summary: Record<string, unknown>;
  itemCount: number;
  items: ActivityItem[];
  truncated: boolean;
};

export type ActivityCursor = { occurredAt: string; id: number };

export type ActivityCoverage = {
  coveredFrom: string | null;
  hasLegacy: boolean;
  binderIsMine: boolean;
};

// ---------------------------------------------------------------------------
// Parse (nunca adivinha: formato inesperado → null)
// ---------------------------------------------------------------------------

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

function obj(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function isIsoDate(value: unknown): value is string {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

function position(page: unknown, row: unknown, col: unknown): ActivityPosition | null {
  const p = int(page);
  if (p === null || p < 1) return null;
  const r = int(row);
  const c = int(col);
  return { page: p, row: r !== null && c !== null ? r : null, col: r !== null && c !== null ? c : null };
}

export function parseActivityItem(value: unknown): ActivityItem | null {
  const r = obj(value);
  if (!r) return null;
  const ordinal = int(r.ordinal);
  const kind = text(r.kind);
  const effect = text(r.effect);
  if (ordinal === null || !kind || !effect) return null;
  return {
    ordinal,
    kind,
    effect,
    cardName: text(r.card_name),
    collectorNumber: text(r.collector_number),
    setCode: text(r.card_set_code),
    variantName: text(r.variant_type_name),
    from: position(r.from_page, r.from_row, r.from_col),
    to: position(r.to_page, r.to_row, r.to_col),
    detail: obj(r.detail),
  };
}

export function parseActivityEvent(value: unknown): ActivityEvent | null {
  const r = obj(value);
  if (!r) return null;
  const id = int(r.event_id);
  const type = text(r.event_type);
  if (id === null || !type || !isIsoDate(r.occurred_at)) return null;
  const rawItems = Array.isArray(r.items) ? r.items : [];
  const items: ActivityItem[] = [];
  for (const raw of rawItems) {
    const item = parseActivityItem(raw);
    if (!item) return null;
    items.push(item);
  }
  items.sort((a, b) => a.ordinal - b.ordinal);
  const category = (ACTIVITY_CATEGORIES as readonly string[]).includes(r.category as string)
    ? (r.category as ActivityCategory)
    : categoryOf(type);
  const itemCount = int(r.item_count) ?? items.length;
  return {
    id,
    occurredAt: r.occurred_at,
    type,
    category,
    source: text(r.source) ?? "",
    legacy: r.is_legacy === true || r.source === "LEGADO",
    collectionName: text(r.collection_name),
    binderName: text(r.binder_name),
    summary: obj(r.summary) ?? {},
    itemCount,
    items,
    truncated: r.items_truncated === true || itemCount > items.length,
  };
}

export function parseActivityPage(data: unknown): ActivityEvent[] | null {
  if (data === null || data === undefined) return [];
  if (!Array.isArray(data)) return null;
  const events: ActivityEvent[] = [];
  for (const row of data) {
    const event = parseActivityEvent(row);
    if (!event) return null;
    events.push(event);
  }
  return events;
}

export function parseActivityCoverage(data: unknown): ActivityCoverage | null {
  if (data === null || data === undefined) return { coveredFrom: null, hasLegacy: false, binderIsMine: false };
  const row = Array.isArray(data) ? data[0] : data;
  if (row === undefined) return { coveredFrom: null, hasLegacy: false, binderIsMine: false };
  const r = obj(row);
  if (!r) return null;
  const covered = isIsoDate(r.covered_from) ? r.covered_from : isIsoDate(r.full_coverage_from) ? r.full_coverage_from : null;
  return { coveredFrom: covered, hasLegacy: r.has_legacy === true, binderIsMine: r.binder_is_mine === true };
}

// ---------------------------------------------------------------------------
// Paginação estável (cursor = ocorrido + id, do mais recente ao mais antigo)
// ---------------------------------------------------------------------------

export const ACTIVITY_PAGE_SIZE = 20;

export function cursorAfter(events: readonly ActivityEvent[]): ActivityCursor | null {
  const last = events[events.length - 1];
  return last ? { occurredAt: last.occurredAt, id: last.id } : null;
}

export function isCursor(value: unknown): value is ActivityCursor {
  const r = obj(value);
  return !!r && isIsoDate(r.occurredAt) && typeof r.id === "number" && Number.isInteger(r.id) && r.id > 0;
}

function newerThan(a: ActivityEvent, b: ActivityEvent): boolean {
  const ta = Date.parse(a.occurredAt);
  const tb = Date.parse(b.occurredAt);
  return ta !== tb ? ta > tb : a.id > b.id;
}

/** Junta páginas sem duplicar (o mesmo id nunca aparece duas vezes) e mantém a ordem decrescente. */
export function mergeActivity(current: readonly ActivityEvent[], incoming: readonly ActivityEvent[]): ActivityEvent[] {
  const byId = new Map<number, ActivityEvent>();
  for (const e of current) byId.set(e.id, e);
  for (const e of incoming) if (!byId.has(e.id)) byId.set(e.id, e);
  return [...byId.values()].sort((a, b) => (newerThan(a, b) ? -1 : newerThan(b, a) ? 1 : 0));
}

/** Quantos eventos de `fresh` são mais novos que o topo atual (para anunciar novidades). */
export function countNewer(current: readonly ActivityEvent[], fresh: readonly ActivityEvent[]): number {
  const top = current[0];
  if (!top) return fresh.length;
  return fresh.filter((e) => newerThan(e, top)).length;
}

// ---------------------------------------------------------------------------
// Datas (fuso de São Paulo, como o restante do produto)
// ---------------------------------------------------------------------------

export const ACTIVITY_TIME_ZONE = "America/Sao_Paulo";

function dayKey(date: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function keyParts(key: string): [number, number, number] {
  const [y = 1970, m = 1, d = 1] = key.split("-").map(Number);
  return [y, m, d];
}

function shiftDay(key: string, days: number): string {
  const [y, m, d] = keyParts(key);
  const utc = new Date(Date.UTC(y, m - 1, d + days));
  return utc.toISOString().slice(0, 10);
}

const MONTHS_SHORT = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];

/**
 * Separador de dia compacto: "Hoje", "Ontem", "27 out", "27 out 2025"
 * (a lista o mostra em maiúsculas por CSS). O nome completo vai em `dayFullLabel`.
 */
export function dayLabel(key: string, now: Date, timeZone = ACTIVITY_TIME_ZONE): string {
  const today = dayKey(now, timeZone);
  if (key === today) return "Hoje";
  if (key === shiftDay(today, -1)) return "Ontem";
  const [y, m, d] = keyParts(key);
  const short = `${d} ${MONTHS_SHORT[m - 1] ?? ""}`;
  return key.slice(0, 4) === today.slice(0, 4) ? short : `${short} ${y}`;
}

/** Nome completo do dia para tecnologias assistivas: "27 de outubro de 2026". */
export function dayFullLabel(key: string): string {
  const [y, m, d] = keyParts(key);
  return new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC", day: "numeric", month: "long", year: "numeric" }).format(new Date(Date.UTC(y, m - 1, d, 12)));
}

/** Data e hora compactas dos detalhes: "28 out 2026 · 21:42". */
export function compactDateTime(iso: string, timeZone = ACTIVITY_TIME_ZONE): string {
  const [y, m, d] = keyParts(dayKey(new Date(iso), timeZone));
  return `${d} ${MONTHS_SHORT[m - 1] ?? ""} ${y} · ${timeLabel(iso, timeZone)}`;
}

export function timeLabel(iso: string, timeZone = ACTIVITY_TIME_ZONE): string {
  return new Intl.DateTimeFormat("pt-BR", { timeZone, hour: "2-digit", minute: "2-digit" }).format(new Date(iso));
}

export function fullDateLabel(iso: string, timeZone = ACTIVITY_TIME_ZONE): string {
  return new Intl.DateTimeFormat("pt-BR", { timeZone, day: "numeric", month: "long", year: "numeric" }).format(new Date(iso));
}

export type ActivityDay = { key: string; label: string; events: ActivityEvent[] };

/** Agrupa por dia (fuso local do produto), preservando a ordem recebida. */
export function groupByDay(events: readonly ActivityEvent[], now: Date, timeZone = ACTIVITY_TIME_ZONE): ActivityDay[] {
  const days: ActivityDay[] = [];
  for (const event of events) {
    const key = dayKey(new Date(event.occurredAt), timeZone);
    const last = days[days.length - 1];
    if (last && last.key === key) last.events.push(event);
    else days.push({ key, label: dayLabel(key, now, timeZone), events: [event] });
  }
  return days;
}

// ---------------------------------------------------------------------------
// Frases (linguagem do colecionador)
// ---------------------------------------------------------------------------

const NUMBER = new Intl.NumberFormat("pt-BR");

function count(n: number, one: string, many: string): string {
  return `${NUMBER.format(n)} ${n === 1 ? one : many}`;
}

/** "Mega Darkrai ex · 120 · Holo Reversa" — só o que existir. */
export function cardLabel(item: Pick<ActivityItem, "cardName" | "collectorNumber" | "variantName">): string {
  return [item.cardName ?? "Carta", item.collectorNumber, item.variantName].filter(Boolean).join(" · ");
}

/** "página 3 (linha 2, coluna 4)" ou só "página 3". */
export function positionLabel(p: ActivityPosition): string {
  return p.row !== null && p.col !== null ? `página ${p.page} (linha ${p.row}, coluna ${p.col})` : `página ${p.page}`;
}

/** "página 5", "páginas 4 e 5", "páginas 2, 3 e 7". */
export function pagesLabel(pages: readonly number[]): string {
  const unique = [...new Set(pages)].sort((a, b) => a - b);
  if (unique.length === 0) return "";
  if (unique.length === 1) return `página ${unique[0]}`;
  if (unique.length > 6) return `${unique.length} páginas`;
  return `páginas ${unique.slice(0, -1).join(", ")} e ${unique[unique.length - 1]}`;
}

function itemPages(items: readonly ActivityItem[], side: "from" | "to" | "any"): number[] {
  const out: number[] = [];
  for (const i of items) {
    if ((side === "from" || side === "any") && i.from) out.push(i.from.page);
    if ((side === "to" || side === "any") && i.to) out.push(i.to.page);
  }
  return out;
}

function byEffect(items: readonly ActivityItem[], ...effects: string[]): ActivityItem[] {
  return items.filter((i) => effects.includes(i.effect));
}

/** Número confiável de itens com certo efeito: só quando a lista veio completa. */
function effectCount(event: ActivityEvent, ...effects: string[]): number | null {
  if (event.truncated) return null;
  return byEffect(event.items, ...effects).length;
}

function summaryText(event: ActivityEvent, key: string): string | null {
  return text(event.summary[key]);
}

function summaryInt(event: ActivityEvent, key: string): number | null {
  return int(event.summary[key]);
}

function withPages(main: string, pages: number[], truncated: boolean): string {
  const label = truncated ? "" : pagesLabel(pages);
  return label ? `${main} · ${label}` : main;
}

export type ActivityIcon = "card" | "move" | "swap" | "remove" | "leave" | "reserve" | "release" | "lock" | "unlock" | "page" | "pageRemove" | "gap" | "reorder" | "catalog" | "binder" | "link" | "unlink" | "transfer" | "close" | "activity";

export type EventView = {
  title: string;
  /** Linha secundária curta (coleção, local, grade) — opcional. */
  context: string | null;
  icon: ActivityIcon;
  legacy: boolean;
  /** Tem itens para "Ver detalhes" (mais de um, ou um com informação além da frase). */
  expandable: boolean;
};

export const LEGACY_BADGE = "Registro anterior ao histórico completo";

export function describeEvent(event: ActivityEvent): EventView {
  const items = event.items;
  const first = items[0];
  const n = event.itemCount;
  const many = n > 1;
  const collection = event.collectionName;
  let title: string;
  let context: string | null = null;
  let icon: ActivityIcon = "activity";

  switch (event.type) {
    case "CARD_PLACED": {
      icon = "card";
      if (!many && first) title = `${cardLabel(first)} colocada${first.to ? ` na ${positionLabel(first.to)}` : " no fichário"}`;
      else title = withPages(`${count(n, "carta colocada", "cartas colocadas")}`, itemPages(items, "to"), event.truncated);
      if (collection) context = `Coleção ${collection}`;
      break;
    }
    case "CARD_MOVED": {
      icon = "move";
      if (!many && first && first.from && first.to) title = `${cardLabel(first)} movida da ${positionLabel(first.from)} para a ${positionLabel(first.to)}`;
      else if (!many && first) title = `${cardLabel(first)} movida`;
      else title = `${count(n, "carta movida", "cartas movidas")}`;
      break;
    }
    case "CARDS_SWAPPED": {
      icon = "swap";
      const [a, b] = items;
      title = a && b && !event.truncated && n === 2 ? `${cardLabel(a)} e ${cardLabel(b)} trocaram de lugar` : `${count(n, "carta trocada", "cartas trocadas")} de lugar`;
      if (a && b && a.from && b.from && n === 2) context = `${positionLabel(a.from)} ↔ ${positionLabel(b.from)}`;
      break;
    }
    case "CARDS_REMOVED": {
      icon = "remove";
      if (!many && first) title = `${cardLabel(first)} retirada${first.from ? ` da ${positionLabel(first.from)}` : " do fichário"}`;
      else title = withPages(count(n, "carta retirada", "cartas retiradas"), itemPages(items, "from"), event.truncated);
      context = "Continua na coleção";
      break;
    }
    case "CARDS_LEFT_BY_STORAGE": {
      icon = "leave";
      title = !many && first ? `${cardLabel(first)} saiu do fichário` : `${count(n, "carta saiu", "cartas saíram")} do fichário`;
      const place = summaryText(event, "storage_container_name");
      context = place ? `Mudou de local no Meu acervo · ${place}` : "Mudou de local no Meu acervo";
      break;
    }
    case "CARDS_LEFT_BY_COLLECTION_STORAGE": {
      icon = "leave";
      title = !many && first ? `${cardLabel(first)} saiu do fichário` : `${count(n, "carta saiu", "cartas saíram")} do fichário`;
      const place = summaryText(event, "storage_container_name");
      context = [collection ? `Guarda da coleção ${collection} reorganizada` : "Guarda da coleção reorganizada", place].filter(Boolean).join(" · ");
      break;
    }
    case "CARD_LEFT_BY_INVENTORY_EXIT": {
      icon = "leave";
      title = first ? `${cardLabel(first)} saiu do fichário` : "Uma carta saiu do fichário";
      context = "Deixou o Meu acervo";
      break;
    }
    case "POCKET_RESERVED": {
      icon = "reserve";
      if (!many && first) {
        const what = first.cardName ? ` para ${cardLabel(first)}` : "";
        title = `Bolso reservado${what}${first.to ? ` · ${positionLabel(first.to)}` : ""}`;
      } else title = withPages(count(n, "bolso reservado", "bolsos reservados"), itemPages(items, "to"), event.truncated);
      if (collection) context = `Coleção ${collection}`;
      break;
    }
    case "RESERVATIONS_RELEASED": {
      icon = "release";
      if (!many && first) title = `Reserva liberada${first.cardName ? ` · ${cardLabel(first)}` : ""}${first.from ? ` · ${positionLabel(first.from)}` : ""}`;
      else title = withPages(count(n, "reserva liberada", "reservas liberadas"), itemPages(items, "from"), event.truncated);
      break;
    }
    case "POCKETS_LOCKED":
    case "POCKETS_UNLOCKED": {
      const locked = event.type === "POCKETS_LOCKED";
      icon = locked ? "lock" : "unlock";
      const noun = locked ? count(n, "bolso fixado", "bolsos fixados") : count(n, "bolso desafixado", "bolsos desafixados");
      title = withPages(noun, itemPages(items, "any"), event.truncated);
      break;
    }
    case "GAP_OPENED":
    case "GAP_CLOSED": {
      const opened = event.type === "GAP_OPENED";
      icon = "gap";
      const shifted = effectCount(event, "SHIFTED");
      const anchor = items.find((i) => i.effect === "SHIFTED");
      const pos = anchor ? ((opened ? anchor.from : anchor.to) ?? anchor.from ?? anchor.to) : null;
      const where = pos ? ` na página ${pos.page}` : "";
      title = `${opened ? "Espaço aberto" : "Espaço fechado"}${where}`;
      const parts: string[] = [];
      if (shifted !== null && shifted > 0) parts.push(`${count(shifted, "item deslocado", "itens deslocados")}`);
      const added = effectCount(event, "PAGE_ADDED");
      const removed = effectCount(event, "PAGE_REMOVED");
      if (added) parts.push(count(added, "página adicionada", "páginas adicionadas"));
      if (removed) parts.push(count(removed, "página removida", "páginas removidas"));
      context = parts.length ? parts.join(" · ") : null;
      break;
    }
    case "PAGES_ADDED": {
      icon = "page";
      const pages = itemPages(items, "to");
      title = !many && pages.length === 1 ? `Página ${pages[0]} adicionada` : count(n, "página adicionada", "páginas adicionadas");
      break;
    }
    case "PAGE_REMOVED": {
      icon = "pageRemove";
      const pages = itemPages(items, "from");
      title = !many && pages.length === 1 ? `Página ${pages[0]} removida` : count(n, "página removida", "páginas removidas");
      break;
    }
    case "PAGES_REORDERED": {
      icon = "reorder";
      title = "Páginas reordenadas";
      context = count(n, "página mudou de posição", "páginas mudaram de posição");
      break;
    }
    case "CATALOG_NOVELTIES_INCORPORATED": {
      icon = "catalog";
      const reserved = effectCount(event, "RESERVED", "INCORPORATED");
      title = reserved !== null ? `${count(reserved, "novidade do Catálogo incorporada", "novidades do Catálogo incorporadas")}` : "Novidades do Catálogo incorporadas";
      const parts: string[] = [];
      const shifted = effectCount(event, "SHIFTED");
      const added = effectCount(event, "PAGE_ADDED");
      if (shifted) parts.push(count(shifted, "item deslocado", "itens deslocados"));
      if (added) parts.push(count(added, "página adicionada", "páginas adicionadas"));
      if (collection) parts.unshift(`Coleção ${collection}`);
      context = parts.length ? parts.join(" · ") : null;
      break;
    }
    case "LEGACY_CATALOG_INCORPORATION": {
      icon = "catalog";
      title = first?.cardName ? `${cardLabel(first)} incorporada do Catálogo` : "Novidade do Catálogo incorporada";
      break;
    }
    case "BINDER_ASSEMBLED": {
      icon = "binder";
      title = "Fichário montado";
      const cols = summaryInt(event, "grid_columns");
      const rows = summaryInt(event, "grid_rows");
      const parts: string[] = [];
      if (collection) parts.push(`Coleção ${collection}`);
      if (cols && rows) parts.push(`grade ${cols} × ${rows}`);
      const pages = effectCount(event, "PAGE_ADDED");
      const reserved = effectCount(event, "RESERVED");
      const placed = effectCount(event, "PLACED");
      if (pages) parts.push(count(pages, "página", "páginas"));
      if (placed) parts.push(count(placed, "carta posicionada", "cartas posicionadas"));
      if (reserved) parts.push(count(reserved, "reserva", "reservas"));
      context = parts.length ? parts.join(" · ") : null;
      break;
    }
    case "COLLECTION_ATTACHED": {
      icon = "link";
      title = collection ? `Coleção ${collection} passou a usar o fichário` : "Uma coleção passou a usar o fichário";
      break;
    }
    case "COLLECTION_DETACHED": {
      icon = "unlink";
      title = collection ? `Coleção ${collection} deixou de usar o fichário` : "Uma coleção deixou de usar o fichário";
      const released = effectCount(event, "RELEASED");
      const unlocked = effectCount(event, "UNLOCKED");
      const parts: string[] = [];
      if (released) parts.push(count(released, "reserva liberada", "reservas liberadas"));
      if (unlocked) parts.push(count(unlocked, "bolso desafixado", "bolsos desafixados"));
      context = parts.length ? parts.join(" · ") : null;
      break;
    }
    case "BINDER_OWNERSHIP_TRANSFERRED": {
      icon = "transfer";
      title = collection ? `O fichário passou a ser da coleção ${collection}` : "O fichário mudou de coleção dona";
      break;
    }
    case "BINDER_DISMANTLED": {
      icon = "close";
      title = "Fichário desmontado";
      const pages = summaryInt(event, "pages");
      context = pages ? `${count(pages, "página", "páginas")} desfeitas · o histórico continua guardado` : "O histórico continua guardado";
      break;
    }
    case "BINDER_DELETED_EMPTY": {
      icon = "close";
      title = "Fichário vazio removido";
      context = "O histórico continua guardado";
      break;
    }
    default:
      title = "Atividade no fichário";
  }

  const expandable = n > 1 || (n === 1 && !!first && describeItem(first) !== null && !singleIsTitle(event.type));
  return { title, context, icon, legacy: event.legacy, expandable };
}

/** Tipos cujo único item já está inteiro na frase principal. */
// ---------------------------------------------------------------------------
// Activity Log minimalista (S7, refinamento definitivo)
//
// Lista recolhida: UMA manchete curta "objeto + ação" por evento
// ("Exeggutor de Alola movida", "7 cartas retiradas", "Página 41 removida").
// Detalhes: campos completos (`detailFields`) + itens + truncamento. Nada é
// inventado: só campos devolvidos pela 5269 (e a regra do V1 de que quem
// executou é o titular — §3.2 / B.2; o legado não tem ator).
// ---------------------------------------------------------------------------

function nameOf(item: ActivityItem | undefined): string {
  return item?.cardName ?? "Carta";
}

export function headlineEvent(event: ActivityEvent): string {
  const items = event.items;
  const first = items[0];
  const n = event.itemCount;
  const many = n > 1;
  const cards = (participle: string) => `${NUMBER.format(n)} cartas ${participle}`;
  switch (event.type) {
    case "CARD_PLACED":
      return many ? cards("colocadas") : `${nameOf(first)} colocada`;
    case "CARD_MOVED":
      return many ? cards("movidas") : `${nameOf(first)} movida`;
    case "CARDS_SWAPPED": {
      const [a, b] = items;
      return n === 2 && a && b && !event.truncated ? `${nameOf(a)} trocada com ${nameOf(b)}` : cards("trocadas de lugar");
    }
    case "CARDS_REMOVED":
      return many ? cards("retiradas") : `${nameOf(first)} retirada`;
    case "CARDS_LEFT_BY_STORAGE":
    case "CARDS_LEFT_BY_COLLECTION_STORAGE":
      return many ? `${NUMBER.format(n)} cartas saíram do fichário` : `${nameOf(first)} saiu do fichário`;
    case "CARD_LEFT_BY_INVENTORY_EXIT":
      return `${nameOf(first)} saiu do acervo`;
    case "POCKET_RESERVED":
      return many ? `${NUMBER.format(n)} reservas criadas` : "Reserva criada";
    case "RESERVATIONS_RELEASED":
      return many ? `${NUMBER.format(n)} reservas liberadas` : "Reserva liberada";
    case "POCKETS_LOCKED":
      return many ? `${NUMBER.format(n)} bolsos fixados` : "Bolso fixado";
    case "POCKETS_UNLOCKED":
      return many ? `${NUMBER.format(n)} bolsos desafixados` : "Bolso desafixado";
    case "GAP_OPENED":
    case "GAP_CLOSED": {
      const opened = event.type === "GAP_OPENED";
      const anchor = items.find((i) => i.effect === "SHIFTED");
      const pos = anchor ? ((opened ? anchor.from : anchor.to) ?? anchor.from ?? anchor.to) : null;
      return `${opened ? "Espaço aberto" : "Espaço fechado"}${pos ? ` na página ${pos.page}` : ""}`;
    }
    case "PAGES_ADDED": {
      const pages = itemPages(items, "to");
      return !many && pages.length === 1 ? `Página ${pages[0]} adicionada` : `${NUMBER.format(n)} páginas adicionadas`;
    }
    case "PAGE_REMOVED": {
      const pages = itemPages(items, "from");
      return !many && pages.length === 1 ? `Página ${pages[0]} removida` : `${NUMBER.format(n)} páginas removidas`;
    }
    case "PAGES_REORDERED":
      return "Páginas reordenadas";
    case "CATALOG_NOVELTIES_INCORPORATED": {
      const k = effectCount(event, "RESERVED", "INCORPORATED");
      return k !== null ? `${count(k, "novidade incorporada", "novidades incorporadas")}` : "Novidades do Catálogo incorporadas";
    }
    case "LEGACY_CATALOG_INCORPORATION":
      return first?.cardName ? `${first.cardName} incorporada` : "Novidade incorporada";
    case "BINDER_ASSEMBLED":
      return "Fichário montado";
    case "COLLECTION_ATTACHED":
      return "Coleção associada";
    case "COLLECTION_DETACHED":
      return "Coleção desassociada";
    case "BINDER_OWNERSHIP_TRANSFERRED":
      return "Fichário transferido";
    case "BINDER_DISMANTLED":
      return "Fichário desmontado";
    case "BINDER_DELETED_EMPTY":
      return "Fichário vazio removido";
    default:
      return "Atividade registrada";
  }
}

export type DetailField = { label: string; value: string };

/** Carta com tudo que a leitura traz: nome · número · Set · acabamento. */
export function fullCardLabel(item: ActivityItem): string {
  return [item.cardName ?? "Carta", item.collectorNumber, item.setCode, item.variantName].filter(Boolean).join(" · ");
}

/** Campos dos detalhes, na ordem de leitura; só os que existem neste evento. */
export function detailFields(event: ActivityEvent): DetailField[] {
  const view = describeEvent(event);
  const fields: DetailField[] = [{ label: "Ação", value: view.title }];
  const single = event.itemCount === 1 ? event.items[0] : undefined;
  if (single?.cardName) fields.push({ label: "Carta", value: fullCardLabel(single) });
  if (single?.from && single.kind !== "PAGE") fields.push({ label: "De", value: capitalize(positionLabel(single.from)) });
  if (single?.to && single.kind !== "PAGE") fields.push({ label: "Para", value: capitalize(positionLabel(single.to)) });
  if (event.collectionName) fields.push({ label: "Coleção", value: event.collectionName });
  if (event.binderName) fields.push({ label: "Fichário", value: event.binderName });
  const place = summaryText(event, "storage_container_name");
  if (place) fields.push({ label: "Destino", value: place });
  if (view.context && !(place && view.context.includes(place)) && !(event.collectionName && view.context === `Coleção ${event.collectionName}`)) {
    fields.push({ label: "Observação", value: view.context });
  }
  fields.push({ label: "Por", value: event.legacy ? "Não registrado (anterior ao histórico)" : "Você" });
  fields.push({ label: "Quando", value: compactDateTime(event.occurredAt) });
  return fields;
}

function capitalize(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/** Itens listados nos detalhes: só quando o evento tem mais de um (o único já está nos campos). */
export function detailItems(event: ActivityEvent): { key: number; text: string }[] {
  if (event.itemCount <= 1) return [];
  return event.items.map((item) => ({ key: item.ordinal, text: describeItem(item) })).filter((l): l is { key: number; text: string } => !!l.text);
}

function singleIsTitle(type: string): boolean {
  return ["CARD_PLACED", "CARD_MOVED", "CARDS_REMOVED", "CARD_LEFT_BY_INVENTORY_EXIT", "POCKET_RESERVED", "RESERVATIONS_RELEASED", "PAGES_ADDED", "PAGE_REMOVED", "COLLECTION_ATTACHED", "BINDER_OWNERSHIP_TRANSFERRED", "BINDER_DELETED_EMPTY", "LEGACY_CATALOG_INCORPORATION"].includes(type);
}

/** Uma linha por item em "Ver detalhes". `null` = item sem informação exibível. */
export function describeItem(item: ActivityItem): string | null {
  const card = item.cardName ? cardLabel(item) : null;
  const from = item.from ? positionLabel(item.from) : null;
  const to = item.to ? positionLabel(item.to) : null;
  const route = from && to ? `${from} → ${to}` : to ? `→ ${to}` : from ? `saiu da ${from}` : null;
  switch (`${item.kind}/${item.effect}`) {
    case "CARD/PLACED":
      return [card ?? "Carta", to ? `→ ${to}` : null].filter(Boolean).join(" · ");
    case "CARD/MOVED":
    case "CARD/SWAPPED":
    case "CARD/SHIFTED":
      return [card ?? "Carta", from && to ? `${from} → ${to}` : route].filter(Boolean).join(" · ");
    case "CARD/REMOVED":
    case "CARD/LEFT":
      return [card ?? "Carta", from ? `saiu da ${from}` : "saiu do fichário"].join(" · ");
    case "CARD/INCORPORATED":
      return [card ?? "Carta", "incorporada do Catálogo"].join(" · ");
    case "RESERVATION/RESERVED":
      return ["Reserva", card, to].filter(Boolean).join(" · ");
    case "RESERVATION/RELEASED":
      return ["Reserva liberada", card, from].filter(Boolean).join(" · ");
    case "RESERVATION/INCORPORATED":
      return ["Reserva ajustada pelo Catálogo", card, to ?? from].filter(Boolean).join(" · ");
    case "RESERVATION/SHIFTED":
      return ["Reserva", card, from && to ? `${from} → ${to}` : route].filter(Boolean).join(" · ");
    case "POCKET/LOCKED":
      return ["Bolso fixado", from ?? to].filter(Boolean).join(" · ");
    case "POCKET/UNLOCKED":
      return ["Bolso desafixado", from ?? to].filter(Boolean).join(" · ");
    case "POCKET/SHIFTED":
      return ["Bolso fixado deslocado", from && to ? `${from} → ${to}` : route].filter(Boolean).join(" · ");
    case "PAGE/PAGE_ADDED":
      return item.to ? `Página ${item.to.page} adicionada` : "Página adicionada";
    case "PAGE/PAGE_REMOVED":
      return item.from ? `Página ${item.from.page} removida` : "Página removida";
    case "PAGE/PAGE_RENUMBERED":
      return item.from && item.to ? `Página ${item.from.page} → posição ${item.to.page}` : "Página renumerada";
    case "COLLECTION/ATTACHED":
      return "Coleção associada ao fichário";
    case "COLLECTION/DETACHED":
      return "Coleção desassociada do fichário";
    case "BINDER/TRANSFERRED":
      return "Fichário transferido para outra coleção";
    case "BINDER/CLOSED":
      return "Fichário encerrado";
    default:
      return card ?? route;
  }
}

export function truncationNote(event: ActivityEvent): string | null {
  if (!event.truncated) return null;
  return `Mostrando ${NUMBER.format(event.items.length)} de ${NUMBER.format(event.itemCount)} alterações deste registro.`;
}

export function coverageNote(coverage: ActivityCoverage | null): string | null {
  if (!coverage?.coveredFrom) return null;
  return `Histórico registrado a partir de ${fullDateLabel(coverage.coveredFrom)}. Alterações anteriores não aparecem aqui.`;
}

export function emptyMessage(filter: ActivityFilterKey): string {
  if (filter === "ALL") return "Nenhuma atividade registrada neste fichário ainda. As próximas mudanças aparecem aqui.";
  const label = ACTIVITY_FILTERS.find((f) => f.key === filter)?.label ?? "este filtro";
  return `Nenhuma atividade em ${label}. Escolha “Todas” para ver o histórico completo.`;
}

export type ActivityFailure = "invalid" | "not_authenticated" | "unavailable" | "unknown";

export function classifyActivityFailure(code?: string, message?: string): ActivityFailure {
  if (code === "28000" || /not_authenticated|JWT/i.test(message ?? "")) return "not_authenticated";
  if (code === "22023") return "invalid";
  if (code === "PGRST202" || code === "42883") return "unavailable";
  return "unknown";
}

export function activityFailureMessage(reason: ActivityFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para ver o histórico.";
    case "unavailable":
      return "O histórico ainda não está disponível.";
    default:
      return "Não foi possível carregar o histórico.";
  }
}
