"use client";

import { type ReactNode, useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Image as ImageIcon, Layers, Loader2, PackagePlus, Plus, RotateCcw, X } from "lucide-react";
import { readAvailableCards } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { cardFrontUrl, formatCollectorNumber } from "@/lib/colecoes/acervo";
import type { BinderSlot } from "@/lib/colecoes/binder";
import { type AvailableCard, type AvailableOrigin, availableOriginLabel, mergeAvailable, pickerOrigins } from "@/lib/colecoes/binder-share";
import styles from "./binder-add-pages.module.css";
import { useDialogKeys } from "./binder-image-editor";
import imageStyles from "./binder-image.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

type SourceState = { status: "loading" | "error" | "ready"; items: AvailableCard[]; total: number; loadingMore: boolean };

/**
 * "Adicionar carta" no bolso vazio (P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01) —
 * comportamento do spike `binder-nav-01` (EmptySlotQuickActions → Card
 * Picker), sobre dados reais.
 *
 * Lista os exemplares guardados neste fichário físico e ainda sem bolso
 * (5252 `get_my_collection_binder_unplaced`, 48 por vez), com as abas de
 * origem Todas · Desta coleção · Outras coleções · Sem coleção (BINDER-
 * PHYSICAL-LOCATION, D3). Escolher uma carta a posiciona neste bolso (5250,
 * feito pela área de trabalho). Bolso reservado só oferece cartas da coleção
 * dona da reserva, com a carta reservada em destaque.
 * Nada é substituído: só bolso vazio e solto abre este seletor.
 *
 * P2-BINDER-CUSTOM-IMAGES-CLOSEOUT-AND-FRONTEND-01: "Carta | Imagem". A aba
 * Imagem (C-198) só vale para bolso realmente livre — vazio, solto e sem
 * reserva; bolso reservado mostra o motivo. O conteúdo da aba vem da área de
 * trabalho (`imageTab.render`), que faz envio e vínculo.
 */
