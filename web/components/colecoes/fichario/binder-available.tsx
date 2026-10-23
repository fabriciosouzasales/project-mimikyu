"use client";

import { useDraggable } from "@dnd-kit/core";
import { Loader2, RotateCcw, X } from "lucide-react";
import { cardFrontUrl, formatCollectorNumber } from "@/lib/colecoes/acervo";
import type { AvailableCard } from "@/lib/colecoes/binder-share";
import type { SlotDragData } from "./binder-slot";
import styles from "./binder-available.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

export type AvailableState = { status: "idle" | "loading" | "error" | "ready"; items: AvailableCard[]; total: number; loadingMore: boolean };

/**
 * Cartas disponíveis (P2-SHARED-BINDER-FRONTEND-01) — exemplares DESTA
 * coleção que ainda não ocupam bolso (5230 `get_my_collection_binder_unplaced`).
 *
 * Não confundir com a Bandeja: a Bandeja é transporte temporário de cartas
 * que já estão no fichário; aqui ficam as cartas que ainda não têm lugar, e
 * a lista é persistente (vem do banco). Painel flutuante não modal: arrastar
 * uma carta até um bolso vazio, ou tocar na carta e depois no bolso. Cada
 * posicionamento é uma chamada à 5131 (`assign_card_to_slot`); nada acontece
 * sozinho e nenhuma carta substitui outra.
 */
export function AvailablePanel({
  collectionName,
  state,
  editable,
  armedId,
  onArm,
  onLoadMore,
  onRetry,
  onClose,
}: {
  collectionName: string;
  state: AvailableState;
  editable: boolean;
  armedId: string | null;
  onArm: (card: AvailableCard) => void;
  onLoadMore: () => void;
  onRetry: () => void;
  onClose: () => void;
}) {
  const remaining = Math.max(0, state.total - state.items.length);
  return (
    <section className={styles.panel} role="region" aria-labelledby="cartas-disponiveis-titulo">
      <div className={styles.head}>
        <div>
          <h3 id="cartas-disponiveis-titulo" className={styles.title}>
            Cartas disponíveis
            {state.status === "ready" ? <span className={styles.count}>{state.total.toLocaleString("pt-BR")}</span> : null}
          </h3>
          <p className={styles.hint}>
            {editable
              ? `Cartas de ${collectionName} ainda sem bolso. Arraste até um bolso vazio, ou toque na carta e depois no bolso.`
              : `Cartas de ${collectionName} ainda sem bolso. Coleção em modo leitura.`}
          </p>
        </div>
        <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar Cartas disponíveis">
          <X className="h-3.5 w-3.5" aria-hidden />
        </button>
      </div>

      <div className={styles.body}>
        {state.status === "loading" || state.status === "idle" ? (
          <ul className={styles.grid} aria-busy="true" aria-label="Carregando cartas disponíveis">
            {Array.from({ length: 6 }).map((_, index) => (
              <li key={index} className={styles.skeleton} />
            ))}
          </ul>
        ) : state.status === "error" ? (
          <div className={styles.state} role="alert">
            <span className={styles.stateTitle}>Não conseguimos carregar as cartas.</span>
            Nada mudou no fichário.
            <div className={styles.more}>
              <button type="button" className={styles.textButton} onClick={onRetry}>
                <RotateCcw className="h-3 w-3" aria-hidden />
                Tentar de novo
              </button>
            </div>
          </div>
        ) : state.items.length === 0 ? (
          <div className={styles.state}>
            <span className={styles.stateTitle}>Tudo no lugar</span>
            Todas as cartas de {collectionName} já estão nos bolsos.
          </div>
        ) : (
          <>
            <ul className={styles.grid}>
              {state.items.map((card) => (
                <AvailableItem key={card.allocationId} card={card} editable={editable} armed={armedId === card.allocationId} onArm={onArm} />
              ))}
            </ul>
            {remaining > 0 ? (
              <div className={styles.more}>
                <button type="button" className={styles.textButton} onClick={onLoadMore} disabled={state.loadingMore}>
                  {state.loadingMore ? <Loader2 className="h-3 w-3 animate-spin" aria-hidden /> : null}
                  Mostrar mais {remaining.toLocaleString("pt-BR")}
                </button>
              </div>
            ) : null}
          </>
        )}
      </div>
    </section>
  );
}

function AvailableItem({ card, editable, armed, onArm }: { card: AvailableCard; editable: boolean; armed: boolean; onArm: (card: AvailableCard) => void }) {
  const { setNodeRef, listeners, isDragging } = useDraggable({
    id: `available:${card.allocationId}`,
    // `slotId` carrega a alocação: cartas disponíveis ainda não têm bolso.
    data: { kind: "available", slotId: card.allocationId } satisfies SlotDragData,
    disabled: !editable,
  });
  const src = cardFrontUrl(SUPABASE_URL, card.imagePath);
  const number = card.collectorNumber ? formatCollectorNumber(card.collectorNumber, card.collectorTotal) : null;
  const detail = [number, card.variantLabel, card.languageCode?.toUpperCase()].filter(Boolean).join(" · ");
  return (
    <li>
      <button
        ref={setNodeRef}
        type="button"
        className={styles.card}
        aria-pressed={armed}
        aria-disabled={!editable || undefined}
        aria-label={`${card.cardName}${detail ? `, ${detail}` : ""}. ${armed ? "Escolhida: toque num bolso vazio." : "Escolher para colocar num bolso."}`}
        title={card.cardName}
        data-dragging={isDragging || undefined}
        onClick={() => editable && onArm(card)}
        {...listeners}
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element -- mesmo asset dos bolsos (cache do navegador)
          <img src={src} alt="" loading="lazy" decoding="async" draggable={false} />
        ) : (
          <span className={styles.fallback}>{card.cardName}</span>
        )}
      </button>
      <p className={styles.caption}>{detail || card.cardName}</p>
    </li>
  );
}
