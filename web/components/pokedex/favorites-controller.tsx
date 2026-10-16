"use client";

import { type MouseEvent, type ReactNode, useRef, useState } from "react";
import { setPokedexSpeciesFavorite } from "@/app/pokedex/actions";
import { InlineFeedback } from "@/components/ui/feedback";
import {
  type FavoriteEntry,
  type FavoriteFailureReason,
  type FavoriteOutcome,
  type FavoriteSend,
  favoriteAnnouncement,
  favoriteSpeciesNameFromLabel,
  favoriteErrorMessage,
  initialFavoriteEntry,
  settleFavorite,
  toggleFavorite,
} from "@/lib/pokedex/favorites";

/**
 * Ilha controladora dos corações da galeria (Pokédex P6, 2026-10-15).
 *
 * Uma única ilha cliente para os até 1.025 cards: os botões-coração são renderizados no
 * servidor (estado inicial em `aria-pressed`) e este componente escuta os cliques por
 * delegação — nenhum componente cliente por card, nenhuma hidratação extra por card.
 *
 * Por espécie vale a máquina de lib/pokedex/favorites.ts: a tela muda na hora
 * (otimista), uma gravação por vez, e a última intenção é a que fica no servidor.
 * Falha = estado revertido + mensagem inline (STD-004). Os atributos alterados são só os
 * do próprio botão (`aria-pressed`, `data-pending`) e, na página Pokémons
 * Favoritos, `data-fav-removed` no item — o card desfavoritado fica atenuado no lugar,
 * sem salto de layout, até a próxima navegação (D4).
 */
export function FavoritesController({
  children,
  mode,
}: {
  children: ReactNode;
  /** "favorites": página Pokémons Favoritos — desfavoritar atenua o card no lugar. */
  mode: "national" | "favorites";
}) {
  const rootRef = useRef<HTMLDivElement>(null);
  const entries = useRef(new Map<number, FavoriteEntry>());
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);

  function paint(number: number, entry: FavoriteEntry) {
    const root = rootRef.current;
    if (!root) return;
    root.querySelectorAll<HTMLButtonElement>(`button[data-fav="${number}"]`).forEach((button) => {
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

  async function write(send: FavoriteSend, speciesName: string) {
    let outcome: FavoriteOutcome;
    let reason: FavoriteFailureReason = "failed";
    try {
      const result = await setPokedexSpeciesFavorite(send.number, send.value);
      if (result.ok) outcome = { ok: true, value: result.favorite };
      else {
        outcome = { ok: false };
        reason = result.reason;
      }
    } catch {
      // Rede/servidor indisponível: mesmo tratamento de uma falha do banco.
      outcome = { ok: false };
    }

    const current = entries.current.get(send.number) ?? initialFavoriteEntry(send.value);
    const step = settleFavorite(send.number, current, outcome);
    entries.current.set(send.number, step.entry);
    paint(send.number, step.entry);

    if (step.reverted) {
      setError(favoriteErrorMessage(speciesName, reason));
    } else if (step.send) {
      void write(step.send, speciesName);
    } else {
      setAnnouncement(favoriteAnnouncement(speciesName, step.entry.confirmed));
    }
  }

  function onClick(event: MouseEvent<HTMLDivElement>) {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>("button[data-fav]");
    if (!button || button.disabled || !rootRef.current?.contains(button)) return;
    event.preventDefault();

    const number = Number(button.dataset.fav);
    const speciesName = favoriteSpeciesNameFromLabel(button.getAttribute("aria-label")) ?? `Nº ${number}`;
    if (!Number.isInteger(number)) return;

    const current = entries.current.get(number) ?? initialFavoriteEntry(button.getAttribute("aria-pressed") === "true");
    const step = toggleFavorite(number, current);
    entries.current.set(number, step.entry);
    paint(number, step.entry);
    setError(null);
    if (step.send) void write(step.send, speciesName);
  }

  return (
    <div ref={rootRef} onClick={onClick}>
      {children}
      <p className="sr-only" aria-live="polite">
        {announcement}
      </p>
      {error ? (
        // Inline no fluxo da página (STD-004), fixado ao rodapé da galeria para ser visto
        // mesmo com o card longe do topo.
        <div className="pointer-events-none sticky bottom-4 z-20 mt-6 flex justify-center" role="alert">
          <div className="pointer-events-auto max-w-md bg-surface shadow-lg">
            <InlineFeedback tone="error">{error}</InlineFeedback>
          </div>
        </div>
      ) : null}
    </div>
  );
}
