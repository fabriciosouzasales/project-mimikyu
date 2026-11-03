"use client";

import { useCallback, useId, useRef, useState } from "react";
import { Bookmark, Loader2 } from "lucide-react";
import { readSpeciesWishCards } from "@/app/colecoes/lista-de-desejos/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import {
  type SpeciesWishCard,
  appendSpeciesCards,
  nextSpeciesCardsOffset,
} from "@/lib/wishlist/wishlist";
import { CARD_GRID_SIZES, CardArt } from "../colecoes/acervo/card-art";
import acervoStyles from "../colecoes/acervo/acervo.module.css";
import { WishButton, wishHostClass } from "./wish-button";
import { WishlistController } from "./wishlist-controller";
import styles from "./wishlist.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

type State =
  | { status: "closed" }
  | { status: "loading" }
  | { status: "error" }
  | { status: "ready"; items: SpeciesWishCard[]; total: number; wished: ReadonlySet<string>; loadingMore: boolean; moreFailed: boolean };

/**
 * Lista de desejos a partir da Pokédex (V1-11 W4, lacuna L3) — escolha EXPLÍCITA da
 * carta de uma espécie. Divulgação progressiva: fechada é só um botão; aberta lista as
 * cartas ativas da espécie (5349, paginada), cada uma com o marcador por carta da W1:
 * uma variante ativa → inclusão direta ("qualquer idioma"); várias → escolha explícita
 * da variante; remoção pela regra da W1 (bloqueada com mais de um desejo).
 *
 * Nunca escolhe carta pela espécie, nunca grava nada ao abrir e não liga o desejo à
 * Pokédex nem à coleção (C-211): o componente só conhece a espécie para LER as cartas.
 * Uma leitura por página aberta (cartas + estado em lote), nunca por posição da grade.
 */
