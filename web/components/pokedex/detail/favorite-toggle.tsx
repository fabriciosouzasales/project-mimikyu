"use client";

import { useEffect, useRef, useState } from "react";
import { setPokedexSpeciesFavorite } from "@/app/pokedex/actions";
import { FavoriteHeartIcon } from "@/components/pokedex/favorite-heart";
import { InlineFeedback } from "@/components/ui/feedback";
import {
  type FavoriteEntry,
  type FavoriteFailureReason,
  type FavoriteOutcome,
  type FavoriteSend,
  favoriteActionHint,
  favoriteAnnouncement,
  favoriteErrorMessage,
  favoriteToggleLabel,
  initialFavoriteEntry,
  settleFavorite,
  toggleFavorite,
} from "@/lib/pokedex/favorites";
import styles from "./species-detail.module.css";

/**
 * Coração da ficha da espécie (Pokédex P6, 2026-10-15) — botão de alternância com
 * estado em `aria-pressed`.
 *
 * UX Correction-03 (2026-10-15): botão circular compacto no agrupamento de controles
 * do topo da ficha (antes das setas e do seletor de número), não mais centralizado sob
 * os tipos. Mesmo nome acessível da galeria ("Favoritar Mimikyu" + pressionado/não
 * pressionado); a dica visual (`title`) diz a ação do próximo clique. O estado não
 * depende só da cor: contorno × coração preenchido. A falha aparece como mensagem
 * inline ancorada sob o botão, sem deslocar a composição.
 *
 * Mesma máquina da galeria (lib/pokedex/favorites.ts): muda na hora, uma gravação por
 * vez, a última intenção vence; falha = estado revertido + mensagem inline. O estado
 * inicial vem da mesma leitura agregada da galeria, então ficha e galeria nunca
 * divergem ao navegar entre elas (cada página relê os favoritos).
 *
 * A ficha é reaproveitada pelo App Router ao ir para o anterior/próximo: o estado é
 * reiniciado quando a espécie muda (chave por número no pai).
 */
export function FavoriteToggle({
  nationalDexNumber,
  speciesName,
  initialFavorite,
  available,
}: {
  nationalDexNumber: number;
  speciesName: string;
  initialFavorite: boolean;
  /** `false` = leitura de favoritos indisponível: botão desabilitado com explicação. */
  available: boolean;
}) {
  const [entry, setEntry] = useState<FavoriteEntry>(() => initialFavoriteEntry(initialFavorite));
  const entryRef = useRef(entry);
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);
  const mounted = useRef(true);

  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
    };
  }, []);

  function commit(next: FavoriteEntry) {
    entryRef.current = next;
    if (mounted.current) setEntry(next);
  }

  async function write(send: FavoriteSend) {
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
      outcome = { ok: false };
    }

    const step = settleFavorite(send.number, entryRef.current, outcome);
    commit(step.entry);
    if (!mounted.current) {
      // Saiu da ficha no meio da gravação: a última intenção ainda é enviada.
      if (step.send) void write(step.send);
      return;
    }
    if (step.reverted) setError(favoriteErrorMessage(speciesName, reason));
    else if (step.send) void write(step.send);
    else setAnnouncement(favoriteAnnouncement(speciesName, step.entry.confirmed));
  }

  function onClick() {
    const step = toggleFavorite(nationalDexNumber, entryRef.current);
    commit(step.entry);
    setError(null);
    if (step.send) void write(step.send);
  }

  const pressed = entry.desired;

  return (
    <span className={styles.favoriteSlot}>
      <button
        type="button"
        className={styles.favoriteButton}
        aria-pressed={pressed}
        aria-label={favoriteToggleLabel(speciesName)}
        aria-describedby={available ? undefined : `favorito-indisponivel-${nationalDexNumber}`}
        title={available ? favoriteActionHint(pressed) : "Favoritos indisponíveis no momento"}
        data-pending={entry.inFlight ? "" : undefined}
        disabled={!available}
        onClick={onClick}
      >
        <FavoriteHeartIcon className={styles.favoriteIcon} />
      </button>
      {available ? null : (
        <span id={`favorito-indisponivel-${nationalDexNumber}`} className="sr-only">
          Favoritos indisponíveis no momento.
        </span>
      )}
      <span className="sr-only" aria-live="polite">
        {announcement}
      </span>
      {error ? (
        <div className={styles.favoriteError} role="alert">
          <InlineFeedback tone="error">{error}</InlineFeedback>
        </div>
      ) : null}
    </span>
  );
}
