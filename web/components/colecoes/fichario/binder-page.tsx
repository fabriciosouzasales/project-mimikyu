"use client";

import { useEffect, useRef, useState } from "react";
import { Lock, Shuffle } from "lucide-react";
import { cardFrontUrl, formatCollectorNumber } from "@/lib/colecoes/acervo";
import { type BinderPage, type BinderSlot, type PreviewSampleSlot, slotDescription } from "@/lib/colecoes/binder";
import styles from "./binder.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/** Um bolso pronto para desenhar — comum ao fichário real e à amostra da prévia. */
export type PocketView = {
  key: string;
  row: number;
  column: number;
  kind: "card" | "mismatch" | "reserve" | "empty";
  name: string | null;
  number: string | null;
  finish: string | null;
  imagePath: string | null;
  locked: boolean;
  label: string;
};

export function pocketsFromPage(page: BinderPage): PocketView[] {
  return page.slots.map((slot) => pocketFromSlot(slot));
}

export function pocketFromSlot(slot: BinderSlot): PocketView {
  const occupied = slot.state === "OCCUPIED_MATCH" || slot.state === "OCCUPIED_UNPLANNED" || slot.state === "OCCUPIED_MISMATCH";
  const face = occupied ? slot.present : slot.expected;
  return {
    key: slot.slotId,
    row: slot.row,
    column: slot.column,
    kind: slot.state === "OCCUPIED_MISMATCH" ? "mismatch" : occupied ? "card" : slot.state === "RESERVED_EMPTY" ? "reserve" : "empty",
    name: face?.cardName ?? null,
    number: face?.collectorNumber ? formatCollectorNumber(face.collectorNumber, face.collectorTotal) : null,
    finish: face?.finishName ?? face?.finishCode ?? null,
    imagePath: face?.imagePath ?? null,
    locked: slot.locked,
    label: slotDescription(slot),
  };
}

/** Amostra da prévia (página 1 do plano): mesma linguagem visual do fichário real. */
export function pocketsFromSample(sample: PreviewSampleSlot[], columns: number, rows: number): PocketView[] {
  const byCell = new Map(sample.map((item) => [`${item.row}:${item.column}`, item]));
  const pockets: PocketView[] = [];
  for (let row = 1; row <= rows; row += 1) {
    for (let column = 1; column <= columns; column += 1) {
      const item = byCell.get(`${row}:${column}`);
      const where = `Linha ${row}, coluna ${column}`;
      if (!item) {
        pockets.push({ key: `${row}:${column}`, row, column, kind: "empty", name: null, number: null, finish: null, imagePath: null, locked: false, label: `${where}: bolso vazio` });
        continue;
      }
      const reserve = item.state === "RESERVED";
      pockets.push({
        key: `${row}:${column}`,
        row,
        column,
        kind: reserve ? "reserve" : "card",
        name: item.cardName,
        number: item.collectorNumber,
        finish: item.finishCode,
        imagePath: item.imagePath,
        locked: false,
        label: reserve
          ? `${where}: reservado para ${item.cardName ?? "uma carta"}`
          : `${where}: ${item.cardName ?? "carta"}${item.state === "EXTRA" ? " (adicional)" : ""}`,
      });
    }
  }
  return pockets;
}

export function BinderPageGrid({
  pockets,
  columns,
  pageNumber,
  side,
  priority = false,
  loading = false,
  rows,
}: {
  pockets: PocketView[] | null;
  columns: number;
  rows: number;
  pageNumber: number | null;
  side: "left" | "right" | "single";
  priority?: boolean;
  loading?: boolean;
}) {
  const style = { "--cols": columns } as React.CSSProperties;
  return (
    <ul
      className={styles.page}
      style={style}
      data-side={side}
      aria-label={pageNumber ? `Página ${pageNumber}` : "Página"}
      aria-busy={loading || undefined}
    >
      {pockets
        ? pockets.map((pocket, index) => <Pocket key={pocket.key} pocket={pocket} priority={priority && index < columns * 2} />)
        : Array.from({ length: columns * rows }).map((_, index) => (
            <li key={index} className={styles.pocket} aria-hidden="true">
              {loading ? <span className={styles.pocketSkeleton} /> : null}
            </li>
          ))}
      {pageNumber ? (
        <span className={styles.pageNumber} aria-hidden="true">
          {pageNumber}
        </span>
      ) : null}
    </ul>
  );
}

