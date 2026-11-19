"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { FileMinus2, Loader2, ShieldAlert, X } from "lucide-react";
import { readSharedBinderPages } from "@/app/colecoes/compartilhar/actions";
import { editorAddPage, editorRemovePage, editorReorderPages, readEditorBinderHeader } from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { OverviewReorder } from "@/components/colecoes/fichario/binder-overview";
import { MiniPage } from "@/components/colecoes/fichario/binder-overview";
import base from "@/components/colecoes/fichario/binder-add-pages.module.css";
import styles from "@/components/colecoes/fichario/binder-remove-page.module.css";
import type { SharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import { formatCount } from "@/lib/colecoes/acervo";
import { type BinderPage, PAGES_PER_READ, readBatchStart } from "@/lib/colecoes/binder";
import { pageRemovalRenumbering } from "@/lib/colecoes/binder-page-removal";
import {
  type EditorRemovalBlocker,
  type Exclusivity,
  type PageFailure,
  addPagesMessage,
  checkFreshPages,
  editorRemovalBlockerLabel,
  editorRemovalBlockers,
  exclusivityLesson,
  freshCheckMessage,
  pageFailureDisablesEditing,
  pageFailureMessage,
  pageFailureRechecksAccess,
  reorderPayload,
} from "@/lib/colecoes/editor-binder-pages";
import { type SharedBinderPage, sharedPageToBinderPage } from "@/lib/colecoes/sharing";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';
/** Leituras frescas em paralelo (lotes de 4 páginas) — o mesmo leitor da tela, sem rajada ilimitada. */
const FRESH_READ_CONCURRENCY = 4;

type Header = { pageCount: number; ownFilled: number };

/** Lote lido → páginas do fichário. Página do lote que não veio (≤ total) = folha vazia. */
export function toBinderCache(pages: SharedBinderPage[], batch: number, total: number, columns: number, rows: number): Map<number, BinderPage> {
  const byNumber = new Map(pages.map((page) => [page.pageNumber, page]));
  const cache = new Map<number, BinderPage>();
  for (let number = batch; number <= Math.min(total, batch + PAGES_PER_READ - 1); number += 1) {
    cache.set(number, sharedPageToBinderPage(byNumber.get(number) ?? { pageNumber: number, pockets: emptyPockets(columns, rows) }));
  }
  return cache;
}

function emptyPockets(columns: number, rows: number) {
  const pockets = [];
  for (let row = 1; row <= rows; row += 1) {
    for (let column = 1; column <= columns; column += 1) {
      pockets.push({ row, column, kind: "empty" as const, cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null });
    }
  }
  return pockets;
}

type RemoveState = {
  numbers: number[];
  chosen: number;
  status: "loading" | "ready" | "gone";
  /** Página como foi lida AGORA (releitura ao abrir e a cada confirmação). */
  page: BinderPage | null;
  /** Total de páginas lido junto com a página mostrada. */
  shownTotal: number;
  error: string | null;
};

/**
 * V1-13 · E2-3A — páginas pelo EDITOR (5382): adicionar, remover e reordenar,
 * só no fichário exclusivo da coleção. Nada otimista: cada operação parte de
 * uma releitura e termina com outra (cabeçalho + páginas). Remover e reordenar
 * são endereçados por NÚMERO, sem token de versão (R1): a releitura logo antes
 * de gravar reduz a janela de corrida, mas não a elimina.
 */
export function useEditorPages({
  editor,
  collectionId,
  columns,
  rows,
  totalPages,
  onHeader,
  replaceCache,
  invalidate,
  cachedNumbers,
}: {
  editor: SharedBinderEditor;
  collectionId: string;
  columns: number;
  rows: number;
  totalPages: number;
  /** Cabeçalho relido (total de páginas e cartas desta coleção). */
  onHeader: (header: Header) => void;
  /** Substitui o cache inteiro por páginas relidas (descarta leituras em voo). */
  replaceCache: (pages: Map<number, BinderPage>) => void;
  /** Esvazia o cache: a tela relê as páginas visíveis. */
  invalidate: () => void;
  /** Números das páginas hoje no cache (relidas no lugar depois de cada operação). */
  cachedNumbers: () => number[];
}) {
  const [exclusivity, setExclusivity] = useState<Exclusivity>("UNKNOWN");
  const [overviewOpen, setOverviewOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [adding, setAdding] = useState(false);
  const [remove, setRemove] = useState<RemoveState | null>(null);
  const [removing, setRemoving] = useState(false);
  const available = editor.active && exclusivity !== "NOT_EXCLUSIVE";
  const removeSeq = useRef(0);

  const closeAll = useCallback(() => {
    setOverviewOpen(false);
    setAddOpen(false);
    setRemove(null);
  }, []);

  const readHeader = useCallback(async (): Promise<Header | { failure: PageFailure }> => {
    const r = await readEditorBinderHeader({ collectionId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    return r.ok ? { pageCount: r.pageCount, ownFilled: r.ownFilled } : { failure: r.reason };
  }, [collectionId]);

  /** Lê de novo, direto do servidor (sem cache), os lotes que contêm as páginas pedidas. */
  const readFresh = useCallback(
    async (numbers: number[], total: number): Promise<Map<number, BinderPage> | null> => {
      const batches = [...new Set(numbers.filter((n) => n >= 1 && n <= total).map(readBatchStart))];
      const out = new Map<number, BinderPage>();
      let failed = false;
      for (let i = 0; i < batches.length && !failed; i += FRESH_READ_CONCURRENCY) {
        const slice = batches.slice(i, i + FRESH_READ_CONCURRENCY);
        const results = await Promise.all(
          slice.map((firstPage) => readSharedBinderPages({ collectionId, firstPage, columns, rows }).catch(() => ({ ok: false }) as const)),
        );
        results.forEach((result, index) => {
          const firstPage = slice[index];
          if (!result.ok || firstPage === undefined) {
            failed = true;
            return;
          }
          for (const [n, page] of toBinderCache(result.pages, firstPage, total, columns, rows)) out.set(n, page);
        });
      }
      return failed ? null : out;
    },
    [collectionId, columns, rows],
  );

  /** Recusa: D1 (só lição inequívoca), perda de permissão (desliga a edição) e mensagem neutra. */
  const absorb = useCallback(
    (op: "add" | "remove" | "reorder", reason: PageFailure) => {
      // A visão geral e os diálogos fecham nos dois casos: a mensagem vai para a base do fichário.
      if (exclusivityLesson(op, reason) === "NOT_EXCLUSIVE") {
        setExclusivity("NOT_EXCLUSIVE");
        closeAll();
        editor.notify({ tone: "info", text: pageFailureMessage(op, reason) });
      }
      if (pageFailureDisablesEditing(reason)) {
        closeAll();
        editor.loseAccess(pageFailureRechecksAccess(reason));
        editor.notify({ tone: "error", text: pageFailureMessage(op, reason) });
      }
    },
    [closeAll, editor],
  );

  /** Estado autorizado depois de qualquer operação: cabeçalho e páginas visíveis. */
  const syncAfter = useCallback(
    async (renumbered: boolean) => {
      if (renumbered) editor.afterRenumber();
      const header = await readHeader();
      if ("failure" in header) {
        if (pageFailureDisablesEditing(header.failure)) editor.loseAccess(pageFailureRechecksAccess(header.failure));
        invalidate();
        return;
      }
      onHeader(header);
      // Relê no lugar o que estava carregado (inclusive na visão geral), com a numeração nova; o resto é lido sob demanda.
      const fresh = await readFresh(cachedNumbers(), header.pageCount);
      if (fresh) replaceCache(fresh);
      else invalidate();
    },
    [cachedNumbers, editor, invalidate, onHeader, readFresh, readHeader, replaceCache],
  );

  const blocked = useCallback((): boolean => {
    if (editor.structuralBlocker) {
      editor.notify({ tone: "info", text: editor.structuralBlocker });
      return true;
    }
    return false;
  }, [editor]);

  // ---- adicionar (uma página por chamada; para na primeira recusa; nunca repete sozinho) ----
  const runAdd = useCallback(
    async (count: number) => {
      if (!available || adding) return;
      if (!editor.beginStructural()) {
        blocked();
        return;
      }
      setAdding(true);
      let added = 0;
      let failure: PageFailure | null = null;
      for (let i = 0; i < count; i += 1) {
        const r = await editorAddPage({ collectionId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
        if (!r.ok) {
          failure = r.reason;
          break;
        }
        added += 1;
      }
      await syncAfter(false);
      setAdding(false);
      setAddOpen(false);
      editor.endStructural();
      editor.notify(addPagesMessage(count, added, failure));
      if (failure) absorb("add", failure);
    },
    [absorb, adding, available, blocked, collectionId, editor, syncAfter],
  );

  // ---- remover: miniatura relida ao abrir e de novo logo antes de gravar ----
  const loadRemove = useCallback(
    async (numbers: number[], chosen: number) => {
      const seq = ++removeSeq.current;
      setRemove((prev) => ({ numbers, chosen, status: "loading", page: null, shownTotal: prev?.shownTotal ?? totalPages, error: prev?.chosen === chosen ? prev.error : null }));
      const header = await readHeader();
      if (seq !== removeSeq.current) return;
      if ("failure" in header) {
        absorb("remove", header.failure);
        setRemove((prev) => (prev ? { ...prev, status: "ready", error: pageFailureMessage("remove", header.failure) } : prev));
        return;
      }
      if (header.pageCount !== totalPages) {
        onHeader(header);
        invalidate();
      }
      const valid = numbers.filter((n) => n <= header.pageCount);
      if (chosen > header.pageCount) {
        setRemove({ numbers: valid, chosen, status: "gone", page: null, shownTotal: header.pageCount, error: null });
        return;
      }
      const fresh = await readFresh([chosen], header.pageCount);
      if (seq !== removeSeq.current) return;
      setRemove((prev) =>
        prev
          ? {
              ...prev,
              numbers: valid,
              status: "ready",
              page: fresh?.get(chosen) ?? null,
              shownTotal: header.pageCount,
              error: fresh ? prev.error : freshCheckMessage("remove", "unreadable"),
            }
          : prev,
      );
    },
    [absorb, invalidate, onHeader, readFresh, readHeader, totalPages],
  );

  const openRemove = useCallback(
    (numbers: number[], initial?: number) => {
      if (!available || blocked()) return;
      const valid = [...new Set(numbers.filter((n) => Number.isInteger(n) && n >= 1 && n <= totalPages))];
      const chosen = initial && valid.includes(initial) ? initial : valid[0];
      if (chosen === undefined) return;
      void loadRemove(valid, chosen);
    },
    [available, blocked, loadRemove, totalPages],
  );

  const confirmRemove = useCallback(async () => {
    const shown = remove;
    if (!shown || shown.status !== "ready" || !shown.page || removing) return;
    if (!editor.beginStructural()) {
      setRemove({ ...shown, error: editor.structuralBlocker ?? freshCheckMessage("remove", "unreadable") });
      return;
    }
    setRemoving(true);
    const n = shown.chosen;
    // R1: releitura imediatamente antes; se a página ou o total mudaram, nada é gravado.
    const header = await readHeader();
    const fresh = "failure" in header ? null : await readFresh([n], header.pageCount);
    const check = checkFreshPages([shown.page], shown.shownTotal, "failure" in header ? null : header.pageCount, fresh);
    if (!check.ok) {
      setRemoving(false);
      editor.endStructural();
      if ("failure" in header) absorb("remove", header.failure);
      else if (header.pageCount !== totalPages) {
        onHeader(header);
        invalidate();
      }
      const stillThere = !("failure" in header) && n <= header.pageCount;
      setRemove({
        ...shown,
        status: stillThere ? "ready" : "gone",
        page: stillThere ? (fresh?.get(n) ?? null) : null,
        shownTotal: "failure" in header ? shown.shownTotal : header.pageCount,
        error: freshCheckMessage("remove", check.reason),
      });
      return;
    }
    const r = await editorRemovePage({ collectionId, pageNumber: n }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    // Resultado incerto (timeout/erro de rede): a numeração pode ter mudado — trata como renumerada, por segurança.
    await syncAfter(r.ok || r.reason === "unknown");
    setRemoving(false);
    editor.endStructural();
    if (r.ok) {
      setRemove(null);
      editor.notify({ tone: "success", text: n < shown.shownTotal ? `Página ${n} removida. As páginas seguintes subiram um número.` : `Página ${n} removida.` });
      return;
    }
    absorb("remove", r.reason);
    if (pageFailureDisablesEditing(r.reason)) return;
    const message = pageFailureMessage("remove", r.reason);
    // Mostra a página como está agora, com a recusa (nada é repetido automaticamente).
    await loadRemove(shown.numbers, n);
    setRemove((prev) => (prev ? { ...prev, error: message } : prev));
  }, [absorb, collectionId, editor, invalidate, loadRemove, onHeader, readFresh, readHeader, remove, removing, syncAfter, totalPages]);

  // ---- reordenar: confere a ordem mostrada com uma releitura completa logo antes de gravar ----
  const reorder: OverviewReorder = useCallback(
    async (order) => {
      if (!editor.beginStructural()) return { ok: false, message: editor.structuralBlocker ?? "Aguarde a alteração em andamento terminar.", reset: false };
      try {
        const shownTotal = order.length;
        const header = await readHeader();
        if ("failure" in header) {
          absorb("reorder", header.failure);
          return { ok: false, message: pageFailureMessage("reorder", header.failure), reset: false };
        }
        const all = Array.from({ length: header.pageCount }, (_, i) => i + 1);
        const fresh = await readFresh(all, header.pageCount);
        const check = checkFreshPages(order, shownTotal, header.pageCount, fresh);
        if (!check.ok) {
          if (header.pageCount !== shownTotal) onHeader(header);
          if (fresh) replaceCache(fresh);
          return { ok: false, message: freshCheckMessage("reorder", check.reason), reset: check.reason !== "unreadable" };
        }
        const payload = reorderPayload(order, header.pageCount);
        if (!payload) return { ok: false, message: freshCheckMessage("reorder", "count_changed"), reset: true };
        // Uma única gravação por "Aplicar": nada aqui repete a chamada, nem em erro ou resultado incerto.
        const r = await editorReorderPages({ collectionId, order: payload }).catch(() => ({ ok: false, reason: "unknown" }) as const);
        const renumbered = r.ok ? r.changed : r.reason === "unknown";
        if (renumbered) editor.afterRenumber();
        // Releitura depois, sempre (cabeçalho + páginas). C2: no sucesso, ou numa recusa que fecha a visão geral,
        // a tela esvazia o cache e relê só o que estiver à vista (o Navegar lê sob demanda) — reler o fichário
        // inteiro de novo seria redundante. Recusa que mantém o Organizar ou resultado incerto: a ordem montada é
        // descartada e o Organizar precisa de todas as páginas, relidas agora.
        const closesOverview = !r.ok && (exclusivityLesson("reorder", r.reason) !== null || pageFailureDisablesEditing(r.reason));
        const after = await readHeader();
        if (!("failure" in after)) onHeader(after);
        if (r.ok || closesOverview || "failure" in after) {
          invalidate();
        } else {
          const pages = await readFresh(Array.from({ length: after.pageCount }, (_, i) => i + 1), after.pageCount);
          if (pages) replaceCache(pages);
          else invalidate();
        }
        if (r.ok) return { ok: true, message: r.changed ? "Nova ordem das páginas aplicada. Cartas e reservas foram junto com cada página." : "A ordem já era essa." };
        absorb("reorder", r.reason);
        return { ok: false, message: pageFailureMessage("reorder", r.reason), reset: true };
      } finally {
        editor.endStructural();
      }
    },
    [absorb, collectionId, editor, invalidate, onHeader, readFresh, readHeader, replaceCache],
  );

  return {
    available,
    exclusivity,
    overviewOpen,
    openOverview: () => {
      if (available) setOverviewOpen(true);
    },
    closeOverview: () => setOverviewOpen(false),
    addOpen,
    openAdd: () => {
      if (available && !blocked()) setAddOpen(true);
    },
    closeAdd: () => {
      if (!adding) setAddOpen(false);
    },
    adding,
    runAdd,
    remove,
    removing,
    openRemove,
    chooseRemove: (n: number) => remove && !removing && void loadRemove(remove.numbers, n),
    confirmRemove: () => void confirmRemove(),
    closeRemove: () => {
      if (removing) return;
      removeSeq.current += 1;
      setRemove(null);
    },
    reorder,
    canRemovePage: (page: BinderPage, total: number) => editorRemovalBlockers(page, total).length === 0,
    dialogOpen: overviewOpen || addOpen || remove !== null,
  };
}

export type EditorPages = ReturnType<typeof useEditorPages>;

/**
 * Confirmação de remoção do EDITOR. Mesma linguagem do diálogo do titular, mas
 * com a página relida agora (miniatura) e sem afirmar que ela está vazia: a
 * tela mascarada não sabe — o servidor confere sob a trava do fichário.
 */
export function EditorRemovePageDialog({
  host,
  state,
  busy,
  columns,
  rows,
  onChoose,
  onConfirm,
  onClose,
}: {
  host: HTMLElement | null;
  state: RemoveState;
  busy: boolean;
  columns: number;
  rows: number;
  onChoose: (n: number) => void;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const descId = useId();
  const blockers: EditorRemovalBlocker[] = state.page ? editorRemovalBlockers(state.page, state.shownTotal) : [];
  const ready = state.status === "ready" && state.page !== null;
  const canConfirm = ready && blockers.length === 0;
  const renumber = pageRemovalRenumbering(state.chosen, state.shownTotal);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    dialogRef.current?.querySelector<HTMLElement>("[data-autofocus]")?.focus({ preventScroll: true });
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  const onKeyRef = useRef<(event: KeyboardEvent) => void>(() => {});
  onKeyRef.current = (event: KeyboardEvent) => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      if (!busy) onClose();
      return;
    }
    if (["ArrowLeft", "ArrowRight", "PageUp", "PageDown", "Home", "End"].includes(event.key)) {
      event.stopPropagation();
      return;
    }
    if (event.key !== "Tab") return;
    event.stopPropagation();
    const nodes = [...dialog.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
    const first = nodes[0];
    const last = nodes[nodes.length - 1];
    if (!first || !last) return;
    if (event.shiftKey && (document.activeElement === first || document.activeElement === dialog)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    } else if (!dialog.contains(document.activeElement)) {
      event.preventDefault();
      first.focus();
    }
  };
  useEffect(() => {
    const listener = (event: KeyboardEvent) => onKeyRef.current(event);
    window.addEventListener("keydown", listener, true);
    return () => window.removeEventListener("keydown", listener, true);
  }, []);

  if (!host) return null;
  const n = state.chosen;
  const title =
    state.status === "gone"
      ? "Essa página não existe mais"
      : state.status === "loading"
        ? "Remover página"
        : blockers.length > 0
          ? `A página ${n} não pode ser removida por aqui`
          : `Remover a página ${n}?`;
  const lead =
    state.status === "gone"
      ? "O fichário mudou e essa página saiu ou mudou de número. Atualizamos o fichário."
      : state.status === "loading"
        ? "Lendo a página como ela está agora…"
        : blockers.length > 0
          ? "Para remover uma página por aqui, ela precisa estar sem cartas e sem reservas desta coleção."
          : "A página sai do fichário com os seus bolsos. O fichário é conferido de novo antes de remover — isso não pode ser desfeito.";

  return createPortal(
    <div className={base.veil} data-remove-page onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={dialogRef} role="alertdialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={descId} className={base.dialog} aria-busy={busy || state.status === "loading" || undefined}>
        <div className={base.head}>
          <span className={styles.icon} data-blocked={(ready && blockers.length > 0) || state.status === "gone" || undefined} aria-hidden>
            {ready && blockers.length > 0 ? <ShieldAlert /> : <FileMinus2 />}
          </span>
          <div>
            <h2 id={titleId} className={base.title}>
              {title}
            </h2>
            <p id={descId} className={base.lead}>
              {lead}
            </p>
          </div>
          <button type="button" className={base.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        {state.numbers.length > 1 ? (
          <div className={styles.options} role="radiogroup" aria-label="Página a remover">
            {state.numbers.map((number) => (
              <button
                key={number}
                type="button"
                role="radio"
                aria-checked={number === n}
                className={styles.option}
                onClick={() => onChoose(number)}
                disabled={busy}
                data-autofocus={number === n || undefined}
              >
                <span className={styles.optionNumber}>Página {number}</span>
              </button>
            ))}
          </div>
        ) : null}

        {state.status !== "gone" ? (
          <figure className="mx-auto my-3 w-40" aria-label={`Página ${n} como está agora`}>
            <MiniPage page={state.page} columns={columns} rows={rows} />
            <figcaption className="mt-1 text-center text-[11px] text-white/55">{state.status === "loading" ? "Lendo…" : "Como a página está agora"}</figcaption>
          </figure>
        ) : null}

        {ready && blockers.length > 0 ? (
          <ul className={styles.reasons} aria-label="O que impede a remoção">
            {blockers.map((reason) => (
              <li key={reason}>{editorRemovalBlockerLabel(reason)}</li>
            ))}
          </ul>
        ) : null}

        {canConfirm ? (
          <>
            <dl className={base.facts}>
              <div>
                <dt>Páginas</dt>
                <dd>
                  {formatCount(state.shownTotal)} → <strong>{formatCount(state.shownTotal - 1)}</strong>
                </dd>
              </div>
            </dl>
            <p className={base.note}>
              {renumber ? `As páginas ${renumber.from}–${renumber.to} passam a ser ${renumber.from - 1}–${renumber.to - 1}.` : "É a última página: nenhuma outra muda de número."}
            </p>
          </>
        ) : null}

        {state.error ? (
          <p className={styles.error} role="alert">
            {state.error}
          </p>
        ) : null}

        <div className={base.actions}>
          {canConfirm ? (
            <>
              <button type="button" className={base.secondary} onClick={onClose} disabled={busy} data-autofocus={state.numbers.length > 1 ? undefined : true}>
                Cancelar
              </button>
              <button type="button" className={styles.danger} onClick={onConfirm} disabled={busy}>
                {busy ? <Loader2 className="animate-spin motion-reduce:animate-none" aria-hidden /> : <FileMinus2 aria-hidden />}
                {busy ? "Conferindo e removendo…" : `Remover página ${n}`}
              </button>
            </>
          ) : (
            <button type="button" className={base.secondary} onClick={onClose} disabled={busy} data-autofocus={state.numbers.length > 1 ? undefined : true}>
              {state.status === "loading" ? "Cancelar" : "Entendi"}
            </button>
          )}
        </div>
      </div>
    </div>,
    host,
  );
}
