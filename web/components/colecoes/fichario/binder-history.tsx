"use client";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import {
  Activity,
  Archive,
  ArrowLeftRight,
  ArrowRight,
  BookOpen,
  Bookmark,
  BookmarkMinus,
  Check,
  ChevronDown,
  FileMinus2,
  FilePlus2,
  Link2,
  ListOrdered,
  Lock,
  LockOpen,
  LogOut,
  Minus,
  MoveHorizontal,
  Plus,
  Repeat,
  Sparkles,
  Unlink,
} from "lucide-react";
import { readBinderActivity, readBinderActivityCoverage } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import {
  ACTIVITY_FILTERS,
  LEGACY_BADGE,
  type ActivityCoverage,
  type ActivityEvent,
  type ActivityFailure,
  type ActivityFilterKey,
  type ActivityIcon,
  activityFailureMessage,
  countNewer,
  coverageNote,
  dayFullLabel,
  cursorAfter,
  describeEvent,
  detailFields,
  detailItems,
  headlineEvent,
  emptyMessage,
  groupByDay,
  mergeActivity,
  timeLabel,
  truncationNote,
} from "@/lib/colecoes/binder-activity";
import { cn } from "@/lib/utils";
import styles from "./binder-control.module.css";

// Traço fino e formas abertas: legíveis a 13 px (sem ícones "quadrados" que viram caixas vazias).
const ICONS: Record<ActivityIcon, typeof Activity> = {
  card: Plus,
  move: ArrowRight,
  swap: ArrowLeftRight,
  remove: Minus,
  leave: LogOut,
  reserve: Bookmark,
  release: BookmarkMinus,
  lock: Lock,
  unlock: LockOpen,
  page: FilePlus2,
  pageRemove: FileMinus2,
  gap: MoveHorizontal,
  reorder: ListOrdered,
  catalog: Sparkles,
  binder: BookOpen,
  link: Link2,
  unlink: Unlink,
  transfer: Repeat,
  close: Archive,
  activity: Activity,
};

type ListState =
  | { status: "loading" }
  | { status: "error"; reason: ActivityFailure }
  | { status: "ready"; events: ActivityEvent[]; hasMore: boolean; more: "idle" | "loading" | "error" };

/**
 * Histórico do fichário (P3-B S7, §3.3) — seção do Centro de Controle.
 *
 * Montada só com a seção aberta (quem chama decide). Lista do mais recente ao
 * mais antigo, agrupada por dia; filtros por categoria; 20 por vez com
 * "Mostrar mais" (cursor estável, sem duplicar); "Ver detalhes" por evento.
 * Mudanças no fichário nesta sessão (`refreshKey`) releem a primeira página em
 * silêncio e juntam o que for novo, sem perder o que já foi carregado.
 * Só leitura: a 5269 devolve apenas eventos do titular da sessão.
 */
