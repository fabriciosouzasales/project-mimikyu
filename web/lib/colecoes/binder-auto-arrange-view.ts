import {
  type AutoArrangeEntry,
  type AutoArrangeFailure,
  type AutoArrangePreview,
  entryHint,
  failureMessage,
} from "./binder-auto-arrange.ts";

// ---------------------------------------------------------------------------
// Organizar automaticamente — estado da interface de PRÉVIA (P2 UI E3).
//
// Só leitura: este módulo nunca conhece a aplicação (5344). A interface chama
// exclusivamente `previewAutoArrange`; o token da prévia fica guardado só para
// comparação futura (o servidor continua a autoridade definitiva).
// ---------------------------------------------------------------------------

/** Botão do trilho: ausente, disponível ou indisponível com motivo (nunca some depois de aparecer). */
export type AutoArrangeRailButton = { present: false } | { present: true; enabled: boolean; label: string };

export const AUTO_ARRANGE_RAIL_LABEL = "Organizar automaticamente";
/** Ids de DOM: painel da prévia e botão do trilho (o foco volta ao botão quando o painel fecha). */
export const AUTO_ARRANGE_PANEL_ID = "fichario-organizar-automaticamente";
export const AUTO_ARRANGE_BUTTON_ID = "fichario-organizar-botao";

export function autoArrangeRailButton(entry: AutoArrangeEntry, open: boolean): AutoArrangeRailButton {
  if (!entry.visible) return { present: false };
  if (!entry.enabled) return { present: true, enabled: false, label: `${AUTO_ARRANGE_RAIL_LABEL} — ${entryHint(entry) ?? "indisponível"}` };
  return { present: true, enabled: true, label: open ? "Fechar a prévia da organização automática" : `${AUTO_ARRANGE_RAIL_LABEL} — ver a prévia` };
}

// ---- painéis laterais: um por vez ----

export type SidePanel = "control" | "available" | "arrange";

/** Ao abrir um painel do palco, os outros dois fecham (mesma área do grid). */
export function sidePanelsWhenOpening(panel: SidePanel): Record<SidePanel, boolean> {
  return { control: panel === "control", available: panel === "available", arrange: panel === "arrange" };
}

// ---- estado da prévia ----

/**
 * Versão local do fichário no momento da leitura: `activity` (escritas desta
 * tela, `activityVersion`) e `layout` (reordenação de páginas, que relê tudo).
 */
export type LocalVersion = { activity: number; layout: number };

export type ArrangeView =
  | { status: "closed"; lastSeq: number }
  | { status: "loading"; seq: number; version: LocalVersion }
  | { status: "ready"; seq: number; version: LocalVersion; preview: AutoArrangePreview }
  | { status: "error"; seq: number; version: LocalVersion; reason: AutoArrangeFailure };

export const ARRANGE_CLOSED: ArrangeView = { status: "closed", lastSeq: 0 };

function lastSeq(view: ArrangeView): number {
  return view.status === "closed" ? view.lastSeq : view.seq;
}

/** Abrir (ou atualizar): nova leitura com sequência crescente; respostas de leituras anteriores são descartadas. */
export function startPreview(view: ArrangeView, version: LocalVersion): ArrangeView {
  return { status: "loading", seq: lastSeq(view) + 1, version };
}

/** Fechar preserva a sequência: uma resposta atrasada de antes do fechamento nunca reabre nem preenche o painel. */
export function closePreview(view: ArrangeView): ArrangeView {
  return { status: "closed", lastSeq: lastSeq(view) };
}

export type PreviewOutcome = { ok: true; preview: AutoArrangePreview } | { ok: false; reason: AutoArrangeFailure };

/** Resposta da leitura `seq`; ignorada se o painel fechou ou outra leitura começou depois. */
export function finishPreview(view: ArrangeView, seq: number, outcome: PreviewOutcome): ArrangeView {
  if (view.status !== "loading" || view.seq !== seq) return view;
  return outcome.ok ? { status: "ready", seq, version: view.version, preview: outcome.preview } : { status: "error", seq, version: view.version, reason: outcome.reason };
}

/**
 * Desatualizada = o fichário mudou NESTA tela depois da leitura. O contrário
 * não vale: versão igual não prova que o plano continua válido (outra tela ou
 * outro dispositivo pode ter mudado o fichário) — só o token do servidor prova.
 */
export function isStale(view: ArrangeView, current: LocalVersion): boolean {
  if (view.status !== "ready") return false;
  return view.version.activity !== current.activity || view.version.layout !== current.layout;
}