export function PocketPicker({
  host,
  target,
  pageNumber,
  collectionId,
  onPick,
  onClose,
  imageTab = null,
  initialMode = "card",
  onRegisterNew = null,
}: {
  host: HTMLElement | null;
  target: BinderSlot;
  pageNumber: number;
  /** Coleção pela qual o fichário está aberto (fronteira de dono das leituras). */
  collectionId: string;
  onPick: (card: AvailableCard) => void;
  onClose: () => void;
  /** Aba "Imagem": `available` falso mostra só o motivo (`reason`). */
  imageTab?: { available: boolean; reason: string | null; render: () => ReactNode } | null;
  initialMode?: "card" | "image";
  /**
   * V1-06: "Cadastrar nova carta" — a carta ainda não está no acervo. A área
   * de trabalho abre o cadastro guardando no fichário físico e, depois,
   * coloca o exemplar novo neste bolso. `null` = ação ausente.
   */
  onRegisterNew?: (() => void) | null;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const [mode, setMode] = useState<"card" | "image">(imageTab?.available && initialMode === "image" ? "image" : "card");
  // Abas de origem; bolso reservado: só a coleção dona da reserva.
  const allowed = useMemo(
    () => pickerOrigins({ state: target.state, expectedCollectionId: target.expectedCollectionId }, collectionId),
    [collectionId, target.expectedCollectionId, target.state],
  );
  const [active, setActive] = useState<AvailableOrigin | null>(allowed[0]?.key ?? null);
  const [bySource, setBySource] = useState<Partial<Record<AvailableOrigin, SourceState>>>({});

  const load = useCallback(
    async (origin: AvailableOrigin, offset: number) => {
      const onlyCollectionId = allowed.find((option) => option.key === origin)?.onlyCollectionId ?? null;
      setBySource((prev) => {
        const current = prev[origin];
        return {
          ...prev,
          [origin]: offset === 0 ? { status: "loading", items: [], total: 0, loadingMore: false } : { ...(current as SourceState), loadingMore: true },
        };
      });
      // Reserva de outra coleção: recorte, total e paginação no SERVIDOR (5252 v1.2) — nunca só a página carregada.
      const result = await readAvailableCards({ collectionId, offset, origin, originCollectionId: onlyCollectionId }).catch(
        () => ({ ok: false as const, reason: "unknown" as const }),
      );
      setBySource((prev) => {
        const current = prev[origin];
        if (!result.ok) {
          return { ...prev, [origin]: offset === 0 ? { status: "error", items: [], total: 0, loadingMore: false } : { ...(current as SourceState), loadingMore: false } };
        }
        const items = offset === 0 ? result.items : mergeAvailable(current?.items ?? [], result.items);
        return { ...prev, [origin]: { status: "ready", items, total: Math.max(result.total, items.length), loadingMore: false } };
      });
    },
    [allowed, collectionId],
  );

  // Cada aba carrega na primeira vez em que é aberta ("Todas" primeiro).
  useEffect(() => {
    if (active && !bySource[active]) void load(active, 0);
  }, [active, bySource, load]);

  // Esc, Tab preso e setas que não vazam para o fichário (o enquadramento da aba Imagem trata as próprias).
  useDialogKeys(dialogRef, onClose);

  if (!host) return null;

  const state = active ? bySource[active] : undefined;
  const reservedCardId = target.state === "RESERVED_EMPTY" ? target.expectedCardId : null;
  // A carta reservada para este bolso aparece primeiro.
  const items = state?.items
    ? reservedCardId
      ? [...state.items].sort((a, b) => Number(b.cardId === reservedCardId) - Number(a.cardId === reservedCardId))
      : state.items
    : [];


  const where = `Página ${pageNumber} · linha ${target.row}, coluna ${target.column}`;

  return createPortal(
    <div className={styles.veil} onPointerDown={(event) => event.target === event.currentTarget && onClose()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1} className={styles.dialog} data-wide>
        <div className={styles.head}>
          <span className={styles.icon} aria-hidden>
            {mode === "image" ? <ImageIcon /> : <Plus />}
          </span>
          <div>
            <h2 id={titleId} className={styles.title}>
              {imageTab ? "Adicionar ao bolso" : "Adicionar carta"}
            </h2>
            <p className={styles.lead}>
              {where}
              {target.state === "RESERVED_EMPTY" && target.expected ? ` · reservado para ${target.expected.cardName}` : ""}
            </p>
          </div>
          <button type="button" className={styles.close} onClick={onClose} aria-label="Fechar">
            <X aria-hidden />
          </button>
        </div>

        {imageTab ? (
          <div className={imageStyles.modes} role="tablist" aria-label="O que colocar no bolso">
            <button type="button" role="tab" className={imageStyles.mode} aria-selected={mode === "card"} onClick={() => setMode("card")}>
              <Layers aria-hidden />
              Carta
            </button>
            <button
              type="button"
              role="tab"
              className={imageStyles.mode}
              aria-selected={mode === "image"}
              aria-disabled={!imageTab.available || undefined}
              title={!imageTab.available ? (imageTab.reason ?? undefined) : undefined}
              onClick={() => imageTab.available && setMode("image")}
            >
              <ImageIcon aria-hidden />
              Imagem
            </button>
          </div>
        ) : null}
        {imageTab && !imageTab.available && imageTab.reason ? <p className="sr-only">{imageTab.reason}</p> : null}

        {mode === "image" && imageTab?.available ? (
          imageTab.render()
        ) : allowed.length === 0 ? (
          <p className={styles.emptyState}>
            <strong>Bolso reservado para outra coleção</strong>
            Este bolso está guardado para uma carta de outra coleção do fichário. Escolha um bolso vazio.
          </p>
        ) : (
          <>
            {allowed.length > 1 ? (
              <div className={styles.tabs} role="tablist" aria-label="Origem das cartas">
                {allowed.map((source) => {
                  const s = bySource[source.key];
                  return (
                    <button
                      key={source.key}
                      type="button"
                      role="tab"
                      aria-selected={active === source.key}
                      className={styles.tab}
                      onClick={() => setActive(source.key)}
                    >
                      {source.label}
                      {s?.status === "ready" ? <span className={styles.tabCount}>{s.total.toLocaleString("pt-BR")}</span> : null}
                    </button>
                  );
                })}
              </div>
            ) : null}

            <div role={allowed.length > 1 ? "tabpanel" : undefined} aria-label={allowed.length > 1 ? "Cartas sem bolso" : undefined}>
              {!state || state.status === "loading" ? (
                <ul className={styles.pickGrid} aria-busy="true" aria-label="Carregando cartas sem bolso">
                  {Array.from({ length: 6 }).map((_, index) => (
                    <li key={index} className={styles.skeletonCard} />
                  ))}
                </ul>
              ) : state.status === "error" ? (
                <div className={styles.emptyState} role="alert">
                  <strong>Não conseguimos carregar as cartas.</strong>
                  Nada mudou no fichário.
                  <div className={`${styles.loadMore} mt-3`}>
                    <button type="button" className={styles.secondary} onClick={() => active && void load(active, 0)}>
                      <RotateCcw className="h-3.5 w-3.5" aria-hidden />
                      Tentar de novo
                    </button>
                  </div>
                </div>
              ) : items.length === 0 ? (
                <p className={styles.emptyState}>
                  <strong>Nenhuma carta sem bolso</strong>
                  {active === "ALL" ? "Todas as cartas guardadas neste fichário já estão nos bolsos." : "Nenhuma carta sem bolso nesta origem."}
                </p>
              ) : (
                <ul className={styles.pickGrid} aria-label="Cartas sem bolso — escolha uma para este bolso">
                  {items.map((card) => {
                    const reserved = reservedCardId !== null && card.cardId === reservedCardId;
                    const number = card.collectorNumber ? formatCollectorNumber(card.collectorNumber, card.collectorTotal) : null;
                    const detail = [number, card.variantLabel, card.languageCode?.toUpperCase()].filter(Boolean).join(" · ");
                    const src = cardFrontUrl(SUPABASE_URL, card.imagePath);
                    return (
                      <li key={card.physicalCardId}>
                        <button
                          type="button"
                          className={styles.pick}
                          data-reserved={reserved || undefined}
                          aria-label={`Colocar ${card.cardName}${detail ? `, ${detail}` : ""} (${availableOriginLabel(card)}) neste bolso${reserved ? " (carta reservada para ele)" : ""}`}
                          title={`${card.cardName} — ${availableOriginLabel(card)}`}
                          onClick={() => onPick(card)}
                        >
                          {src ? (
                            // eslint-disable-next-line @next/next/no-img-element -- mesmo asset dos bolsos (cache do navegador)
                            <img src={src} alt="" loading="lazy" decoding="async" draggable={false} />
                          ) : (
                            <span className={styles.pickFallback}>{card.cardName}</span>
                          )}
                          {reserved ? <span className={styles.pickBadge}>Reservada</span> : null}
                        </button>
                        <p className={styles.pickCaption}>{detail || card.cardName}</p>
                      </li>
                    );
                  })}
                </ul>
              )}
              {state?.status === "ready" && state.items.length < state.total ? (
                <div className={`${styles.loadMore} mt-2`}>
                  <button type="button" className={styles.secondary} onClick={() => active && void load(active, state.items.length)} disabled={state.loadingMore}>
                    {state.loadingMore ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : null}
                    Mostrar mais {(state.total - state.items.length).toLocaleString("pt-BR")}
                  </button>
                </div>
              ) : null}
            </div>
          </>
        )}

        {mode === "card" && onRegisterNew && allowed.length > 0 ? (
          <div className={styles.registerRow}>
            <span>A carta ainda não está no seu acervo?</span>
            <button type="button" className={styles.secondary} onClick={onRegisterNew} aria-haspopup="dialog">
              <PackagePlus className="h-3.5 w-3.5" aria-hidden />
              Cadastrar nova carta
            </button>
          </div>
        ) : null}

        <p className={styles.note}>
          {mode === "image"
            ? "A imagem enfeita só este bolso. Ela não conta como carta, progresso ou valor, e você pode ajustar, trocar ou remover depois."
            : "A carta escolhida entra neste bolso; nada que já está no fichário muda de lugar."}
        </p>
      </div>
    </div>,
    host,
  );
}
