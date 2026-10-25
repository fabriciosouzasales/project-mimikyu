"use client";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { ArrowLeft, Loader2, Sparkles, X } from "lucide-react";
import { applyCatalogReconciliation, previewCatalogReconciliation, readCatalogNovelties } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type CatalogApplyResult,
  type CatalogNovelty,
  type CatalogNoveltyState,
  type CatalogPlanItem,
  type CatalogPreview,
  affectedPages,
  blockingItemKeys,
  canApplyPreview,
  catalogFailureMessage,
  failureNeedsFreshPreview,
  noveltyLabel,
  planItemMessage,
  previewSummaryMessage,
  selectionKeys,
} from "@/lib/colecoes/binder-catalog";
import base from "./binder-add-pages.module.css";
import styles from "./binder-catalog.module.css";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

type Stage = { step: "select" } | { step: "preview"; keys: string[]; status: "loading" } | { step: "preview"; keys: string[]; status: "ready"; preview: CatalogPreview } | { step: "preview"; keys: string[]; status: "error"; message: string };

function itemTone(kind: CatalogPlanItem["kind"]): "blocked" | "review" | undefined {
  if (kind === "BLOCKED" || kind === "NOT_EVALUATED") return "blocked";
  if (kind === "REVIEW_REQUIRED" || kind === "OUT_OF_ORDER" || kind === "NO_ANCHOR") return "review";
  return undefined;
}

/**
 * "Novidades do Catálogo" (BINDER-CATALOG-RECONCILIATION-FRONTEND-01): o
 * Catálogo Editorial ganhou posições do Set depois que o fichário desta
 * coleção Master Set foi montado (ou associado). Aqui o colecionador:
 *
 *  1. vê e escolhe as novidades (todas marcadas por padrão);
 *  2. pede a prévia (5265, não grava): destino de cada uma, bolsos que
 *     avançam, páginas afetadas e novas, capacidade antes/depois;
 *  3. confirma explicitamente — e marca, quando a prévia exige, "outra
 *     página" e "página nova" — para incorporar (5266).
 *
 * Bloqueios (bolso fixado, imagem em 2 bolsos, carta fora da ordem, reserva
 * genérica ambígua, sem vizinho, limite) aparecem com o motivo e o botão de
 * incorporar fica desligado; o atalho "Desmarcar" refaz a prévia sem eles.
 * PLAN_CHANGED / SELECTION_INVALID / INCONSISTENT relêem a lista e a prévia.
 * Uma novidade já incorporada e liberada depois não volta (o banco garante;
 * o texto explica). Mesmo teclado do "Adicionar páginas": Tab preso, Esc
 * fecha, setas não viram a página por baixo.
 */