export function BinderHistory({ layoutId, refreshKey }: { layoutId: string; refreshKey: string }) {
  const [filter, setFilter] = useState<ActivityFilterKey>("ALL");
  const [list, setList] = useState<ListState>({ status: "loading" });
  const [coverage, setCoverage] = useState<ActivityCoverage | null>(null);
  const [expanded, setExpanded] = useState<ReadonlySet<number>>(() => new Set());
  const [announce, setAnnounce] = useState("");
  // `generation` muda a cada troca de filtro/recarga visível: respostas de uma
  // geração anterior (primeira página ou "Mostrar mais") são descartadas.
  const generationRef = useRef(0);
  const silentRef = useRef(0);
  const filterRef = useRef(filter);
  filterRef.current = filter;
  const listRef = useRef(list);
  listRef.current = list;

  const loadFirst = useCallback(
    async (silent: boolean) => {
      const generation = silent ? generationRef.current : ++generationRef.current;
      const silentRequest = ++silentRef.current;
      if (!silent) setList({ status: "loading" });
      const result = await readBinderActivity({ layoutId, filter: filterRef.current, cursor: null }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
      if (generation !== generationRef.current || silentRequest !== silentRef.current) return;
      const current = listRef.current;
      if (!result.ok) {
        // Releitura silenciosa que falha mantém a lista atual à vista.
        if (!(silent && current.status === "ready")) setList({ status: "error", reason: result.reason });
        return;
      }
      if (silent && current.status === "ready") {
        const fresh = countNewer(current.events, result.events);
        if (fresh === 0) return;
        setAnnounce(fresh === 1 ? "1 nova atividade no histórico." : `${fresh} novas atividades no histórico.`);
        setList({ ...current, events: mergeActivity(current.events, result.events) });
        return;
      }
      setList({ status: "ready", events: result.events, hasMore: result.hasMore, more: "idle" });
    },
    [layoutId],
  );

  const loadCoverage = useCallback(async () => {
    const result = await readBinderActivityCoverage({ layoutId }).catch(() => null);
    // A nota de cobertura é complementar: falha só a omite.
    setCoverage(result && result.ok ? result.coverage : null);
  }, [layoutId]);

  useEffect(() => {
    setExpanded(new Set());
    void loadFirst(false);
  }, [filter, loadFirst]);

  useEffect(() => {
    void loadCoverage();
  }, [loadCoverage]);

  const firstKey = useRef(refreshKey);
  useEffect(() => {
    if (refreshKey === firstKey.current) return;
    firstKey.current = refreshKey;
    void loadFirst(true);
  }, [refreshKey, loadFirst]);

  const loadMore = useCallback(async () => {
    const start = listRef.current;
    if (start.status !== "ready" || start.more === "loading" || !start.hasMore) return;
    const cursor = cursorAfter(start.events);
    const generation = generationRef.current; // troca de filtro cancela esta página
    setList({ ...start, more: "loading" });
    const result = await readBinderActivity({ layoutId, filter: filterRef.current, cursor }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
    if (generation !== generationRef.current) return;
    const current = listRef.current;
    if (current.status !== "ready") return;
    if (!result.ok) {
      setList({ ...current, more: "error" });
      return;
    }
    const merged = mergeActivity(current.events, result.events);
    const added = merged.length - current.events.length;
    const hasMore = result.hasMore && added > 0;
    setAnnounce(
      added > 0 ? `${added === 1 ? "1 atividade carregada" : `${added} atividades carregadas`}${hasMore ? "." : ". Fim do histórico."}` : "Fim do histórico.",
    );
    setList({ status: "ready", events: merged, hasMore, more: "idle" });
  }, [layoutId]);

  const toggle = useCallback((id: number) => {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const filterId = useId();
  const days = useMemo(() => (list.status === "ready" ? groupByDay(list.events, new Date()) : []), [list]);
  const note = coverageNote(coverage);

  return (
    <div className={styles.history}>
      <div className={styles.historyToolbar}>
        <span id={`${filterId}-label`} className={styles.historyToolbarLabel}>
          Mostrar
        </span>
        <HistoryFilterMenu id={filterId} labelId={`${filterId}-label`} value={filter} onChange={(next) => next !== filter && setFilter(next)} />
      </div>

      <p className="sr-only" role="status" aria-live="polite">
        {announce}
      </p>

      {list.status === "loading" ? (
        <div aria-busy="true" aria-label="Carregando o histórico" className="mt-3">
          <div className={styles.skeleton} style={{ width: "35%" }} />
          <div className={styles.skeleton} style={{ width: "100%" }} />
          <div className={styles.skeleton} style={{ width: "85%" }} />
          <div className={styles.skeleton} style={{ width: "92%" }} />
        </div>
      ) : list.status === "error" ? (
        <div role="alert" className={cn(styles.hint, "mt-3")}>
          {activityFailureMessage(list.reason)}{" "}
          {list.reason !== "not_authenticated" ? (
            <button type="button" className={styles.historyRetry} onClick={() => void loadFirst(false)}>
              Tentar de novo
            </button>
          ) : null}
        </div>
      ) : list.events.length === 0 ? (
        <div className="mt-3">
          <p className={styles.hint}>{emptyMessage(filter)}</p>
          {filter === "ALL" && note ? <p className={cn(styles.hint, styles.historyEnd)}>{note}</p> : null}
        </div>
      ) : (
        <>
          {days.map((day) => (
            <section key={day.key} className={styles.historyDay} aria-labelledby={`${filterId}-${day.key}`}>
              <h4 id={`${filterId}-${day.key}`} className={styles.historyDayLabel}>
                <time dateTime={day.key} aria-label={dayFullLabel(day.key)}>
                  {day.label}
                </time>
              </h4>
              <ol className={styles.logList}>
                {day.events.map((event) => (
                  <HistoryEntry key={event.id} event={event} open={expanded.has(event.id)} onToggle={toggle} />
                ))}
              </ol>
            </section>
          ))}

          {list.hasMore ? (
            <div className={styles.historyMore}>
              {list.more === "error" ? (
                <p role="alert" className={styles.hint}>
                  Não foi possível carregar mais.{" "}
                  <button type="button" className={styles.historyRetry} onClick={() => void loadMore()}>
                    Tentar de novo
                  </button>
                </p>
              ) : (
                <button type="button" className={styles.linkButton} onClick={() => void loadMore()} disabled={list.more === "loading"} aria-busy={list.more === "loading" || undefined}>
                  {list.more === "loading" ? "Carregando…" : "Mostrar mais"}
                </button>
              )}
            </div>
          ) : (
            <p className={cn(styles.hint, styles.historyEnd)}>
              {filter === "ALL" && note ? note : "Fim do histórico."}
            </p>
          )}
        </>
      )}
    </div>
  );
}

function HistoryEntry({ event, open, onToggle }: { event: ActivityEvent; open: boolean; onToggle: (id: number) => void }) {
  const view = describeEvent(event);
  const headline = headlineEvent(event);
  const Icon = ICONS[view.icon];
  const detailsId = useId();
  const time = timeLabel(event.occurredAt);
  const fields = open ? detailFields(event) : [];
  const items = open ? detailItems(event) : [];
  const truncated = open ? truncationNote(event) : null;
  return (
    <li className={styles.logEntry} data-open={open || undefined}>
      {/* A linha inteira abre os detalhes (sempre há data completa, autoria e frase integral). */}
      <button
        type="button"
        className={styles.logRow}
        aria-expanded={open}
        aria-controls={detailsId}
        title={view.title}
        onClick={() => onToggle(event.id)}
      >
        <span className={styles.logIcon} aria-hidden>
          <Icon strokeWidth={1.75} />
        </span>
        <span className={styles.logText}>
          {headline}
          {view.legacy ? <span className={styles.logLegacy}> · {LEGACY_BADGE}</span> : null}
        </span>
        <time className={styles.logTime} dateTime={event.occurredAt}>
          {time}
        </time>
        <ChevronDown className={styles.logChevron} aria-hidden />
      </button>
      <div id={detailsId} className={styles.logDetails} hidden={!open}>
        {open ? (
          <>
            <dl className={styles.logFields}>
              {fields.map((f) => (
                <div key={f.label} className={styles.logField}>
                  <dt>{f.label}</dt>
                  <dd>{f.value}</dd>
                </div>
              ))}
            </dl>
            {items.length > 0 ? (
              <>
                <p className={styles.logItemsTitle}>Itens ({event.itemCount.toLocaleString("pt-BR")})</p>
                <ul className={styles.logItems}>
                  {items.map((line) => (
                    <li key={line.key}>{line.text}</li>
                  ))}
                </ul>
              </>
            ) : null}
            {truncated ? <p className={styles.logNote}>{truncated}</p> : null}
          </>
        ) : null}
      </div>
    </li>
  );
}

const FILTER_LABEL = (key: ActivityFilterKey) => (key === "ALL" ? "Todas as atividades" : (ACTIVITY_FILTERS.find((f) => f.key === key)?.label ?? ""));

/**
 * Seletor do filtro no estilo do painel (lista própria, sem o realce azul do
 * sistema operacional). Padrão de combobox "select-only" (WAI-ARIA APG):
 * botão com aria-haspopup="listbox" + lista com aria-activedescendant.
 * Teclado: ↑/↓ abrem e navegam, Home/End, Enter/Espaço escolhem, Esc fecha
 * e devolve o foco, Tab fecha; digitar a inicial salta para a opção.
 */
function HistoryFilterMenu({
  id,
  labelId,
  value,
  onChange,
}: {
  id: string;
  labelId: string;
  value: ActivityFilterKey;
  onChange: (next: ActivityFilterKey) => void;
}) {
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(() => Math.max(0, ACTIVITY_FILTERS.findIndex((f) => f.key === value)));
  const rootRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const listId = `${id}-list`;
  const optionId = (i: number) => `${id}-opt-${i}`;

  const openMenu = useCallback(
    (index?: number) => {
      setActive(index ?? Math.max(0, ACTIVITY_FILTERS.findIndex((f) => f.key === value)));
      setOpen(true);
    },
    [value],
  );

  const choose = useCallback(
    (index: number) => {
      const option = ACTIVITY_FILTERS[index];
      setOpen(false);
      buttonRef.current?.focus();
      if (option) onChange(option.key);
    },
    [onChange],
  );

  // Clique fora fecha sem escolher.
  useEffect(() => {
    if (!open) return;
    function onPointer(event: PointerEvent) {
      if (!rootRef.current?.contains(event.target as Node)) setOpen(false);
    }
    document.addEventListener("pointerdown", onPointer);
    return () => document.removeEventListener("pointerdown", onPointer);
  }, [open]);

  const onKeyDown = (event: React.KeyboardEvent<HTMLButtonElement>) => {
    const last = ACTIVITY_FILTERS.length - 1;
    switch (event.key) {
      case "ArrowDown":
        event.preventDefault();
        if (!open) openMenu();
        else setActive((i) => Math.min(last, i + 1));
        return;
      case "ArrowUp":
        event.preventDefault();
        if (!open) openMenu();
        else setActive((i) => Math.max(0, i - 1));
        return;
      case "Home":
        if (open) {
          event.preventDefault();
          setActive(0);
        }
        return;
      case "End":
        if (open) {
          event.preventDefault();
          setActive(last);
        }
        return;
      case "Enter":
      case " ":
        event.preventDefault();
        if (open) choose(active);
        else openMenu();
        return;
      case "Escape":
        if (open) {
          // Não deixa o Esc fechar o Centro de Controle quando só a lista está aberta.
          event.preventDefault();
          event.stopPropagation();
          setOpen(false);
        }
        return;
      case "Tab":
        setOpen(false);
        return;
      default:
        if (open && event.key.length === 1) {
          const k = event.key.toLocaleLowerCase("pt-BR");
          const found = ACTIVITY_FILTERS.findIndex((f, i) => i > active && FILTER_LABEL(f.key).toLocaleLowerCase("pt-BR").startsWith(k));
          const wrap = found >= 0 ? found : ACTIVITY_FILTERS.findIndex((f) => FILTER_LABEL(f.key).toLocaleLowerCase("pt-BR").startsWith(k));
          if (wrap >= 0) setActive(wrap);
        }
    }
  };

  return (
    <div ref={rootRef} className={styles.filterMenu}>
      <button
        ref={buttonRef}
        id={id}
        type="button"
        className={styles.filterTrigger}
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-labelledby={`${labelId} ${id}`}
        aria-activedescendant={open ? optionId(active) : undefined}
        onClick={() => (open ? setOpen(false) : openMenu())}
        onKeyDown={onKeyDown}
      >
        {/* Largura fixa: todos os rótulos ocupam a mesma célula do grid, então o
            botão mede sempre o rótulo mais longo; só o atual fica visível. */}
        <span className={styles.filterValue}>
          {ACTIVITY_FILTERS.map(({ key }) => (
            <span key={key} aria-hidden={key === value ? undefined : true} data-current={key === value || undefined}>
              {FILTER_LABEL(key)}
            </span>
          ))}
        </span>
        <ChevronDown className={styles.filterChevron} aria-hidden />
      </button>
      {open ? (
        <ul id={listId} role="listbox" aria-labelledby={labelId} className={styles.filterList} tabIndex={-1}>
          {ACTIVITY_FILTERS.map((f, i) => {
            const selected = f.key === value;
            return (
              <li
                key={f.key}
                id={optionId(i)}
                role="option"
                aria-selected={selected}
                data-active={i === active || undefined}
                className={styles.filterOption}
                onPointerEnter={() => setActive(i)}
                onPointerDown={(e) => e.preventDefault()}
                onClick={() => choose(i)}
              >
                <span>{FILTER_LABEL(f.key)}</span>
                {selected ? <Check className={styles.filterCheck} aria-hidden /> : null}
              </li>
            );
          })}
        </ul>
      ) : null}
    </div>
  );
}