export function SpeciesWishPicker({ speciesId, speciesName }: { speciesId: string; speciesName: string }) {
  const headingId = useId();
  const [state, setState] = useState<State>({ status: "closed" });
  const requestRef = useRef(0);

  const loadFirst = useCallback(async () => {
    const ticket = ++requestRef.current;
    setState({ status: "loading" });
    const result = await readSpeciesWishCards(speciesId, 0).catch(() => null);
    if (ticket !== requestRef.current) return;
    setState(
      result
        ? { status: "ready", items: result.items, total: result.total, wished: new Set(result.wished), loadingMore: false, moreFailed: false }
        : { status: "error" },
    );
  }, [speciesId]);

  const loadMore = useCallback(async () => {
    if (state.status !== "ready" || state.loadingMore) return;
    const offset = nextSpeciesCardsOffset(state.items.length, state.total);
    if (offset === null) return;
    const ticket = requestRef.current;
    setState({ ...state, loadingMore: true, moreFailed: false });
    const result = await readSpeciesWishCards(speciesId, offset).catch(() => null);
    if (ticket !== requestRef.current) return;
    setState((prev) => {
      if (prev.status !== "ready") return prev;
      if (!result) return { ...prev, loadingMore: false, moreFailed: true };
      return {
        ...prev,
        items: appendSpeciesCards(prev.items, result.items),
        total: result.total || prev.total,
        wished: new Set([...prev.wished, ...result.wished]),
        loadingMore: false,
      };
    });
  }, [speciesId, state]);

  // O controlador da W1 confirma o conjunto final de variantes desejadas da carta.
  const onCardConfirmed = useCallback((cardId: string, variantIds: string[]) => {
    setState((prev) => {
      if (prev.status !== "ready") return prev;
      const wished = new Set(prev.wished);
      if (variantIds.length > 0) wished.add(cardId);
      else wished.delete(cardId);
      return { ...prev, wished };
    });
  }, []);

  if (state.status === "closed") {
    return (
      <section className={styles.speciesWish} aria-labelledby={headingId}>
        <h3 id={headingId} className="sr-only">
          Lista de desejos
        </h3>
        <Button variant="outline" className="min-h-11 self-start" onClick={() => void loadFirst()}>
          <Bookmark className="mr-1.5 h-4 w-4" aria-hidden="true" />
          Desejar uma carta de {speciesName}
        </Button>
      </section>
    );
  }

  return (
    <section className={styles.speciesWish} aria-labelledby={headingId} aria-busy={state.status === "loading" || undefined}>
      <div className={styles.speciesWishHead}>
        <h3 id={headingId} className={styles.speciesWishTitle}>
          Qual carta de {speciesName} você deseja?
        </h3>
        {state.status === "ready" && state.total > 0 ? (
          <span className={styles.speciesWishMeta}>
            {formatCount(state.total)} {state.total === 1 ? "carta" : "cartas"}
          </span>
        ) : null}
      </div>

      {state.status === "loading" ? (
        <p className={styles.speciesWishHint} role="status">
          <Loader2 className="mr-1.5 inline h-4 w-4 animate-spin" aria-hidden="true" />
          Buscando as cartas de {speciesName}…
        </p>
      ) : state.status === "error" ? (
        <div className="flex flex-col items-start gap-2">
          <InlineFeedback tone="error">Não conseguimos carregar as cartas de {speciesName} agora. Nada foi alterado.</InlineFeedback>
          <Button variant="outline" size="sm" onClick={() => void loadFirst()}>
            Tentar novamente
          </Button>
        </div>
      ) : state.items.length === 0 ? (
        <p className={styles.speciesWishHint} role="status">
          Ainda não há cartas de {speciesName} disponíveis no catálogo para a lista de desejos.
        </p>
      ) : (
        <>
          <p className={styles.speciesWishHint}>
            Marque a carta que você quer. Se ela tiver mais de uma variante, você escolhe qual — vale qualquer idioma.
          </p>
          <WishlistController onCardConfirmed={onCardConfirmed}>
            <ul className={styles.speciesWishGrid} aria-label={`Cartas de ${speciesName}`}>
              {state.items.map((card) => (
                <li key={card.cardId}>
                  <SpeciesCardTile card={card} wished={state.wished.has(card.cardId)} />
                </li>
              ))}
            </ul>
          </WishlistController>
          {state.moreFailed ? (
            <InlineFeedback tone="error">Não conseguimos carregar mais cartas agora. Tente de novo.</InlineFeedback>
          ) : null}
          {nextSpeciesCardsOffset(state.items.length, state.total) !== null ? (
            <Button
              variant="outline"
              className="min-h-11 self-start"
              onClick={() => void loadMore()}
              disabled={state.loadingMore}
              aria-busy={state.loadingMore || undefined}
            >
              {state.loadingMore ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
              {state.loadingMore ? "Carregando…" : `Mostrar mais (${formatCount(state.items.length)} de ${formatCount(state.total)})`}
            </Button>
          ) : null}
        </>
      )}
    </section>
  );
}

function SpeciesCardTile({ card, wished }: { card: SpeciesWishCard; wished: boolean }) {
  const number = card.collectorNumber ? formatCollectorNumber(card.collectorNumber, card.collectorTotal) : null;
  const caption = [card.setCode?.toUpperCase(), number].filter(Boolean).join(" · ");
  const imageUrl = cardFrontUrl(SUPABASE_URL, card.imagePathPt ?? card.imagePathEn);
  return (
    <article className={`${acervoStyles.tile} ${wishHostClass}`} aria-label={[card.name, caption, card.setName].filter(Boolean).join(", ")}>
      <div className={acervoStyles.artWrap}>
        <div className={acervoStyles.art}>
          <CardArt src={imageUrl} alt="" name={card.name} caption={caption || card.name} sizes={CARD_GRID_SIZES} />
        </div>
        <WishButton cardId={card.cardId} cardName={caption ? `${card.name} (${caption})` : card.name} isWished={wished} />
      </div>
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{card.name}</div>
        {caption ? <div className={acervoStyles.sub}>{caption}</div> : null}
      </div>
    </article>
  );
}
