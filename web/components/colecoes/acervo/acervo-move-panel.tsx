"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useId, useRef, useState, useTransition } from "react";
import { Loader2, RotateCcw, X } from "lucide-react";
import { moveMyCopies, previewMyCopiesMove } from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { Select } from "@/components/ui/select";
import { formatCount, pluralize } from "@/lib/colecoes/acervo";
import {
  type MoveFailure,
  moveConfirmAction,
  moveConfirmTitle,
  moveFailureMessage,
  moveSuccessMessage,
} from "@/lib/colecoes/acervo-move";
import type { MovePreview } from "@/lib/colecoes/acervo-move-queries";
import { type Selection, selectionTotals } from "@/lib/colecoes/acervo-selection";
import { LOCAIS_PATH, type StorageLocation } from "@/lib/colecoes/storage-locations";
import styles from "./acervo.module.css";
import review from "../colecoes/collection-objective.module.css";
import organize from "../colecoes/collection-organize.module.css";
import local from "./acervo-selection.module.css";

/**
 * WHERE-05B — painel "Mover exemplares" (lateral no desktop, tela cheia no
 * mobile; mesma base Radix Dialog do detalhe do acervo).
 *
 * Fluxo: destino → prévia (resolvida no servidor) → confirmação explícita →
 * gravação (uma chamada à 5024) → resultado. Recuperação:
 *  - cartas sem exemplar no recorte (salvaguarda 1): a confirmação fica
 *    bloqueada até o colecionador tirá-las da seleção — nova prévia;
 *  - acervo mudou entre prévia e confirmação: nova prévia, nada gravado;
 *  - local excluído: escolher outro destino;
 *  - resultado desconhecido: refazer a prévia (nunca repetir às cegas).
 * Durante a gravação o painel não fecha.
 */

const CLEAR = "__clear__";
const ARIA_DISABLED = "aria-disabled:pointer-events-none aria-disabled:opacity-50";

type Phase =
  | { kind: "choose"; error?: MoveFailure }
  | { kind: "loading" }
  | { kind: "ready"; preview: MovePreview; changed: boolean }
  | { kind: "failed"; reason: MoveFailure }
  | { kind: "saving"; preview: MovePreview }
  | { kind: "unknown" }
  | { kind: "done"; text: string };