export function CatalogNoveltiesDialog({
  host,
  collectionId,
  state,
  onStateChange,
  onApplied,
  onClose,
}: {
  host: HTMLElement | null;
  collectionId: string;
  state: Extract<CatalogNoveltyState, { eligible: true }>;
  /** Lista relida (após recusa por estado mudado). */
  onStateChange: (next: CatalogNoveltyState) => void;
  /** Incorporação confirmada pelo banco: o fichário relê as páginas afetadas. */
  onApplied: (result: CatalogApplyResult, pages: number[]) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const descId = useId();
  const [selected, setSelected] = useState<Set<string>>(() => new Set(state.items.map((i) => i.itemKey)));
  const [stage, setStage] = useState<Stage>({ step: "select" });
  const [confirmCross, setConfirmCross] = useState(false);
  const [confirmAdd, setConfirmAdd] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [announce, setAnnounce] = useState("");
  const byKey = useMemo(() => new Map(state.items.map((i) => [i.itemKey, i])), [state.items]);

  // A lista mudou (relida): a seleção fica só com o que ainda é novidade.
  useEffect(() => {
    setSelected((prev) => new Set([...prev].filter((k) => byKey.has(k))));
  }, [byKey]);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    dialogRef.current?.querySelector<HTMLElement>("[data-autofocus]")?.focus({ preventScroll: true });
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, []);

  const onKey = (event: KeyboardEvent) => {
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
  const onKeyRef = useRef(onKey);
  onKeyRef.current = onKey;
  useEffect(() => {
    const listener = (event: KeyboardEvent) => onKeyRef.current(event);
    window.addEventListener("keydown", listener, true);
    return () => window.removeEventListener("keydown", listener, true);
  }, []);

  const reloadList = useCallback(async () => {
    const result = await readCatalogNovelties({ collectionId }).catch(() => null);
    if (result && result.ok) onStateChange(result.state);
  }, [collectionId, onStateChange]);

  const loadPreview = useCallback(
    async (keys: string[]) => {
      setError(null);
      setConfirmCross(false);
      setConfirmAdd(false);
      if (keys.length === 0) {
        setStage({ step: "select" });
        return;
      }
      setStage({ step: "preview", keys, status: "loading" });
      const result = await previewCatalogReconciliation({ collectionId, keys }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
      if (result.ok) {
        setStage({ step: "preview", keys, status: "ready", preview: result.preview });
        setAnnounce(previewSummaryMessage(result.preview));
        return;
      }
      const message = catalogFailureMessage(result.reason);
      setStage({ step: "preview", keys, status: "error", message });
      setAnnounce(message);
      if (result.reason === "selection_invalid") void reloadList();
    },
    [collectionId, reloadList],
  );

  const toggle = (key: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  const deselectAndRepreview = (keys: string[]) => {
    const drop = new Set(keys);
    const next = new Set([...selected].filter((k) => !drop.has(k)));
    setSelected(next);
    void loadPreview(selectionKeys(state.items, next));
  };

  const apply = async () => {
    if (stage.step !== "preview" || stage.status !== "ready" || busy) return;
    const preview = stage.preview;
    if (!canApplyPreview(preview, { crossPage: confirmCross, addPage: confirmAdd }) || !preview.planToken) return;
    setBusy(true);
    setError(null);
    const result = await applyCatalogReconciliation({
      collectionId,
      keys: stage.keys,
      planToken: preview.planToken,
      confirmCrossPage: confirmCross,
      confirmAddPage: confirmAdd,
    }).catch(() => ({ ok: false as const, reason: "unknown" as const }));
    setBusy(false);
    if (!result.ok) {
      const message = catalogFailureMessage(result.reason);
      setError(message);
      setAnnounce(message);
      if (failureNeedsFreshPreview(result.reason) || result.reason === "unknown") {
        await reloadList();
        void loadPreview(stage.keys.filter((k) => byKey.has(k)));
      }
      return;
    }
    onApplied(result.result, affectedPages(preview));
  };

  if (!host) return null;
  const selectedCount = selected.size;
  const ready = stage.step === "preview" && stage.status === "ready" ? stage.preview : null;
  const blocking = ready ? new Set(blockingItemKeys(ready)) : new Set<string>();
  const applicable = canApplyPreview(ready, { crossPage: confirmCross, addPage: confirmAdd });
  const pages = ready ? affectedPages(ready) : [];

  return createPortal(
    <div className={base.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={descId} className={base.dialog} data-wide aria-busy={busy || undefined}>
        <div className={base.head}>
          <span className={base.icon} aria-hidden>
            <Sparkles />
          </span>
          <div>
            <h2 id={titleId} className={base.title}>
              Novidades do Catálogo
            </h2>
            <p id={descId} className={base.lead}>
              {state.count === 1
                ? "1 posição do seu objetivo chegou ao Catálogo depois que este fichário foi montado."
                : `${formatCount(state.count)} posições do seu objetivo chegaram ao Catálogo depois que este fichário foi montado.`}{" "}
              Incorporar reserva um bolso na ordem do Set para cada uma — nenhuma carta sai do lugar sem aparecer na prévia.
            </p>
          </div>
          <button type="button" className={base.close} onClick={onClose} aria-label="Fechar" disabled={busy} data-autofocus>
            <X aria-hidden />
          </button>
        </div>

        {stage.step === "select" ? (
          <>
            <div className={styles.toolbar}>
              <span>
                {formatCount(selectedCount)} de {formatCount(state.count)} selecionada{state.count === 1 ? "" : "s"}
              </span>
              {state.count > 1 ? (
                <button
                  type="button"
                  className={styles.link}
                  onClick={() => setSelected(selectedCount === state.count ? new Set() : new Set(state.items.map((i) => i.itemKey)))}
                >
                  {selectedCount === state.count ? "Desmarcar todas" : "Marcar todas"}
                </button>
              ) : null}
            </div>
            <ul className={styles.list} aria-label="Novidades">
              {state.items.map((item) => (
                <NoveltyRow key={item.itemKey} item={item} checked={selected.has(item.itemKey)} onToggle={() => toggle(item.itemKey)} />
              ))}
            </ul>
            <p className={base.note}>
              Uma novidade incorporada e depois liberada não volta para esta lista. Reservas que você liberou de posições antigas também não são novidades — continuam como “Falta” na coleção e podem ser reservadas à mão.
            </p>
            <div className={base.actions}>
              <button type="button" className={base.secondary} onClick={onClose}>
                Agora não
              </button>
              <button type="button" className={base.primary} onClick={() => void loadPreview(selectionKeys(state.items, selected))} disabled={selectedCount === 0}>
                Ver prévia
              </button>
            </div>
          </>
        ) : stage.status === "loading" ? (
          <p className={base.note} role="status">
            <Loader2 className="mr-1.5 inline h-3.5 w-3.5 animate-spin align-[-2px]" aria-hidden />
            Calculando onde cada novidade entra…
          </p>
        ) : stage.status === "error" ? (
          <>
            <p className={base.note} role="alert">
              {stage.message}
            </p>
            <div className={base.actions}>
              <button type="button" className={base.secondary} onClick={() => setStage({ step: "select" })}>
                <ArrowLeft className="h-4 w-4" aria-hidden />
                Voltar à seleção
              </button>
              <button type="button" className={base.primary} onClick={() => void loadPreview(selectionKeys(state.items, selected))} disabled={selected.size === 0}>
                Tentar de novo
              </button>
            </div>
          </>
        ) : ready ? (
          <>
            <p className={base.note} style={{ color: ready.outcome === "READY" ? undefined : "hsl(38 92% 76%)" }}>
              {previewSummaryMessage(ready)}
            </p>

            {ready.outcome === "READY" || ready.items.length > 0 ? (
              <dl className={base.facts}>
                <div>
                  <dt>Capacidade</dt>
                  <dd>
                    <strong>{ready.capacityBefore !== null ? formatCount(ready.capacityBefore) : "—"}</strong>
                    {ready.capacityAfter !== null && ready.capacityAfter !== ready.capacityBefore ? ` → ${formatCount(ready.capacityAfter)}` : ""} bolsos
                  </dd>
                </div>
                <div>
                  <dt>Livres depois</dt>
                  <dd>
                    <strong>{ready.freePocketsAfter !== null ? formatCount(ready.freePocketsAfter) : "—"}</strong>
                  </dd>
                </div>
                <div>
                  <dt>Itens que mudam de bolso</dt>
                  <dd>
                    <strong>{formatCount(ready.totalRowsMoved)}</strong>
                  </dd>
                </div>
                <div>
                  <dt>{pages.length === 1 ? "Página afetada" : "Páginas afetadas"}</dt>
                  <dd>
                    <strong>{pages.length > 0 ? pages.join(", ") : "—"}</strong>
                  </dd>
                </div>
              </dl>
            ) : null}

            {ready.items.length > 0 ? (
              <ul className={styles.list} aria-label="Onde cada novidade entra">
                {ready.items.map((planItem) => {
                  const novelty = byKey.get(planItem.itemKey);
                  const tone = itemTone(planItem.kind);
                  return (
                    <li key={planItem.itemKey} className={styles.row} data-tone={tone} style={{ gridTemplateColumns: "minmax(0, 1fr)" }}>
                      <div>
                        <p className={styles.name}>{novelty ? noveltyLabel(novelty) : "Novidade"}</p>
                        <p className={styles.detail}>{planItemMessage(planItem)}</p>
                        {tone ? (
                          <span className={styles.flag} data-tone={tone}>
                            {tone === "blocked" ? "Bloqueada" : "Precisa de revisão"}
                          </span>
                        ) : null}
                      </div>
                    </li>
                  );
                })}
              </ul>
            ) : null}

            {blocking.size > 0 && selected.size > blocking.size ? (
              <div className={styles.toolbar}>
                <span>
                  {blocking.size === 1 ? "1 novidade impede a incorporação." : `${blocking.size} novidades impedem a incorporação.`}
                </span>
                <button type="button" className={styles.link} onClick={() => deselectAndRepreview([...blocking])}>
                  Desmarcar e ver a prévia de novo
                </button>
              </div>
            ) : null}

            {ready.outcome === "READY" && ready.requiresCrossPage ? (
              <label className={styles.confirm}>
                <input type="checkbox" className={styles.check} checked={confirmCross} onChange={(e) => setConfirmCross(e.target.checked)} disabled={busy} />
                <span>Entendi que bolsos passam para a página seguinte.</span>
              </label>
            ) : null}
            {ready.outcome === "READY" && ready.requiresAddPage ? (
              <label className={styles.confirm}>
                <input type="checkbox" className={styles.check} checked={confirmAdd} onChange={(e) => setConfirmAdd(e.target.checked)} disabled={busy} />
                <span>
                  Adicionar {ready.pagesAdded === 1 ? `a página ${ready.addedPageNumbers[0] ?? ""}` : `as páginas ${ready.addedPageNumbers.join(", ")}`} ao fim do fichário.
                </span>
              </label>
            ) : null}

            <div className={base.actions}>
              <button type="button" className={base.secondary} onClick={() => setStage({ step: "select" })} disabled={busy}>
                <ArrowLeft className="h-4 w-4" aria-hidden />
                Voltar
              </button>
              <button type="button" className={base.primary} onClick={() => void apply()} disabled={busy || !applicable} aria-describedby={applicable ? undefined : descId}>
                {busy ? <Loader2 className="animate-spin" aria-hidden /> : <Sparkles aria-hidden />}
                {busy ? "Incorporando…" : ready.totalItems === 1 ? "Incorporar 1 novidade" : `Incorporar ${formatCount(ready.totalItems)} novidades`}
              </button>
            </div>
          </>
        ) : null}

        {error ? (
          <p className={base.note} role="alert" style={{ color: "hsl(0 85% 78%)" }}>
            {error}
          </p>
        ) : null}
        <span className="sr-only" aria-live="polite" aria-atomic="true">
          {announce}
        </span>
      </div>
    </div>,
    host,
  );
}

function NoveltyRow({ item, checked, onToggle }: { item: CatalogNovelty; checked: boolean; onToggle: () => void }) {
  const id = useId();
  return (
    <li className={styles.row}>
      <input id={id} type="checkbox" className={styles.check} checked={checked} onChange={onToggle} />
      <label htmlFor={id} style={{ cursor: "pointer" }}>
        <span className={styles.name}>{noveltyLabel(item)}</span>
        {item.placedInBinder ? (
          <span className={styles.detail} style={{ display: "block" }}>
            Você já tem esta carta em algum bolso: se for o bolso certo, ele passa a ficar reservado; se estiver fora da ordem, a prévia avisa e ela fica onde está.
          </span>
        ) : null}
        {item.placedInBinder ? <span className={styles.flag}>Já no fichário</span> : null}
      </label>
    </li>
  );
}
