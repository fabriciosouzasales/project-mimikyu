"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { AlertTriangle, BetweenVerticalStart, Crop, Image as ImageIcon, ImagePlus, Loader2, Move, RefreshCw, Ungroup, X } from "lucide-react";
import { readSlotImageSummary } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { BINDER_UNITS, type RegionImage } from "@/lib/colecoes/binder";
import { FOCAL_DEFAULT, SLOT_IMAGE_LIMIT, SOURCE_ACCEPT, type SlotImageSummary, imagesLeft } from "@/lib/colecoes/binder-images";
import { type GapPreview, gapServerPreviewMessage } from "@/lib/colecoes/binder-insert";
import { clampFocal2, focal2ForKey, focal2Label, regionAspect, regionObjectPosition } from "@/lib/colecoes/binder-region";
import { type SubmitResult, useDialogKeys } from "./binder-image-editor";
import { type PreparedImage, cleanupUnlinkedSlotImagesOnce, prepareSlotImage } from "./binder-image-io";
import type { RegionDialogMode } from "./binder-slot";
import dialog from "./binder-add-pages.module.css";
import css from "./binder-image.module.css";

/**
 * Personalização do layout do fichário (P2-BINDER-LAYOUT-CUSTOMIZATION):
 *  - imagem em 2 bolsos (5239–5242): prévia larga com enquadramento em dois
 *    eixos, composição, ver/ajustar/substituir/separar;
 *  - "Abrir espaço" (5243): prévia vinda do banco e confirmação explícita
 *    quando atravessa páginas ou precisa de página nova.
 * Mesma linguagem dos diálogos do fichário; movimento só com
 * opacidade/transform e nada com movimento reduzido (CSS dos módulos).
 */

const GAP_RATIO = BINDER_UNITS.gap;

export type WideSubmit = (image: PreparedImage, focalX: number, focalY: number, onStage: (stage: "upload" | "link") => void) => SubmitResult;

// ---------------------------------------------------------------------------
// Prévia larga com enquadramento em dois eixos
// ---------------------------------------------------------------------------

function overflow(natural: { width: number; height: number }, box: { width: number; height: number }) {
  if (!(natural.width > 0 && natural.height > 0 && box.width > 0 && box.height > 0)) return { x: 0, y: 0 };
  const scale = Math.max(box.width / natural.width, box.height / natural.height);
  const x = natural.width * scale - box.width;
  const y = natural.height * scale - box.height;
  return { x: x < 0.01 ? 0 : x, y: y < 0.01 ? 0 : y };
}

/**
 * A área de 2 bolsos em tamanho de prévia (2 × 8:11 + o vão). Com
 * `onFocal`, vira o controle de enquadramento: arrastar em qualquer direção
 * ou setas (2), PageUp/PageDown (10, vertical), Home (centro).
 */
