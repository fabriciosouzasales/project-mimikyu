"use client";

import { type MouseEvent, type ReactNode, useRef, useState } from "react";
import { setCardFavorite } from "@/app/colecoes/favoritos/actions";
import { InlineFeedback } from "@/components/ui/feedback";
import {
  type CardFavoriteSend,
  type FavoriteEntry,
  type FavoriteOutcome,
  favoriteAnnouncement,
  favoriteCardNameFromLabel,
  favoriteErrorMessage,
  initialFavoriteEntry,
  normalizeId,
  settleCardFavorite,
  toggleCardFavorite,
} from "@/lib/favorites/card-favorites";

/**
 * Ilha controladora dos corações de carta (V1-10) — a `FavoritesController` da Pokédex
 * (P6) chaveada por carta, sem alterar a original.
 *
 * Os botões (`CardFavoriteButton`) vêm prontos com o estado inicial em `aria-pressed`;
 * este componente escuta os cliques por delegação. Por carta vale a máquina da P6: a
 * tela muda na hora (otimista), uma gravação por vez, a última intenção é a que fica no
 * servidor; falha = estado revertido + mensagem inline (STD-004). Todos os botões da
 * mesma carta na grade são pintados juntos (no Acervo, várias variantes da mesma carta).
 *
 * `onConfirmed` (opcional): avisa a grade quando o servidor confirma o estado final —
 * a Pesquisa guarda o conjunto em estado React para que cartas carregadas depois
 * ("Carregar mais") nasçam com o coração certo.
 */
export function CardFavoritesController({
  children,
  mode = "grid",
  onConfirmed,
  className,
  onFeedback,
}: {
  children: ReactNode;
  /** "favorites": página Cartas favoritas — atenua enquanto grava; a página remove após a confirmação. */
  mode?: "grid" | "favorites";
  onConfirmed?: (cardId: string, isFavorite: boolean) => void;
  /**
   * Extensão no Fichário (V1-10): classe da raiz (ex.: `contents`, para não mexer na
   * grade) e o erro entregue ao aviso do próprio Fichário em vez do aviso no fluxo.
   * Sem elas, exatamente o comportamento de antes (Acervo, Pesquisa, Cartas favoritas).
   */
  className?: string;
  onFeedback?: (feedback: { tone: "error"; text: string }) => void;
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const entries = useRef(new Map<string, FavoriteEntry>());
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);

  function paint(cardId: string, entry: FavoriteEntry) {
    const root = rootRef.current;
    if (!root) return;
    root.querySelectorAll<HTMLButtonElement>(`button[data-card-fav="${cardId}"]`).forEach((button) => {
      button.setAttribute("aria-pressed", String(entry.desired));
      if (entry.inFlight) button.setAttribute("data-pending", "");
      else button.removeAttribute("data-pending");
      if (mode === "favorites") {
        const item = button.closest<HTMLElement>("[data-fav-item]");
        if (entry.desired) item?.removeAttribute("data-fav-removed");
        else item?.setAttribute("data-fav-removed", "");
      }
    });
  }

  async function write(send: CardFavoriteSend, cardName: string) {
    let outcome: FavoriteOutcome;
    let reason: Parameters<typeof favoriteErrorMessage>[1] = "failed";
    try {
      const result = await setCardFavorite(send.cardId, send.value);
      if (result.ok) outcome = { ok: true, value: result.favorite };
      else {
        outcome = { ok: false };
        reason = result.reason;
      }
    } catch {
      // Rede/servidor indisponível: mesmo tratamento de uma falha do banco.
      outcome = { ok: false };
    }

    const current = entries.current.get(send.cardId) ?? initialFavoriteEntry(send.value);
    const step = settleCardFavorite(send.cardId, current, outcome);
    entries.current.set(send.cardId, step.entry);
    paint(send.cardId, step.entry);

    if (step.reverted) {
      const message = favoriteErrorMessage(cardName, reason);
      if (onFeedback) onFeedback({ tone: "error", text: message });
      else setError(message);
    } else if (step.send) {
      void write(step.send, cardName);
    } else {
      setAnnouncement(favoriteAnnouncement(cardName, step.entry.confirmed));
      // Página de favoritos: a carta desfavoritada sai da grade; se voltar ("Desfazer"),
      // nasce do estado do servidor (`aria-pressed`), não de uma intenção antiga.
      if (mode === "favorites" && !step.entry.confirmed) entries.current.delete(send.cardId);
      onConfirmed?.(send.cardId, step.entry.confirmed);
    }
  }

  function onClick(event: MouseEvent<HTMLDivElement>) {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-card-fav]");
    if (!button || button.disabled || !rootRef.current?.contains(button)) return;
    // O coração nunca abre a carta nem dispara a seleção do tile.
    event.preventDefault();
    event.stopPropagation();

    const cardId = normalizeId(button.dataset.cardFav);
    if (!cardId) return;
    const cardName = favoriteCardNameFromLabel(button.getAttribute("aria-label")) ?? "Carta";

    const current = entries.current.get(cardId) ?? initialFavoriteEntry(button.getAttribute("aria-pressed") === "true");
    const step = toggleCardFavorite(cardId, current);
    entries.current.set(cardId, step.entry);
    paint(cardId, step.entry);
    setError(null);
    if (step.send) void write(step.send, cardName);
  }

  return (
    <div ref={rootRef} onClickCapture={onClick} className={className}>
      {children}
      <p className="sr-only" aria-live="polite">
        {announcement}
      </p>
      {error ? (
        <div className="pointer-events-none sticky bottom-4 z-20 mt-6 flex justify-center" role="alert">
          <div className="pointer-events-auto max-w-md bg-surface shadow-lg">
            <InlineFeedback tone="error">{error}</InlineFeedback>
          </div>
        </div>
      ) : null}
    </div>
  );
}