function Pocket({ pocket, priority }: { pocket: PocketView; priority: boolean }) {
  return (
    <li className={styles.pocket} data-state={pocket.kind === "card" || pocket.kind === "mismatch" ? "OCCUPIED" : pocket.kind} aria-label={pocket.label}>
      <PocketContent pocket={pocket} priority={priority} />
    </li>
  );
}

/** Conteúdo visual de um bolso (carta, reserva, selos) — comum à prévia e à área de trabalho. */
export function PocketContent({ pocket, priority, sizes }: { pocket: PocketView; priority: boolean; sizes?: string }) {
  return (
    <>
      {pocket.kind === "card" || pocket.kind === "mismatch" ? (
        <span className={styles.cardWrap}>
          <PocketArt src={cardFrontUrl(SUPABASE_URL, pocket.imagePath)} name={pocket.name} number={pocket.number} priority={priority} sizes={sizes} />
        </span>
      ) : null}
      {pocket.kind === "reserve" ? (
        <span className={styles.reserve}>
          <PocketArt src={cardFrontUrl(SUPABASE_URL, pocket.imagePath)} name={null} number={null} priority={false} sizes={sizes} />
          <span className={styles.reserveLabel} aria-hidden="true">
            <strong>{pocket.name ?? "Reservado"}</strong>
            <span className={styles.reserveShort}>{pocket.number ?? "Falta"}</span>
            <span className={styles.reserveLong}>{["Falta", pocket.number, pocket.finish].filter(Boolean).join(" · ")}</span>
          </span>
        </span>
      ) : null}
      {pocket.locked ? (
        <span className={`${styles.badge} ${styles.badgeLock}`} aria-hidden="true" title="Bolso fixado">
          <Lock />
        </span>
      ) : null}
      {pocket.kind === "mismatch" ? (
        <span className={`${styles.badge} ${styles.badgeMismatch}`} aria-hidden="true" title="Diferente da carta reservada">
          <Shuffle />
        </span>
      ) : null}
    </>
  );
}

/**
 * Frente da carta no bolso. Mesma estratégia de `CardArt` (Meu acervo):
 * img nativo do bucket público, dimensões declaradas, fade curto ao chegar e
 * moldura com nome/número quando a imagem não existe ou falha.
 */
export function PocketArt({
  src,
  name,
  number,
  priority,
  sizes = "(min-width: 1024px) 14vw, 30vw",
}: {
  src: string | null;
  name: string | null;
  number: string | null;
  priority: boolean;
  sizes?: string;
}) {
  const [state, setState] = useState<"loading" | "loaded" | "failed">(src ? "loading" : "failed");
  const ref = useRef<HTMLImageElement>(null);

  useEffect(() => {
    setState(src ? "loading" : "failed");
  }, [src]);

  useEffect(() => {
    const img = ref.current;
    if (img?.complete) setState(img.naturalWidth > 0 ? "loaded" : "failed");
  }, [src]);

  if (!src || state === "failed") {
    if (!name) return null;
    return (
      <span className={styles.cardFallback} aria-hidden="true">
        <span>{name}</span>
        {number ? <small>{number}</small> : null}
      </span>
    );
  }
  return (
    // eslint-disable-next-line @next/next/no-img-element -- asset já otimizado no pipeline, URL pública imutável
    <img
      ref={ref}
      src={src}
      alt=""
      width={367}
      height={512}
      sizes={sizes}
      loading={priority ? "eager" : "lazy"}
      decoding="async"
      fetchPriority={priority ? "high" : "low"}
      draggable={false}
      data-state={state}
      className={styles.cardImage}
      onLoad={() => setState("loaded")}
      onError={() => setState("failed")}
    />
  );
}
