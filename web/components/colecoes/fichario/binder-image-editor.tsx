"use client";

import { useCallback, useEffect, useId, useRef, useState, type RefObject } from "react";
import { createPortal } from "react-dom";
import { ChevronDown, ChevronUp, Crop, Image as ImageIcon, ImageOff, ImagePlus, Loader2, RefreshCw, Trash2, X } from "lucide-react";
import { readSlotImageSummary } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import type { BinderSlot, SlotImage } from "@/lib/colecoes/binder";
import {
  FOCAL_DEFAULT,
  SLOT_IMAGE_LIMIT,
  type SlotImageSummary,
  SOURCE_ACCEPT,
  canFrameVertically,
  clampFocal,
  focalForKey,
  focalFromDrag,
  focalLabel,
  imagesLeft,
  verticalOverflow,
} from "@/lib/colecoes/binder-images";
import { type PreparedImage, cleanupUnlinkedSlotImagesOnce, prepareSlotImage } from "./binder-image-io";
import dialog from "./binder-add-pages.module.css";
import css from "./binder-image.module.css";

const FOCUSABLE = 'button:not([disabled]), input:not([disabled]):not([tabindex="-1"]), [tabindex]:not([tabindex="-1"])';

/** Resultado de uma gravação pedida pela área de trabalho: `null` = sucesso; texto = erro já em linguagem do colecionador. */
export type SubmitResult = Promise<string | null>;

// ---------------------------------------------------------------------------
// Teclado dos diálogos sobre o fichário
// ---------------------------------------------------------------------------

/**
 * Esc fecha, Tab fica preso e as setas não viram a página do fichário por
 * baixo — exceto dentro de um controle que trata as próprias teclas
 * (`data-own-keys`, o enquadramento). Mesmo comportamento do seletor de bolso.
 */
export function useDialogKeys(ref: RefObject<HTMLDivElement | null>, onClose: () => void, closable = true) {
  const handler = useRef<(event: KeyboardEvent) => void>(() => {});
  handler.current = (event: KeyboardEvent) => {
    const node = ref.current;
    if (!node) return;
    const target = event.target as HTMLElement | null;
    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      if (closable) onClose();
      return;
    }
    if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) {
      if (target && node.contains(target) && target.closest("[data-own-keys]")) return;
      event.stopPropagation();
      return;
    }
    if (event.key !== "Tab") return;
    event.stopPropagation();
    // O seletor de arquivo é visualmente oculto, mas precisa fazer parte do ciclo de Tab.
    const nodes = [...node.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => el.offsetParent !== null);
    const first = nodes[0];
    const last = nodes[nodes.length - 1];
    if (!first || !last) return;
    if (event.shiftKey && (document.activeElement === first || document.activeElement === node)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    } else if (!node.contains(document.activeElement)) {
      event.preventDefault();
      first.focus();
    }
  };
  useEffect(() => {
    const listener = (event: KeyboardEvent) => handler.current(event);
    window.addEventListener("keydown", listener, true);
    return () => window.removeEventListener("keydown", listener, true);
  }, []);
  // Foco no diálogo; volta ao bolso ao fechar.
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    ref.current?.focus({ preventScroll: true });
    return () => {
      if (opener?.isConnected) opener.focus();
    };
  }, [ref]);
}

// ---------------------------------------------------------------------------
// Prévia no formato real do bolso, com enquadramento vertical
// ---------------------------------------------------------------------------

/**
 * O bolso do fichário em tamanho de prévia: 8:11, abertura e reflexo do
 * plástico, a imagem cobrindo como no fichário (`object-position` 50% foco%).
 * Com `onFocal`, vira o controle de enquadramento: arrastar na vertical ou
 * ↑ ↓ / PageUp PageDown / Home End (`role="slider"`).
 */
