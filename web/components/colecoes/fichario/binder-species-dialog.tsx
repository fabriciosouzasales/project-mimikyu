"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Loader2, PawPrint, Trash2, X } from "lucide-react";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type SpeciesReferencePreview,
  type SpeciesReferenceState,
  formatNationalNumber,
  speciesFailureMessage,
} from "@/lib/colecoes/binder-species";
import { applySpeciesReferences, clearSpeciesReferences, previewSpeciesReferences, setSpeciesReferenceVisibility } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import styles from "./binder-add-pages.module.css";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])';

type Preview = { status: "idle" | "loading" } | { status: "ready"; preview: SpeciesReferencePreview } | { status: "error"; message: string };

/**
 * "Pokémon nos bolsos" (POKEDEX-BINDER-SPECIES-REFERENCE, D2): ações das
 * referências de espécie no próprio Fichário Digital — o Centro de Controle
 * não muda.
 *
 *  - Sem referências e coleção Pokédex dona do fichário: prévia (5258, não
 *    grava) com a quantidade de Pokémon, bolsos livres e o intervalo de
 *    páginas; confirmação explícita aplica tudo de uma vez.
 *  - Com referências: interruptor "Exibir nos bolsos vazios" (ajuste A —
 *    só preferência, nunca apaga) e, para a dona, "Remover as referências"
 *    com confirmação e contagem exata.
 *  - Convidada: só o interruptor (a dona define as referências).
 *
 * Mesma linguagem e teclado do diálogo "Adicionar páginas": Tab preso, Esc
 * fecha, setas não viram a página por baixo.
 */