export function AcervoMovePanel({
  selection,
  scope,
  locations,
  onClose,
  onRemoveKeys,
  onDone,
}: {
  selection: Selection;
  scope: string;
  locations: StorageLocation[] | null;
  onClose(): void;
  onRemoveKeys(keys: string[]): void;
  onDone(text: string): void;
}) {
  const router = useRouter();
  const selectId = useId();
  const titleId = useId();
  const [, startRefresh] = useTransition();
  const [choice, setChoice] = useState("");
  const [phase, setPhase] = useState<Phase>({ kind: "choose" });
  const busy = phase.kind === "loading" || phase.kind === "saving";
  const headingRef = useRef<HTMLHeadingElement>(null);
  const target = choice === CLEAR ? null : choice || undefined;
  const totals = selectionTotals(selection);
  const names = new Map(selection.items.map((item) => [item.key, item.name]));

  const focusHeading = () => requestAnimationFrame(() => headingRef.current?.focus());
  const refresh = () => startRefresh(() => router.refresh());

  async function runPreview(keys: string[]) {
    if (target === undefined || keys.length === 0) return;
    setPhase({ kind: "loading" });
    let result: Awaited<ReturnType<typeof previewMyCopiesMove>>;
    try {
      result = await previewMyCopiesMove({ keys, scope, target });
    } catch {
      result = { ok: false, reason: "unavailable" }; // leitura: nada foi gravado
    }
    if (result.ok) setPhase({ kind: "ready", preview: result.preview, changed: false });
    else if (result.reason === "storage_gone") {
      refresh();
      setPhase({ kind: "choose", error: "storage_gone" });
    } else setPhase({ kind: "failed", reason: result.reason });
    focusHeading();
  }

  async function confirm(preview: MovePreview) {
    if (busy || target === undefined) return;
    setPhase({ kind: "saving", preview });
    let result: Awaited<ReturnType<typeof moveMyCopies>>;
    try {
      result = await moveMyCopies({
        keys: selection.items.map((item) => item.key),
        scope,
        target,
        planToken: preview.token,
        expectedCount: preview.toMove,
      });
    } catch {
      // A requisição pode ter chegado ao servidor: não dá para saber.
      result = { ok: false, reason: "unknown" };
    }
    if (result.ok) {
      const text =
        result.updated === 0
          ? "Nada mudou: todos os exemplares já estavam no destino."
          : moveSuccessMessage(result.updated, result.targetName, result.atTarget);
      refresh();
      onDone(text);
      setPhase({ kind: "done", text });
    } else if (result.reason === "plan_changed" && "preview" in result) {
      refresh();
      setPhase({ kind: "ready", preview: result.preview, changed: true });
    } else if (result.reason === "plan_changed" || result.reason === "unresolved") {
      refresh();
      await runPreview(selection.items.map((item) => item.key));
      return;
    } else if (result.reason === "storage_gone") {
      refresh();
      setPhase({ kind: "choose", error: "storage_gone" });
    } else if (result.reason === "unknown") {
      refresh();
      setPhase({ kind: "unknown" });
    } else {
      setPhase({ kind: "failed", reason: result.reason });
    }
    focusHeading();
  }

  function removeUnresolved(preview: MovePreview) {
    const drop = new Set(preview.unresolvedKeys);
    const remaining = selection.items.map((item) => item.key).filter((key) => !drop.has(key));
    onRemoveKeys(preview.unresolvedKeys);
    if (remaining.length === 0) setPhase({ kind: "failed", reason: "empty" });
    else void runPreview(remaining);
  }

  const title =
    phase.kind === "ready" || phase.kind === "saving"
      ? moveConfirmTitle(phase.preview.toMove, phase.preview.targetName)
      : phase.kind === "done"
        ? "Pronto"
        : "Mover exemplares";

  return (
    <DialogPrimitive.Root
      open
      onOpenChange={(open) => {
        if (!open && !busy) onClose();
      }}
    >
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={styles.overlay} />
        <DialogPrimitive.Content
          className={styles.drawer}
          aria-describedby={undefined}
          aria-busy={busy || undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
        >
          <div className={styles.drawerHeader}>
            <DialogPrimitive.Title className="text-sm font-medium text-foreground">Mover exemplares</DialogPrimitive.Title>
            <DialogPrimitive.Close
              aria-disabled={busy || undefined}
              onClick={(event) => busy && event.preventDefault()}
              className="aria-disabled:opacity-40 flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              aria-label="Fechar"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>
          <div className={styles.drawerBody}>
            <div className={`${organize.flow} flex flex-col`}>
              <div className={organize.head}>
                <h3 id={titleId} ref={headingRef} tabIndex={-1} className={local.panelTitle}>
                  {title}
                </h3>
                <p className={organize.subtitle}>
                  {pluralize(totals.cards, "carta selecionada", "cartas selecionadas")} — só os exemplares que atendem aos
                  filtros ativos da galeria. Coleção, variante, idioma e quantidade não mudam.
                </p>
              </div>

              {/* ---- destino ---- */}
              {phase.kind === "choose" || phase.kind === "loading" || phase.kind === "failed" ? (
                <div className="flex flex-col gap-2">
                  <label htmlFor={selectId} className={organize.destinationLabel}>
                    Destino
                  </label>
                  <Select
                    id={selectId}
                    value={choice}
                    className="h-11"
                    aria-disabled={busy || undefined}
                    onChange={(event) => {
                      if (busy) return;
                      setChoice(event.target.value);
                      setPhase({ kind: "choose" });
                    }}
                  >
                    <option value="" disabled>
                      Escolha o local…
                    </option>
                    {(locations ?? []).map((location) => (
                      <option key={location.id} value={location.id}>
                        {location.name}
                        {location.kindLabel ? ` · ${location.kindLabel}` : ""}
                      </option>
                    ))}
                    <option value={CLEAR}>Sem localização definida (remover local)</option>
                  </Select>
                  {locations === null ? (
                    <p className={organize.subtitle}>Não foi possível carregar seus locais agora. Você ainda pode remover a localização.</p>
                  ) : locations.length === 0 ? (
                    <p className={organize.subtitle}>
                      Você ainda não tem locais.{" "}
                      <Link href={LOCAIS_PATH} className="text-primary-ink underline underline-offset-2">
                        Criar em Meus locais
                      </Link>
                    </p>
                  ) : null}
                  <div className={review.reviewActions}>
                    <Button
                      className={`min-h-11 px-5 ${ARIA_DISABLED}`}
                      aria-disabled={target === undefined || busy || undefined}
                      onClick={() => void runPreview(selection.items.map((item) => item.key))}
                    >
                      {phase.kind === "loading" ? (
                        <Loader2 className="mr-1.5 h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" />
                      ) : null}
                      {phase.kind === "loading" ? "Conferindo exemplares…" : "Ver prévia"}
                    </Button>
                  </div>
                </div>
              ) : null}

              {/* ---- prévia e confirmação ---- */}
              {phase.kind === "ready" || phase.kind === "saving" ? (
                <PreviewBlock
                  preview={phase.preview}
                  changed={phase.kind === "ready" && phase.changed}
                  indicativeCopies={totals.copies}
                  names={names}
                  saving={phase.kind === "saving"}
                  onConfirm={() => void confirm(phase.preview)}
                  onBack={() => setPhase({ kind: "choose" })}
                  onRemoveUnresolved={() => removeUnresolved(phase.preview)}
                  onClose={onClose}
                />
              ) : null}

              {phase.kind === "unknown" ? (
                <div className={review.review}>
                  <InlineFeedback tone="warning">{moveFailureMessage("unknown")}</InlineFeedback>
                  <div className={review.reviewActions}>
                    <Button className="min-h-11 px-5" onClick={() => void runPreview(selection.items.map((item) => item.key))}>
                      <RotateCcw className="mr-1.5 h-4 w-4" aria-hidden="true" />
                      Refazer a prévia
                    </Button>
                  </div>
                </div>
              ) : null}

              {phase.kind === "done" ? (
                <div className={review.review}>
                  <InlineFeedback tone="success">{phase.text}</InlineFeedback>
                  <div className={review.reviewActions}>
                    <Button className="min-h-11 px-5" onClick={onClose}>
                      Fechar
                    </Button>
                  </div>
                </div>
              ) : null}

              <div aria-live="assertive">
                {phase.kind === "failed" ? <InlineFeedback tone="error">{moveFailureMessage(phase.reason)}</InlineFeedback> : null}
                {phase.kind === "choose" && phase.error ? (
                  <InlineFeedback tone="error">{moveFailureMessage(phase.error)}</InlineFeedback>
                ) : null}
              </div>
            </div>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function PreviewBlock({
  preview,
  changed,
  indicativeCopies,
  names,
  saving,
  onConfirm,
  onBack,
  onRemoveUnresolved,
  onClose,
}: {
  preview: MovePreview;
  changed: boolean;
  indicativeCopies: number;
  names: Map<string, string>;
  saving: boolean;
  onConfirm(): void;
  onBack(): void;
  onRemoveUnresolved(): void;
  onClose(): void;
}) {
  const unresolved = preview.unresolvedKeys;
  const blocked = unresolved.length > 0;
  const destination = preview.targetName === null ? "Sem localização definida" : `“${preview.targetName}”`;
  const cards = Object.entries(preview.perKey);

  if (preview.toMove === 0 && !blocked) {
    return (
      <div className={review.review}>
        <InlineFeedback tone="success">
          {preview.targetName === null
            ? "Todos esses exemplares já estão sem localização definida. Nada a mover."
            : `Todos esses exemplares já estão em ${destination}. Nada a mover.`}
        </InlineFeedback>
        <div className={review.reviewActions}>
          <Button className="min-h-11 px-5" onClick={onClose}>
            Fechar
          </Button>
          <Button variant="outline" className="min-h-11" onClick={onBack}>
            Escolher outro destino
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {changed ? (
        <InlineFeedback tone="warning">Seu acervo mudou desde a prévia anterior. Confira os números atualizados — nada foi gravado.</InlineFeedback>
      ) : null}

      <dl className={organize.summary}>
        <div className={organize.summaryRow}>
          <dt>Destino</dt>
          <dd>{destination}</dd>
        </div>
        <div className={organize.summaryRow}>
          <dt>Vão mudar</dt>
          <dd>
            <span className={organize.summaryStrong}>{pluralize(preview.toMove, "exemplar", "exemplares")}</span>
            {preview.fromOther > 0 ? (
              <span className={`${organize.leavingLine} block`}>
                {pluralize(preview.fromOther, "sai de outro local", "saem de outros locais")}
              </span>
            ) : null}
            {preview.fromNone > 0 ? (
              <span className="block text-muted-foreground">{pluralize(preview.fromNone, "estava sem local", "estavam sem local")}</span>
            ) : null}
          </dd>
        </div>
        {preview.atTarget > 0 ? (
          <div className={organize.summaryRow}>
            <dt>Já no destino</dt>
            <dd>{pluralize(preview.atTarget, "exemplar fica como está", "exemplares ficam como estão")}</dd>
          </div>
        ) : null}
        <div className={organize.summaryRow}>
          <dt>Cartas</dt>
          <dd>{pluralize(cards.length, "carta", "cartas")}</dd>
        </div>
      </dl>

      {preview.total !== indicativeCopies && !blocked ? (
        <p className={organize.subtitle}>
          A galeria indicava {pluralize(indicativeCopies, "exemplar", "exemplares")}; a conferência agora encontrou{" "}
          {formatCount(preview.total)}. Vale o número conferido.
        </p>
      ) : null}

      {blocked ? (
        <div className={local.unresolved} role="group" aria-label="Cartas sem exemplares neste recorte">
          <InlineFeedback tone="warning">
            {pluralize(unresolved.length, "carta selecionada não tem", "cartas selecionadas não têm")} mais exemplares que atendam
            aos filtros. Elas não entram na mudança — revise antes de confirmar.
          </InlineFeedback>
          <ul className={local.unresolvedList}>
            {unresolved.slice(0, 20).map((key) => (
              <li key={key}>{names.get(key) ?? "Carta"}</li>
            ))}
            {unresolved.length > 20 ? <li>e mais {formatCount(unresolved.length - 20)}</li> : null}
          </ul>
          <div className={review.reviewActions}>
            <Button className="min-h-11 px-5" onClick={onRemoveUnresolved}>
              Tirar da seleção e refazer a prévia
            </Button>
          </div>
        </div>
      ) : null}

      {cards.length > 0 ? (
        <details className={local.cards}>
          <summary>Ver as cartas ({formatCount(cards.length)})</summary>
          <ul>
            {cards.map(([key, count]) => (
              <li key={key}>
                <span>{names.get(key) ?? "Carta"}</span>
                <span className={local.cardsCount}>×{formatCount(count)}</span>
              </li>
            ))}
          </ul>
        </details>
      ) : null}

      {!blocked ? (
        <div className={review.reviewActions}>
          <Button
            className={`min-h-11 px-5 ${ARIA_DISABLED}`}
            variant={preview.targetName === null ? "outline" : "default"}
            aria-disabled={saving || undefined}
            onClick={() => !saving && onConfirm()}
          >
            {saving ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
            {saving ? "Movendo…" : moveConfirmAction(preview.toMove, preview.targetName)}
          </Button>
          <Button variant="outline" className={`min-h-11 ${ARIA_DISABLED}`} aria-disabled={saving || undefined} onClick={() => !saving && onBack()}>
            Voltar
          </Button>
        </div>
      ) : null}
    </div>
  );
}