export function PocketPreview({
  src,
  width,
  focalY,
  natural,
  onFocal,
  onNatural,
  label = "Imagem do bolso",
}: {
  src: string | null;
  width: number;
  focalY: number;
  /** Dimensões reais da imagem (para saber se há o que enquadrar e quanto o arrasto move). */
  natural: { width: number; height: number } | null;
  onFocal?: (value: number) => void;
  onNatural?: (size: { width: number; height: number }) => void;
  label?: string;
}) {
  const boxRef = useRef<HTMLDivElement>(null);
  const drag = useRef<{ startY: number; startFocal: number; overflow: number; id: number } | null>(null);
  const [dragging, setDragging] = useState(false);
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [src]);
  const frameable = Boolean(onFocal && natural && canFrameVertically(natural.width, natural.height));

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!frameable || !natural || !boxRef.current) return;
    const rect = boxRef.current.getBoundingClientRect();
    drag.current = { startY: event.clientY, startFocal: focalY, overflow: verticalOverflow(natural.width, natural.height, rect.width, rect.height), id: event.pointerId };
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(true);
  };
  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const d = drag.current;
    if (!d || d.id !== event.pointerId || !onFocal) return;
    onFocal(focalFromDrag(d.startFocal, event.clientY - d.startY, d.overflow));
  };
  const endDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    if (drag.current?.id !== event.pointerId) return;
    drag.current = null;
    setDragging(false);
  };

  return (
    <div ref={boxRef} className={css.pocket} style={{ width }} data-dragging={dragging || undefined}>
      {src && !failed ? (
        // eslint-disable-next-line @next/next/no-img-element -- URL assinada (privada, 1 h) ou prévia local blob:
        <img
          src={src}
          alt=""
          draggable={false}
          decoding="async"
          style={{ objectPosition: `50% ${clampFocal(focalY)}%` }}
          onLoad={(event) => onNatural?.({ width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })}
          onError={() => setFailed(true)}
        />
      ) : (
        <span className={css.unavailable}>
          <ImageOff aria-hidden />
          Imagem indisponível agora
        </span>
      )}
      <span className={css.pocketLip} aria-hidden />
      <span className={css.pocketSheen} aria-hidden />
      <span className={css.pocketEdge} aria-hidden />
      {frameable && onFocal ? (
        <>
          <div
            className={css.frame}
            role="slider"
            tabIndex={0}
            data-own-keys
            aria-label={`${label}: enquadramento vertical`}
            aria-orientation="vertical"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={clampFocal(focalY)}
            aria-valuetext={focalLabel(focalY)}
            onKeyDown={(event) => {
              const next = focalForKey(event.key, focalY);
              if (next === null) return;
              event.preventDefault();
              onFocal(next);
            }}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={endDrag}
            onPointerCancel={endDrag}
          />
          <span className={css.frameCue} data-pos="top" aria-hidden>
            <ChevronUp />
          </span>
          <span className={css.frameCue} data-pos="bottom" aria-hidden>
            <ChevronDown />
          </span>
        </>
      ) : null}
    </div>
  );
}

function FocalReadout({ value }: { value: number }) {
  return (
    <div className={css.focal} aria-hidden>
      <span>Topo</span>
      <span className={css.focalBar}>
        <span style={{ left: `${clampFocal(value)}%` }} />
      </span>
      <span>Base</span>
    </div>
  );
}

function kb(bytes: number): string {
  return `${Math.max(1, Math.round(bytes / 1024)).toLocaleString("pt-BR")} KB`;
}

// ---------------------------------------------------------------------------
// Escolher, preparar, enquadrar e confirmar (colocar ou substituir)
// ---------------------------------------------------------------------------

type SummaryState = { status: "loading" } | { status: "ready"; summary: SlotImageSummary } | { status: "error" };

/**
 * Do arquivo ao bolso: escolher (ou soltar) → preparar no navegador →
 * prévia no formato do bolso → enquadrar → confirmar. Nada é enviado antes
 * da confirmação. `onSubmit` faz o envio e o vínculo (área de trabalho) e
 * devolve `null` no sucesso ou a mensagem do erro.
 */