export function WidePreview({
  src,
  width,
  focalX,
  focalY,
  natural,
  onFocal,
  onNatural,
}: {
  src: string | null;
  width: number;
  focalX: number;
  focalY: number;
  natural: { width: number; height: number } | null;
  onFocal?: (value: { focalX: number; focalY: number }) => void;
  onNatural?: (size: { width: number; height: number }) => void;
}) {
  const boxRef = useRef<HTMLDivElement>(null);
  const drag = useRef<{ x: number; y: number; fx: number; fy: number; ox: number; oy: number; id: number } | null>(null);
  const [dragging, setDragging] = useState(false);
  const [failed, setFailed] = useState(false);
  const [box, setBox] = useState<{ width: number; height: number } | null>(null);
  useEffect(() => setFailed(false), [src]);
  useEffect(() => {
    const node = boxRef.current;
    if (!node) return;
    const rect = node.getBoundingClientRect();
    setBox({ width: rect.width, height: rect.height });
  }, [width]);
  const room = natural && box ? overflow(natural, box) : { x: 0, y: 0 };
  const frameable = Boolean(onFocal && (room.x > 0 || room.y > 0));

  return (
    <div
      ref={boxRef}
      className={css.pocket}
      style={{ width, aspectRatio: regionAspect(2, GAP_RATIO) }}
      data-dragging={dragging || undefined}
    >
      {src && !failed ? (
        // eslint-disable-next-line @next/next/no-img-element -- URL assinada (privada, 1 h) ou prévia local blob:
        <img
          src={src}
          alt=""
          draggable={false}
          decoding="async"
          style={{ objectPosition: regionObjectPosition(focalX, focalY) }}
          onLoad={(event) => onNatural?.({ width: event.currentTarget.naturalWidth, height: event.currentTarget.naturalHeight })}
          onError={() => setFailed(true)}
        />
      ) : (
        <span className={css.unavailable}>
          <ImageIcon aria-hidden />
          Imagem indisponível agora
        </span>
      )}
      <span className={css.wideSeam} aria-hidden />
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
            aria-label="Enquadramento da imagem em 2 bolsos (setas movem, Home centraliza)"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={room.x > 0 ? clampFocal2(focalX, focalY).focalX : clampFocal2(focalX, focalY).focalY}
            aria-valuetext={focal2Label(focalX, focalY)}
            onKeyDown={(event) => {
              const next = focal2ForKey(event.key, focalX, focalY);
              if (!next) return;
              event.preventDefault();
              onFocal(next);
            }}
            onPointerDown={(event) => {
              const node = boxRef.current;
              if (!node || !natural) return;
              const rect = node.getBoundingClientRect();
              const o = overflow(natural, { width: rect.width, height: rect.height });
              drag.current = { x: event.clientX, y: event.clientY, fx: focalX, fy: focalY, ox: o.x, oy: o.y, id: event.pointerId };
              event.currentTarget.setPointerCapture(event.pointerId);
              setDragging(true);
            }}
            onPointerMove={(event) => {
              const d = drag.current;
              if (!d || d.id !== event.pointerId) return;
              const fx = d.ox > 0 ? d.fx - ((event.clientX - d.x) / d.ox) * 100 : d.fx;
              const fy = d.oy > 0 ? d.fy - ((event.clientY - d.y) / d.oy) * 100 : d.fy;
              onFocal(clampFocal2(fx, fy));
            }}
            onPointerUp={(event) => {
              if (drag.current?.id !== event.pointerId) return;
              drag.current = null;
              setDragging(false);
            }}
            onPointerCancel={() => {
              drag.current = null;
              setDragging(false);
            }}
          />
          <span className={css.frameCue} data-pos="center" aria-hidden>
            <Move />
          </span>
        </>
      ) : null}
    </div>
  );
}

function FocalHint({ focalX, focalY }: { focalX: number; focalY: number }) {
  return (
    <p className={css.metaLine} aria-hidden>
      {focal2Label(focalX, focalY)}
    </p>
  );
}

// ---------------------------------------------------------------------------
// 1 bolso | 2 bolsos (aba Imagem do seletor do bolso)
// ---------------------------------------------------------------------------

