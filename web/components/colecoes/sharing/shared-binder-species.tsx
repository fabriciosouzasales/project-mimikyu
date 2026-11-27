"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Eye, EyeOff, Loader2, PawPrint, Trash2, X } from "lucide-react";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  editorApplySpeciesReferences,
  editorClearSpeciesReferences,
  editorPreviewSpeciesReferences,
  editorSetSpeciesReferenceVisibility,
} from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { SharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import { formatCount } from "@/lib/colecoes/acervo";
import { formatNationalNumber } from "@/lib/colecoes/binder-species";
import {
  type EditorSpeciesFail,
  type EditorSpeciesPreview,
  applyMessage,
  clearMessage,
  editorSpeciesFail,
  editorSpeciesStage,
  speciesWriteUncertain,
  visibilityMessage,
} from "@/lib/colecoes/editor-binder-species";
import styles from "@/components/colecoes/fichario/binder-add-pages.module.css";

const FOCUSABLE = 'button:not([disabled]), [tabindex]:not([tabindex="-1"])';

type Fail = { ok: false } & EditorSpeciesFail;
type View = { status: "loading" } | { status: "ready"; preview: EditorSpeciesPreview } | { status: "error"; message: string };

/**
 * V1-13 · E3-6 / F2 — "Pokémon nos bolsos" pelo EDITOR (5383), só Pokédex.
 *
 * Sob demanda: nada é lido ao abrir o fichário. O botão abre o diálogo e lê a
 * prévia; a partir dela, uma ação explícita por vez (associar, mostrar,
 * ocultar, remover). Nada otimista: a tela só muda com a resposta do
 * servidor; resultado incerto → nova prévia, nunca repetição. Recusa que
 * tira a permissão desliga a edição nesta tela (mesma regra da E2).
 */
export function useEditorSpecies({
  editor,
  collectionId,
  available,
  visibility = null,
  afterWrite = async () => {},
}: {
  editor: SharedBinderEditor;
  collectionId: string;
  available: boolean;
  /** E3-6 / F2: estado real da exibição lido pela 5393; `null` = desconhecido (5316/barreira). */
  visibility?: boolean | null;
  /** Releitura da tela depois de uma escrita confirmada ou de resultado incerto. */
  afterWrite?: () => Promise<void>;
}) {
  const [open, setOpen] = useState(false);
  const editorRef = useRef(editor);
  editorRef.current = editor;

  const absorb = useCallback((fail: Fail) => {
    if (!fail.disables) return;
    setOpen(false);
    editorRef.current.loseAccess(fail.recheck);
    editorRef.current.notify({ tone: "error", text: fail.message });
  }, []);

  return {
    available,
    open,
    show: () => {
      if (!available) return;
      if (editorRef.current.structuralBlocker) {
        editorRef.current.notify({ tone: "info", text: editorRef.current.structuralBlocker });
        return;
      }
      setOpen(true);
    },
    close: () => setOpen(false),
    absorb,
    collectionId,
    editorRef,
    visibility,
    afterWrite,
  };
}

export type EditorSpecies = ReturnType<typeof useEditorSpecies>;

export function EditorSpeciesDialog({ host, species }: { host: HTMLElement | null; species: EditorSpecies }) {
  const { collectionId, absorb, close, editorRef, visibility, afterWrite } = species;
  const switchId = useId();
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [view, setView] = useState<View>({ status: "loading" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [confirmRemove, setConfirmRemove] = useState(false);

  const load = useCallback(async () => {
    setView({ status: "loading" });
    setConfirmRemove(false);
    const r = await editorPreviewSpeciesReferences({ collectionId }).catch((): Fail => ({ ok: false, ...editorSpeciesFail("unknown") }));
    if (!r.ok) {
      absorb(r);
      setView({ status: "error", message: r.message });
      return;
    }
    setView({ status: "ready", preview: r.preview });
  }, [absorb, collectionId]);

  useEffect(() => {
    void load();
  }, [load]);

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
      if (!busy) close();
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

  /** Uma escrita por confirmação, sob a trava estrutural da tela (não concorre com páginas/espaços/organização). */
  const run = async <T,>(write: () => Promise<{ ok: true; result: T } | Fail>, message: (result: T) => string) => {
    if (busy) return;
    const editorNow = editorRef.current;
    if (!editorNow.beginStructural()) {
      setError(editorNow.structuralBlocker ?? "Aguarde a alteração em andamento terminar.");
      return;
    }
    setBusy(true);
    setError(null);
    setDone(null);
    try {
      const r = await write().catch((): Fail => ({ ok: false, ...editorSpeciesFail("unknown") }));
      if (!r.ok) {
        absorb(r);
        if (r.disables) return;
        setError(r.message);
        // Plano/contagem mudou ou resultado incerto: nova prévia e releitura da tela (nunca repetir a escrita).
        if (r.reloadPreview || speciesWriteUncertain(r.reason)) void load();
        if (speciesWriteUncertain(r.reason)) void afterWrite();
        return;
      }
      setDone(message(r.result));
      void load();
      // Confirmada: as páginas são relidas (a arte e o estado da exibição vêm da 5393).
      void afterWrite();
    } finally {
      setBusy(false);
      editorNow.endStructural();
    }
  };

  if (!host) return null;
  const preview = view.status === "ready" ? view.preview : null;
  const stage = preview ? editorSpeciesStage(preview) : null;

  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && close()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby={titleId} className={styles.dialog} aria-busy={busy || undefined}>
        <div className={styles.head}>
          <span className={styles.icon} aria-hidden>
            <PawPrint />
          </span>
          <div>
            <h2 id={titleId} className={styles.title}>
              Pokémon nos bolsos
            </h2>
            <p className={styles.lead}>
              A arte de cada espécie fica associada aos bolsos vazios, na ordem da Pokédex Nacional. É só uma referência visual: não é carta, reserva nem progresso, e
              nenhuma carta muda de lugar.
            </p>
          </div>
          <button type="button" className={styles.close} onClick={close} aria-label="Fechar" disabled={busy} data-autofocus>
            <X aria-hidden />
          </button>
        </div>

        {view.status === "loading" ? (
          <p className={styles.note} role="status">
            <Loader2 className="mr-1.5 inline h-3.5 w-3.5 animate-spin align-[-2px] motion-reduce:animate-none" aria-hidden />
            Preparando a prévia…
          </p>
        ) : view.status === "error" ? (
          <>
            <p className={styles.note} role="alert">
              {view.message}
            </p>
            <div className={styles.actions}>
              <button type="button" className={styles.secondary} onClick={() => void load()}>
                Tentar de novo
              </button>
            </div>
          </>
        ) : preview && (stage === "apply" || stage === "nothing") ? (
          <>
            <dl className={styles.facts}>
              <div>
                <dt>Pokémon</dt>
                <dd>
                  <strong>{formatCount(preview.pairCount)}</strong>
                  {preview.firstNumber !== null && preview.lastNumber !== null ? ` · ${formatNationalNumber(preview.firstNumber)}–${formatNationalNumber(preview.lastNumber)}` : ""}
                </dd>
              </div>
              <div>
                <dt>Bolsos sem referência</dt>
                <dd>
                  <strong>{formatCount(preview.slotsLeftFree)}</strong>
                </dd>
              </div>
            </dl>
            <p className={styles.note}>
              {preview.firstPage !== null && preview.lastPage !== null ? `Do primeiro bolso da página ${preview.firstPage} até a página ${preview.lastPage}, na ordem das páginas. ` : ""}
              Nenhuma página é criada e nenhuma carta, reserva ou imagem muda.
              {preview.positionsUnplaced > 0 ? ` ${formatCount(preview.positionsUnplaced)} Pokémon ficam sem bolso: o fichário tem menos bolsos que a Pokédex.` : ""}
            </p>
            <div className={styles.actions}>
              <button type="button" className={styles.secondary} onClick={close} disabled={busy}>
                Cancelar
              </button>
              <button
                type="button"
                className={styles.primary}
                onClick={() => void run(() => editorApplySpeciesReferences({ collectionId, planToken: preview.planToken }), applyMessage)}
                disabled={busy || stage === "nothing"}
              >
                {busy ? <Loader2 className="animate-spin" aria-hidden /> : <PawPrint aria-hidden />}
                {busy ? "Associando…" : "Associar aos bolsos"}
              </button>
            </div>
          </>
        ) : preview ? (
          <>
            <p className={styles.note}>
              {formatCount(preview.existingCount)} {preview.existingCount === 1 ? "Pokémon associado" : "Pokémon associados"} aos bolsos deste fichário.
              {stage === "outdated" ? " As páginas mudaram desde a associação: para refazê-la na ordem atual, remova e associe de novo." : ""}
            </p>
            {visibility !== null ? (
              // Estado real (5393): um único interruptor; muda só depois da confirmação do servidor e da releitura.
              <div className="flex items-center justify-between gap-4 rounded-xl px-3 py-3" style={{ background: "hsl(0 0% 100% / 0.04)" }}>
                <div className="min-w-0">
                  <Label htmlFor={switchId} className="text-[13px] text-white/90">
                    Exibir nos bolsos vazios
                  </Label>
                  <p className="mt-0.5 text-[11.5px] leading-snug text-white/50">Ocultar não apaga a associação.</p>
                </div>
                <Switch
                  id={switchId}
                  checked={visibility}
                  onCheckedChange={(next) => void run(() => editorSetSpeciesReferenceVisibility({ collectionId, visible: next }), visibilityMessage)}
                  disabled={busy}
                />
              </div>
            ) : (
              <div className={styles.actions}>
                <button type="button" className={styles.secondary} onClick={() => void run(() => editorSetSpeciesReferenceVisibility({ collectionId, visible: true }), visibilityMessage)} disabled={busy}>
                  <Eye className="h-4 w-4" aria-hidden />
                  Mostrar nos bolsos vazios
                </button>
                <button type="button" className={styles.secondary} onClick={() => void run(() => editorSetSpeciesReferenceVisibility({ collectionId, visible: false }), visibilityMessage)} disabled={busy}>
                  <EyeOff className="h-4 w-4" aria-hidden />
                  Ocultar
                </button>
              </div>
            )}
            {confirmRemove ? (
              <div className="rounded-xl px-3 py-3" style={{ background: "hsl(0 72% 50% / 0.08)", boxShadow: "inset 0 0 0 1px hsl(0 72% 60% / 0.25)" }}>
                <p className="text-[12.5px] leading-snug text-white/85">
                  Remover as {formatCount(preview.existingCount)} referências deste fichário? Cartas, reservas, imagens e páginas não mudam. Para só esconder, use “Ocultar”.
                </p>
                <div className={`${styles.actions} mt-3`}>
                  <button type="button" className={styles.secondary} onClick={() => setConfirmRemove(false)} disabled={busy}>
                    Cancelar
                  </button>
                  <button
                    type="button"
                    className={styles.secondary}
                    onClick={() => void run(() => editorClearSpeciesReferences({ collectionId, expectedCount: preview.existingCount }), clearMessage)}
                    disabled={busy}
                    style={{ color: "hsl(0 85% 75%)" }}
                  >
                    {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <Trash2 className="h-4 w-4" aria-hidden />}
                    {busy ? "Removendo…" : "Remover referências"}
                  </button>
                </div>
              </div>
            ) : (
              <div className={styles.actions}>
                <button type="button" className={styles.secondary} onClick={() => setConfirmRemove(true)} disabled={busy}>
                  <Trash2 className="h-4 w-4" aria-hidden />
                  Remover as referências
                </button>
              </div>
            )}
          </>
        ) : null}

        {visibility === null ? (
          <p className={styles.note}>A arte de referência não está disponível nesta visualização agora. A contagem acima mostra o que está associado.</p>
        ) : null}
        {done ? (
          <p className={styles.note} role="status">
            {done}
          </p>
        ) : null}
        {error ? (
          <p className={styles.note} role="alert" style={{ color: "hsl(0 85% 78%)" }}>
            {error}
          </p>
        ) : null}
      </div>
    </div>,
    host,
  );
}