export function ImageComposer({
  collectionId,
  replacing = false,
  pocketWidth = 168,
  onSubmit,
  onCancel,
}: {
  collectionId: string;
  replacing?: boolean;
  pocketWidth?: number;
  onSubmit: (image: PreparedImage, focalY: number, onStage: (stage: "upload" | "link") => void) => SubmitResult;
  onCancel?: () => void;
}) {
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [summary, setSummary] = useState<SummaryState>({ status: "loading" });
  const [image, setImage] = useState<PreparedImage | null>(null);
  const [focal, setFocal] = useState(FOCAL_DEFAULT);
  const [preparing, setPreparing] = useState(false);
  const [stage, setStage] = useState<"upload" | "link" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [over, setOver] = useState(false);
  // A prévia passa a ser do fichário depois do sucesso (não revogar).
  const handedOff = useRef(false);
  const imageRef = useRef<PreparedImage | null>(null);
  imageRef.current = image;

  useEffect(() => {
    // Limpeza oportunista de envios abandonados (> 1 h, sem vínculo).
    cleanupUnlinkedSlotImagesOnce();
    let alive = true;
    readSlotImageSummary({ collectionId })
      .then((result) => alive && setSummary(result.ok ? { status: "ready", summary: result.summary } : { status: "error" }))
      .catch(() => alive && setSummary({ status: "error" }));
    return () => {
      alive = false;
    };
  }, [collectionId]);

  useEffect(
    () => () => {
      const current = imageRef.current;
      if (current && !handedOff.current) URL.revokeObjectURL(current.url);
    },
    [],
  );

  const pick = useCallback(async (file: File | null | undefined) => {
    if (!file) return;
    setError(null);
    setPreparing(true);
    const prepared = await prepareSlotImage(file);
    setPreparing(false);
    if (!prepared.ok) {
      setError(prepared.message);
      return;
    }
    setImage((previous) => {
      if (previous) URL.revokeObjectURL(previous.url);
      return prepared.image;
    });
    setFocal(FOCAL_DEFAULT);
  }, []);

  const left = summary.status === "ready" ? imagesLeft(summary.summary) : null;
  // Substituir não aumenta a contagem; colocar exige uma vaga.
  const blocked = !replacing && left === 0;
  const busy = stage !== null;

  const confirm = async () => {
    if (!image || busy || blocked) return;
    setError(null);
    setStage("upload");
    const message = await onSubmit(image, focal, setStage);
    if (message === null) {
      handedOff.current = true;
      return;
    }
    setStage(null);
    setError(message);
  };

  const used = summary.status === "ready" ? summary.summary.userCount : null;
  const near = used !== null && used >= SLOT_IMAGE_LIMIT - 25;

  return (
    <div className="flex flex-col gap-4">
      {!image ? (
        <label
          htmlFor={inputId}
          className={css.drop}
          data-over={over || undefined}
          onDragOver={(event) => {
            event.preventDefault();
            setOver(true);
          }}
          onDragLeave={() => setOver(false)}
          onDrop={(event) => {
            event.preventDefault();
            setOver(false);
            void pick(event.dataTransfer.files?.[0]);
          }}
        >
          <input
            ref={inputRef}
            id={inputId}
            type="file"
            accept={SOURCE_ACCEPT}
            className={css.fileInput}
            disabled={preparing || blocked}
            onChange={(event) => {
              void pick(event.currentTarget.files?.[0]);
              event.currentTarget.value = "";
            }}
          />
          <span className={css.dropPocket} aria-hidden>
            {preparing ? <Loader2 className={css.spin} /> : <ImagePlus />}
          </span>
          <span>
            <span className={css.dropTitle}>{preparing ? "Preparando a imagem…" : replacing ? "Escolher a nova imagem" : "Escolher uma imagem"}</span>
            <span className={`${css.dropHint} block`}>
              JPEG, PNG ou WebP, do seu dispositivo (ou arraste até aqui). Ajustamos o tamanho para o bolso e removemos dados de localização da foto.
            </span>
          </span>
        </label>
      ) : (
        <div className={css.stageRow}>
          <PocketPreview src={image.url} width={pocketWidth} focalY={focal} natural={{ width: image.width, height: image.height }} onFocal={busy ? undefined : setFocal} />
          <div className={css.meta}>
            <div>
              <p className={css.metaTitle}>Enquadramento</p>
              <p className={css.metaLine}>
                {canFrameVertically(image.width, image.height)
                  ? "Arraste a imagem para cima ou para baixo, ou use ↑ ↓ com o bolso em foco."
                  : "A imagem já cabe inteira na altura do bolso — não há o que ajustar."}
              </p>
            </div>
            {canFrameVertically(image.width, image.height) ? <FocalReadout value={focal} /> : null}
            <p className={css.metaLine}>
              {image.mime === "image/webp" ? "WebP" : "JPEG"} · {image.width}×{image.height} · {kb(image.bytes)}
            </p>
            <button type="button" className={css.linkButton} onClick={() => inputRef.current?.click()} disabled={busy}>
              <RefreshCw aria-hidden />
              Trocar arquivo
            </button>
            <input
              ref={inputRef}
              type="file"
              accept={SOURCE_ACCEPT}
              className={css.fileInput}
              tabIndex={-1}
              aria-hidden
              onChange={(event) => {
                void pick(event.currentTarget.files?.[0]);
                event.currentTarget.value = "";
              }}
            />
          </div>
        </div>
      )}

      {blocked ? (
        <p className={css.notice} role="status">
          Você chegou ao limite de {SLOT_IMAGE_LIMIT} imagens. Remova a imagem de algum bolso para colocar outra.
        </p>
      ) : null}
      {error ? (
        <p className={css.alert} role="alert">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className={css.quota} data-near={near || undefined}>
          {summary.status === "ready"
            ? `${summary.summary.userCount.toLocaleString("pt-BR")} de ${summary.summary.limit.toLocaleString("pt-BR")} imagens usadas`
            : summary.status === "loading"
              ? "Conferindo suas imagens…"
              : ""}
        </span>
        <div className={dialog.actions}>
          {onCancel ? (
            <button type="button" className={dialog.secondary} onClick={onCancel} disabled={busy}>
              Cancelar
            </button>
          ) : null}
          <button type="button" className={dialog.primary} onClick={() => void confirm()} disabled={!image || busy || blocked || preparing}>
            {busy ? <Loader2 className={css.spin} aria-hidden /> : <ImageIcon aria-hidden />}
            {stage === "upload" ? "Enviando…" : stage === "link" ? "Colocando no bolso…" : replacing ? "Substituir imagem" : "Colocar no bolso"}
          </button>
        </div>
      </div>
      <p className="sr-only" aria-live="polite">
        {preparing ? "Preparando a imagem." : stage === "upload" ? "Enviando a imagem." : stage === "link" ? "Colocando a imagem no bolso." : image ? "Prévia pronta." : ""}
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Imagem de um bolso: ver, ajustar, substituir, remover
// ---------------------------------------------------------------------------

export type ImageDialogMode = "view" | "frame" | "replace" | "remove";

/**
 * Bolso com imagem personalizada: ver em tamanho maior, ajustar o
 * enquadramento (5233 foco), substituir (envio novo + troca atômica) ou
 * remover (confirmado; o arquivo só é apagado depois do banco). Coleção
 * arquivada: só ver.
 */
export function SlotImageDialog({
  host,
  collectionId,
  slot,
  image,
  pageNumber,
  editable,
  initialMode,
  onReplace,
  onSaveFocal,
  onRemove,
  onClose,
}: {
  host: HTMLElement | null;
  collectionId: string;
  slot: BinderSlot;
  image: SlotImage;
  pageNumber: number;
  editable: boolean;
  initialMode: ImageDialogMode;
  onReplace: (image: PreparedImage, focalY: number, onStage: (stage: "upload" | "link") => void) => SubmitResult;
  onSaveFocal: (focalY: number) => SubmitResult;
  onRemove: () => SubmitResult;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [mode, setMode] = useState<ImageDialogMode>(editable ? initialMode : "view");
  const [focal, setFocal] = useState(image.focalY);
  const [natural, setNatural] = useState<{ width: number; height: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useDialogKeys(ref, onClose, !busy);

  const frameable = natural ? canFrameVertically(natural.width, natural.height) : null;
  const where = `Página ${pageNumber} · linha ${slot.row}, coluna ${slot.column}`;

  const run = async (action: () => SubmitResult) => {
    setBusy(true);
    setError(null);
    const message = await action();
    if (message !== null) {
      setBusy(false);
      setError(message);
    }
  };

  if (!host) return null;
  return createPortal(
    <div className={dialog.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={ref} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1} className={dialog.dialog} data-wide>
        <div className={dialog.head}>
          <span className={dialog.icon} aria-hidden>
            {mode === "remove" ? <Trash2 /> : mode === "frame" ? <Crop /> : mode === "replace" ? <RefreshCw /> : <ImageIcon />}
          </span>
          <div>
            <h2 id={titleId} className={dialog.title}>
              {mode === "remove" ? "Remover imagem" : mode === "frame" ? "Ajustar enquadramento" : mode === "replace" ? "Substituir imagem" : "Imagem do bolso"}
            </h2>
            <p className={dialog.lead}>{where}</p>
          </div>
          <button type="button" className={dialog.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        {mode === "replace" ? (
          <ImageComposer collectionId={collectionId} replacing onSubmit={onReplace} onCancel={() => setMode("view")} />
        ) : (
          <>
            <div className={css.stageRow}>
              <PocketPreview
                src={image.url}
                width={mode === "view" ? 200 : 180}
                focalY={mode === "frame" ? focal : image.focalY}
                natural={natural}
                onNatural={setNatural}
                onFocal={mode === "frame" && !busy ? setFocal : undefined}
              />
              <div className={css.meta}>
                {mode === "view" ? (
                  <>
                    <p className={css.metaLine}>Imagem personalizada deste bolso. Ela enfeita o fichário — não conta como carta, progresso ou valor.</p>
                    {editable ? (
                      <div className={css.toolRow}>
                        <button
                          type="button"
                          className={css.linkButton}
                          onClick={() => {
                            setFocal(image.focalY);
                            setMode("frame");
                          }}
                          disabled={frameable === false}
                          title={frameable === false ? "A imagem já cabe inteira na altura do bolso" : undefined}
                        >
                          <Crop aria-hidden />
                          Ajustar enquadramento
                        </button>
                        <button type="button" className={css.linkButton} onClick={() => setMode("replace")}>
                          <RefreshCw aria-hidden />
                          Substituir
                        </button>
                        <button type="button" className={css.linkButton} onClick={() => setMode("remove")}>
                          <Trash2 aria-hidden />
                          Remover
                        </button>
                      </div>
                    ) : (
                      <p className={css.metaLine}>A coleção está arquivada: a imagem pode ser vista, mas não alterada.</p>
                    )}
                  </>
                ) : mode === "frame" ? (
                  <>
                    <p className={css.metaLine}>
                      {frameable === false
                        ? "A imagem já cabe inteira na altura do bolso — não há o que ajustar."
                        : "Arraste a imagem para cima ou para baixo, ou use ↑ ↓ com o bolso em foco."}
                    </p>
                    {frameable ? <FocalReadout value={focal} /> : null}
                  </>
                ) : (
                  <p className={css.metaLine}>O bolso fica vazio e o arquivo da imagem é apagado. As cartas e o progresso não mudam.</p>
                )}
              </div>
            </div>

            {error ? (
              <p className={css.alert} role="alert">
                {error}
              </p>
            ) : null}

            {mode === "frame" ? (
              <div className={dialog.actions}>
                <button type="button" className={dialog.secondary} onClick={() => setMode("view")} disabled={busy}>
                  Cancelar
                </button>
                <button
                  type="button"
                  className={dialog.primary}
                  disabled={busy || frameable !== true || clampFocal(focal) === image.focalY}
                  onClick={() => void run(() => onSaveFocal(clampFocal(focal)))}
                >
                  {busy ? <Loader2 className={css.spin} aria-hidden /> : null}
                  {busy ? "Salvando…" : "Salvar enquadramento"}
                </button>
              </div>
            ) : mode === "remove" ? (
              <div className={dialog.actions} role="alertdialog" aria-label="Confirmar remoção da imagem">
                <button type="button" className={dialog.secondary} onClick={() => setMode("view")} disabled={busy} autoFocus>
                  Cancelar
                </button>
                <button type="button" className={css.danger} disabled={busy} onClick={() => void run(onRemove)}>
                  {busy ? <Loader2 className={css.spin} aria-hidden /> : <Trash2 className="h-[15px] w-[15px]" aria-hidden />}
                  {busy ? "Removendo…" : "Remover imagem"}
                </button>
              </div>
            ) : null}
          </>
        )}
        <p className="sr-only" aria-live="polite">
          {busy ? (mode === "remove" ? "Removendo a imagem." : "Salvando o enquadramento.") : ""}
        </p>
      </div>
    </div>,
    host,
  );
}