export function ImageShapeSwitch({
  shape,
  wideReason,
  onChange,
}: {
  shape: "single" | "wide";
  /** Por que "2 bolsos" não vale aqui (`null` = vale). */
  wideReason: string | null;
  onChange: (shape: "single" | "wide") => void;
}) {
  const hintId = useId();
  return (
    <div className="flex flex-col gap-1.5">
      <div className={css.modes} role="radiogroup" aria-label="Tamanho da imagem">
        <button type="button" role="radio" aria-checked={shape === "single"} aria-selected={shape === "single"} className={css.mode} onClick={() => onChange("single")}>
          <ImageIcon aria-hidden />1 bolso
        </button>
        <button
          type="button"
          role="radio"
          aria-checked={shape === "wide"}
          aria-selected={shape === "wide"}
          aria-disabled={wideReason ? true : undefined}
          aria-describedby={wideReason ? hintId : undefined}
          className={css.mode}
          onClick={() => !wideReason && onChange("wide")}
        >
          <span className={css.wideGlyph} aria-hidden />2 bolsos
        </button>
      </div>
      {wideReason ? (
        <p id={hintId} className={css.metaLine}>
          {wideReason}
        </p>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Escolher, preparar, enquadrar e confirmar a imagem larga
// ---------------------------------------------------------------------------

type SummaryState = { status: "loading" } | { status: "ready"; summary: SlotImageSummary } | { status: "error" };

/**
 * Mesma sequência da imagem do bolso (nada sai antes da confirmação;
 * envio para caminho novo; vínculo atômico no banco), com a prévia no
 * formato da área de 2 bolsos. `replacing` não consome vaga do limite.
 */
export function RegionComposer({
  collectionId,
  replacing = false,
  width = 300,
  onSubmit,
  onCancel,
}: {
  collectionId: string;
  replacing?: boolean;
  width?: number;
  onSubmit: WideSubmit;
  onCancel?: () => void;
}) {
  const inputId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [summary, setSummary] = useState<SummaryState>({ status: "loading" });
  const [image, setImage] = useState<PreparedImage | null>(null);
  const [focal, setFocal] = useState({ focalX: FOCAL_DEFAULT, focalY: FOCAL_DEFAULT });
  const [preparing, setPreparing] = useState(false);
  const [stage, setStage] = useState<"upload" | "link" | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [over, setOver] = useState(false);
  const handedOff = useRef(false);
  const imageRef = useRef<PreparedImage | null>(null);
  imageRef.current = image;

  useEffect(() => {
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
    setFocal({ focalX: FOCAL_DEFAULT, focalY: FOCAL_DEFAULT });
  }, []);

  const left = summary.status === "ready" ? imagesLeft(summary.summary) : null;
  const blocked = !replacing && left === 0;
  const busy = stage !== null;

  const confirm = async () => {
    if (!image || busy || blocked) return;
    setError(null);
    setStage("upload");
    const message = await onSubmit(image, focal.focalX, focal.focalY, setStage);
    if (message === null) {
      handedOff.current = true;
      return;
    }
    setStage(null);
    setError(message);
  };

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
          <span className={css.dropPocket} data-wide aria-hidden>
            {preparing ? <Loader2 className={css.spin} /> : <ImagePlus />}
          </span>
          <span>
            <span className={css.dropTitle}>{preparing ? "Preparando a imagem…" : replacing ? "Escolher a nova imagem" : "Escolher uma imagem larga"}</span>
            <span className={`${css.dropHint} block`}>
              Ela ocupa os 2 bolsos lado a lado, como uma só peça. Imagens deitadas ficam melhores. JPEG, PNG ou WebP; removemos dados de localização da foto.
            </span>
          </span>
        </label>
      ) : (
        <div className={css.stageColumn}>
          <WidePreview
            src={image.url}
            width={width}
            focalX={focal.focalX}
            focalY={focal.focalY}
            natural={{ width: image.width, height: image.height }}
            onFocal={busy ? undefined : setFocal}
          />
          <div className={css.metaRow}>
            <div className="min-w-0">
              <p className={css.metaTitle}>Enquadramento</p>
              <p className={css.metaLine}>Arraste a imagem ou use as setas com a área em foco. Home centraliza.</p>
              <FocalHint focalX={focal.focalX} focalY={focal.focalY} />
            </div>
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
          Você chegou ao limite de {SLOT_IMAGE_LIMIT} imagens. Remova uma imagem para colocar outra.
        </p>
      ) : null}
      {error ? (
        <p className={css.alert} role="alert">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className={css.quota} data-near={summary.status === "ready" && summary.summary.userCount >= SLOT_IMAGE_LIMIT - 25 ? true : undefined}>
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
            {stage === "upload" ? "Enviando…" : stage === "link" ? (replacing ? "Substituindo…" : "Unindo os bolsos…") : replacing ? "Substituir imagem" : "Colocar nos 2 bolsos"}
          </button>
        </div>
      </div>
      <p className="sr-only" aria-live="polite">
        {preparing ? "Preparando a imagem." : stage === "upload" ? "Enviando a imagem." : stage === "link" ? "Unindo os bolsos." : image ? "Prévia pronta." : ""}
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Imagem em 2 bolsos: ver, ajustar, substituir, separar
// ---------------------------------------------------------------------------

export function RegionImageDialog({
  host,
  collectionId,
  region,
  where,
  editable,
  initialMode,
  onReplace,
  onSaveFocal,
  onSeparate,
  onClose,
}: {
  host: HTMLElement | null;
  collectionId: string;
  region: RegionImage | null;
  /** "Página 3 · linha 2, colunas 1–2" */
  where: string;
  editable: boolean;
  initialMode: RegionDialogMode;
  onReplace: WideSubmit;
  onSaveFocal: (focalX: number, focalY: number) => SubmitResult;
  onSeparate: () => SubmitResult;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [mode, setMode] = useState<RegionDialogMode>(editable ? (region || initialMode === "separate" ? initialMode : "view") : "view");
  const [focal, setFocal] = useState({ focalX: region?.focalX ?? 50, focalY: region?.focalY ?? 50 });
  const [natural, setNatural] = useState<{ width: number; height: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useDialogKeys(ref, onClose, !busy);

  const run = async (action: () => SubmitResult) => {
    setBusy(true);
    setError(null);
    const message = await action();
    if (message !== null) {
      setBusy(false);
      setError(message);
    }
  };

  const unchanged = region !== null && focal.focalX === region.focalX && focal.focalY === region.focalY;
  const title = mode === "separate" ? "Separar os bolsos" : mode === "frame" ? "Ajustar enquadramento" : mode === "replace" ? "Substituir imagem" : "Imagem em 2 bolsos";

  if (!host) return null;
  return createPortal(
    <div className={dialog.veil} onPointerDown={(event) => event.target === event.currentTarget && !busy && onClose()}>
      <div ref={ref} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1} className={dialog.dialog} data-wide>
        <div className={dialog.head}>
          <span className={dialog.icon} aria-hidden>
            {mode === "separate" ? <Ungroup /> : mode === "frame" ? <Crop /> : mode === "replace" ? <RefreshCw /> : <ImageIcon />}
          </span>
          <div>
            <h2 id={titleId} className={dialog.title}>
              {title}
            </h2>
            <p className={dialog.lead}>{where}</p>
          </div>
          <button type="button" className={dialog.close} onClick={onClose} aria-label="Fechar" disabled={busy}>
            <X aria-hidden />
          </button>
        </div>

        {mode === "replace" ? (
          <RegionComposer collectionId={collectionId} replacing onSubmit={onReplace} onCancel={() => setMode("view")} />
        ) : (
          <>
            <div className={css.stageColumn}>
              <WidePreview
                src={region?.url ?? null}
                width={340}
                focalX={mode === "frame" ? focal.focalX : (region?.focalX ?? 50)}
                focalY={mode === "frame" ? focal.focalY : (region?.focalY ?? 50)}
                natural={natural}
                onNatural={setNatural}
                onFocal={mode === "frame" && !busy ? setFocal : undefined}
              />
              {mode === "view" ? (
                <div className={css.metaRow}>
                  <p className={css.metaLine}>Uma imagem ocupando 2 bolsos. Ela enfeita o fichário — não conta como carta, progresso ou valor.</p>
                  {editable ? (
                    <div className={css.toolRow}>
                      <button
                        type="button"
                        className={css.linkButton}
                        disabled={!region}
                        onClick={() => {
                          if (region) setFocal({ focalX: region.focalX, focalY: region.focalY });
                          setMode("frame");
                        }}
                      >
                        <Crop aria-hidden />
                        Ajustar
                      </button>
                      <button type="button" className={css.linkButton} disabled={!region} onClick={() => setMode("replace")}>
                        <RefreshCw aria-hidden />
                        Substituir
                      </button>
                      <button type="button" className={css.linkButton} onClick={() => setMode("separate")}>
                        <Ungroup aria-hidden />
                        Separar
                      </button>
                    </div>
                  ) : (
                    <p className={css.metaLine}>A coleção está arquivada: a imagem pode ser vista, mas não alterada.</p>
                  )}
                </div>
              ) : mode === "frame" ? (
                <div className={css.metaRow}>
                  <p className={css.metaLine}>Arraste a imagem ou use as setas com a área em foco. Home centraliza.</p>
                  <FocalHint focalX={focal.focalX} focalY={focal.focalY} />
                </div>
              ) : (
                <p className={css.metaLine}>Os 2 bolsos voltam a ser bolsos livres e o arquivo da imagem é apagado. As cartas e o progresso não mudam.</p>
              )}
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
                <button type="button" className={dialog.primary} disabled={busy || unchanged || !region} onClick={() => void run(() => onSaveFocal(focal.focalX, focal.focalY))}>
                  {busy ? <Loader2 className={css.spin} aria-hidden /> : null}
                  {busy ? "Salvando…" : "Salvar enquadramento"}
                </button>
              </div>
            ) : mode === "separate" ? (
              <div className={dialog.actions} role="alertdialog" aria-label="Confirmar separação dos bolsos">
                <button type="button" className={dialog.secondary} onClick={() => setMode("view")} disabled={busy} autoFocus>
                  Cancelar
                </button>
                <button type="button" className={css.danger} disabled={busy} onClick={() => void run(onSeparate)}>
                  {busy ? <Loader2 className={css.spin} aria-hidden /> : <Ungroup className="h-[15px] w-[15px]" aria-hidden />}
                  {busy ? "Separando…" : "Separar os bolsos"}
                </button>
              </div>
            ) : null}
          </>
        )}
        <p className="sr-only" aria-live="polite">
          {busy ? (mode === "separate" ? "Separando os bolsos." : "Salvando o enquadramento.") : ""}
        </p>
      </div>
    </div>,
    host,
  );
}

// ---------------------------------------------------------------------------
// Abrir espaço: prévia do banco e confirmação
// ---------------------------------------------------------------------------

export type GapDialogState = {
  slotId: string;
  page: number;
  row: number;
  column: number;
  preview: GapPreview;
  running: boolean;
  error: string | null;
  /** A prévia foi refeita porque o fichário mudou. */
  refreshed: boolean;
};

const EXECUTABLE = new Set(["SAME_PAGE", "CROSS_PAGE", "NEEDS_PAGE"]);

/**
 * Só aparece quando o espaço atravessa páginas, precisa de página nova ou
 * não pode ser aberto (barreira, limite). Na mesma página o espaço abre
 * direto, com "Desfazer" na mensagem (D1/D3/D4).
 */
export function GapDialog({ host, state, onConfirm, onClose }: { host: HTMLElement | null; state: GapDialogState; onConfirm: () => void; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const descId = useId();
  useDialogKeys(ref, onClose, !state.running);
  const { preview } = state;
  const executable = EXECUTABLE.has(preview.outcome);
  const needsPage = preview.outcome === "NEEDS_PAGE";
  const items = [
    preview.movedCards > 0 ? `${preview.movedCards} ${preview.movedCards === 1 ? "carta" : "cartas"}` : null,
    preview.movedReserves > 0 ? `${preview.movedReserves} ${preview.movedReserves === 1 ? "reserva" : "reservas"}` : null,
    preview.movedImages > 0 ? `${preview.movedImages} ${preview.movedImages === 1 ? "imagem" : "imagens"}` : null,
  ].filter(Boolean);

  if (!host) return null;
  return createPortal(
    <div className={dialog.veil} onPointerDown={(event) => event.target === event.currentTarget && !state.running && onClose()}>
      <div ref={ref} role={executable ? "dialog" : "alertdialog"} aria-modal="true" aria-labelledby={titleId} aria-describedby={descId} tabIndex={-1} className={dialog.dialog}>
        <div className={dialog.head}>
          <span className={dialog.icon} data-tone={executable ? undefined : "warn"} aria-hidden>
            {executable ? <BetweenVerticalStart /> : <AlertTriangle />}
          </span>
          <div>
            <h2 id={titleId} className={dialog.title}>
              {executable ? (needsPage ? "Abrir espaço com uma página nova" : "Abrir espaço") : "Não dá para abrir espaço aqui"}
            </h2>
            <p className={dialog.lead}>
              Antes do bolso da página {state.page} · linha {state.row}, coluna {state.column}
            </p>
          </div>
          <button type="button" className={dialog.close} onClick={onClose} aria-label="Fechar" disabled={state.running}>
            <X aria-hidden />
          </button>
        </div>

        {state.refreshed ? (
          <p className={css.notice} role="status">
            O fichário mudou desde a primeira prévia. Esta é a prévia atualizada.
          </p>
        ) : null}
        <p id={descId} className="text-[13px] leading-relaxed text-white/80">
          {gapServerPreviewMessage(preview)}
        </p>

        {executable ? (
          <dl className={dialog.facts}>
            <div>
              <dt>Bolsos que avançam</dt>
              <dd>
                <strong>{preview.movedPockets.toLocaleString("pt-BR")}</strong>
                {items.length > 0 ? ` · ${items.join(", ")}` : ""}
              </dd>
            </div>
            <div>
              <dt>{preview.pages.length === 1 ? "Página" : "Páginas"}</dt>
              <dd>
                <strong>{preview.pages.join(", ")}</strong>
                {needsPage ? " · + 1 nova ao final" : ""}
              </dd>
            </div>
          </dl>
        ) : null}

        {state.error ? (
          <p className={css.alert} role="alert">
            {state.error}
          </p>
        ) : null}

        <div className={dialog.actions}>
          <button type="button" className={dialog.secondary} onClick={onClose} disabled={state.running} autoFocus={!executable}>
            {executable ? "Cancelar" : "Entendi"}
          </button>
          {executable ? (
            <button type="button" className={dialog.primary} onClick={onConfirm} disabled={state.running} autoFocus>
              {state.running ? <Loader2 className={css.spin} aria-hidden /> : <BetweenVerticalStart aria-hidden />}
              {state.running ? "Abrindo espaço…" : needsPage ? "Adicionar página e abrir espaço" : "Abrir espaço"}
            </button>
          ) : null}
        </div>
        <p className="sr-only" aria-live="polite">
          {state.running ? "Abrindo o espaço." : ""}
        </p>
      </div>
    </div>,
    host,
  );
}