export function SpeciesReferenceDialog({
  host,
  collectionId,
  state,
  onStateChange,
  onClose,
}: {
  host: HTMLElement | null;
  collectionId: string;
  state: SpeciesReferenceState;
  /** `reload`: as referências mudaram — o fichário relê as páginas. */
  onStateChange: (next: SpeciesReferenceState, options: { reload: boolean; message?: string }) => void;
  onClose: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const switchId = useId();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [preview, setPreview] = useState<Preview>({ status: "idle" });
  const applied = state.referenceCount > 0;

  const loadPreview = useCallback(async () => {
    setPreview({ status: "loading" });
    const result = await previewSpeciesReferences({ collectionId });
    setPreview(result.ok ? { status: "ready", preview: result.preview } : { status: "error", message: speciesFailureMessage(result.reason) });
  }, [collectionId]);

  useEffect(() => {
    if (!applied && state.canManage) void loadPreview();
  }, [applied, loadPreview, state.canManage]);

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

  const apply = async () => {
    if (preview.status !== "ready" || busy) return;
    setBusy(true);
    setError(null);
    const result = await applySpeciesReferences({ collectionId, planToken: preview.preview.planToken });
    setBusy(false);
    if (!result.ok) {
      setError(speciesFailureMessage(result.reason));
      // O plano mudou (página adicionada, removida ou reordenada): prévia nova antes de tentar de novo.
      if (result.reason === "plan_changed") void loadPreview();
      return;
    }
    const n = result.state.referenceCount;
    onStateChange(result.state, {
      reload: true,
      message: result.alreadyApplied ? "Os Pokémon já estavam nos bolsos." : `${formatCount(n)} Pokémon apareceram nos bolsos vazios.`,
    });
    onClose();
  };

  const toggleVisible = async (visible: boolean) => {
    if (busy) return;
    setBusy(true);
    setError(null);
    // Retorno imediato na tela; volta atrás se o banco recusar.
    onStateChange({ ...state, visible }, { reload: false });
    const result = await setSpeciesReferenceVisibility({ collectionId, visible });
    setBusy(false);
    if (!result.ok) {
      onStateChange({ ...state, visible: !visible }, { reload: false });
      setError(speciesFailureMessage(result.reason));
      return;
    }
    if (result.visible !== visible) onStateChange({ ...state, visible: result.visible }, { reload: false });
  };

  const remove = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    const result = await clearSpeciesReferences({ collectionId, expectedCount: state.referenceCount });
    setBusy(false);
    if (!result.ok) {
      setError(speciesFailureMessage(result.reason));
      return;
    }
    setConfirmRemove(false);
    onStateChange(result.state, { reload: true, message: "As referências foram removidas. Cartas e páginas não mudaram." });
  };

  if (!host) return null;
  const ready = preview.status === "ready" ? preview.preview : null;

  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
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
              A arte de cada espécie aparece, discreta, nos bolsos vazios — na ordem da Pokédex Nacional. É só uma referência visual: não é carta, reserva nem progresso.
            </p>
          </div>
          <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar" disabled={busy} data-autofocus>
            <X aria-hidden />
          </button>
        </div>

        {applied ? (
          <>
            <div className="flex items-center justify-between gap-4 rounded-xl px-3 py-3" style={{ background: "hsl(0 0% 100% / 0.04)" }}>
              <div className="min-w-0">
                <Label htmlFor={switchId} className="text-[13px] text-white/90">
                  Exibir nos bolsos vazios
                </Label>
                <p className="mt-0.5 text-[11.5px] leading-snug text-white/50">
                  {formatCount(state.referenceCount)} {state.referenceCount === 1 ? "Pokémon associado" : "Pokémon associados"} aos bolsos. Ocultar não apaga a associação.
                </p>
              </div>
              <Switch id={switchId} checked={state.visible} onCheckedChange={(value) => void toggleVisible(value)} disabled={busy} />
            </div>

            {state.canManage ? (
              confirmRemove ? (
                <div className="rounded-xl px-3 py-3" style={{ background: "hsl(0 72% 50% / 0.08)", boxShadow: "inset 0 0 0 1px hsl(0 72% 60% / 0.25)" }}>
                  <p className="text-[12.5px] leading-snug text-white/85">
                    Remover as {formatCount(state.referenceCount)} referências deste fichário? Cartas, reservas, imagens e páginas não mudam. Para só esconder, use o interruptor acima.
                  </p>
                  <div className={`${styles.actions} mt-3`}>
                    <button type="button" className={styles.secondary} onClick={() => setConfirmRemove(false)} disabled={busy}>
                      Cancelar
                    </button>
                    <button type="button" className={styles.secondary} onClick={() => void remove()} disabled={busy} style={{ color: "hsl(0 85% 75%)" }}>
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
              )
            ) : null}
          </>
        ) : !state.canManage ? (
          <p className={styles.note}>
            {state.isPokedexOwner
              ? "Os Pokémon dos bolsos são definidos pela coleção Pokédex dona do fichário."
              : "Os Pokémon nos bolsos existem só nos fichários de coleções Pokédex."}
          </p>
        ) : preview.status === "error" ? (
          <div className={styles.actions}>
            <button type="button" className={styles.secondary} onClick={() => void loadPreview()}>
              Tentar de novo
            </button>
          </div>
        ) : !ready ? (
          <p className={styles.note} role="status">
            <Loader2 className="mr-1.5 inline h-3.5 w-3.5 animate-spin align-[-2px]" aria-hidden />
            Preparando a prévia…
          </p>
        ) : (
          <>
            <dl className={styles.facts}>
              <div>
                <dt>Pokémon</dt>
                <dd>
                  <strong>{formatCount(ready.pairCount)}</strong>
                  {ready.firstNumber !== null && ready.lastNumber !== null ? ` · ${formatNationalNumber(ready.firstNumber)}–${formatNationalNumber(ready.lastNumber)}` : ""}
                </dd>
              </div>
              <div>
                <dt>Bolsos sem referência</dt>
                <dd>
                  <strong>{formatCount(ready.slotsLeftFree)}</strong>
                </dd>
              </div>
            </dl>
            <p className={styles.note}>
              {ready.firstPage !== null && ready.lastPage !== null
                ? `Do primeiro bolso da página ${ready.firstPage} até a página ${ready.lastPage}, na ordem das páginas. `
                : ""}
              Nenhuma página é criada e nenhuma carta, reserva ou imagem muda.
              {ready.positionsUnplaced > 0
                ? ` ${formatCount(ready.positionsUnplaced)} Pokémon ficam sem bolso: o fichário tem menos bolsos que a sua Pokédex.`
                : ""}
              {ready.slotsWithContent > 0
                ? ` ${formatCount(ready.slotsWithContent)} bolsos já ocupados mostram a referência quando ficarem vazios.`
                : ""}
            </p>
            <div className={styles.actions}>
              <button type="button" className={styles.secondary} onClick={onClose} disabled={busy}>
                Cancelar
              </button>
              <button type="button" className={styles.primary} onClick={() => void apply()} disabled={busy || ready.pairCount === 0}>
                {busy ? <Loader2 className="animate-spin" aria-hidden /> : <PawPrint aria-hidden />}
                {busy ? "Posicionando…" : "Mostrar nos bolsos"}
              </button>
            </div>
          </>
        )}

        {preview.status === "error" && !applied && state.canManage ? (
          <p className={styles.note} role="alert">
            {preview.message}
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