export const STALE_MESSAGE = "O fichário mudou desde esta prévia. Atualize para ver o plano atual.";
export const SERVER_AUTHORITY_NOTE = "A prévia mostra o fichário no momento da leitura. Antes de qualquer organização, o plano é conferido de novo.";

/** Projeção local dos bolsos que receberiam carta: só READY e não desatualizada. Nunca é posição gravada. */
export function projectedSlotIds(view: ArrangeView, current: LocalVersion): ReadonlySet<string> | null {
  if (view.status !== "ready" || isStale(view, current) || view.preview.status !== "READY") return null;
  return new Set(view.preview.items.map((item) => item.slotId));
}

/** Itens da prévia numa página (destaque e contagem por página). */
export function itemsOnPage(preview: AutoArrangePreview, page: number): number {
  let n = 0;
  for (const item of preview.items) if (item.page === page) n += 1;
  return n;
}

/** Páginas afetadas para navegação: as da prévia (READY e LIMIT_EXCEEDED), limitadas às existentes. */
export function navigablePages(preview: AutoArrangePreview, totalPages: number): number[] {
  return preview.pages.filter((p) => p >= 1 && p <= totalPages);
}

/** Próxima página afetada depois das que estão à vista (circular); `null` se não houver. */
export function nextAffectedPage(pages: readonly number[], visible: readonly number[]): number | null {
  if (pages.length === 0) return null;
  const last = visible.length > 0 ? Math.max(...visible) : 0;
  return pages.find((p) => p > last) ?? pages[0]!;
}

// ---- textos ----

const NUMBER = new Intl.NumberFormat("pt-BR");
function count(n: number, one: string, many: string): string {
  return `${NUMBER.format(n)} ${n === 1 ? one : many}`;
}

export type PreviewFact = { key: "insert" | "pages" | "unfilled" | "excluded"; value: string; label: string };

/** Fatos da prévia READY na ordem da tela: posicionáveis, páginas, reservas vazias, de fora. */
export function readyFacts(preview: AutoArrangePreview): PreviewFact[] {
  return [
    { key: "insert", value: NUMBER.format(preview.insertCount), label: preview.insertCount === 1 ? "carta posicionável" : "cartas posicionáveis" },
    { key: "pages", value: NUMBER.format(preview.pages.length), label: preview.pages.length === 1 ? "página afetada" : "páginas afetadas" },
    { key: "unfilled", value: NUMBER.format(preview.unfilledCount), label: preview.unfilledCount === 1 ? "reserva continua vazia" : "reservas continuam vazias" },
    { key: "excluded", value: NUMBER.format(preview.excludedCount), label: preview.excludedCount === 1 ? "carta fica de fora" : "cartas ficam de fora" },
  ];
}

/** Anúncio da região viva quando a leitura termina. */
export function previewAnnouncement(view: ArrangeView): string {
  switch (view.status) {
    case "closed":
      return "";
    case "loading":
      return "Lendo a prévia da organização automática.";
    case "error":
      return previewFailureMessage(view.reason);
    case "ready": {
      const p = view.preview;
      if (p.status === "EMPTY") return "Prévia pronta: nenhuma carta para posicionar agora.";
      if (p.status === "LIMIT_EXCEEDED") return `Prévia pronta: ${count(p.insertCount, "carta", "cartas")}, acima do limite de ${NUMBER.format(p.limit)} por vez.`;
      return `Prévia pronta: ${count(p.insertCount, "carta posicionável", "cartas posicionáveis")} em ${count(p.pages.length, "página", "páginas")}.`;
    }
  }
}

/**
 * Falha de LEITURA da prévia. A 5343 é só leitura: nada no fichário mudou,
 * qualquer que seja o motivo (inclusive resultado incerto da chamada).
 */
export function previewFailureMessage(reason: AutoArrangeFailure): string {
  switch (reason) {
    case "unsupported":
    case "not_owner":
    case "forbidden":
    case "archived":
    case "collection_not_found":
    case "binder_not_found":
    case "not_authenticated":
    case "unavailable":
      return failureMessage(reason);
    default:
      return "Não conseguimos ler a prévia agora. Nada foi alterado no fichário — tente de novo.";
  }
}

/** Erros em que "Tentar de novo" faz sentido (os demais dependem de outra ação do colecionador). */
export function previewRetryable(reason: AutoArrangeFailure): boolean {
  return !["unsupported", "not_owner", "forbidden", "archived", "collection_not_found", "binder_not_found", "not_authenticated", "unavailable"].includes(reason);
}
