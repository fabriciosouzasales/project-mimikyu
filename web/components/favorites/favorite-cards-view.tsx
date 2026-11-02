"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { setCardFavorite } from "@/app/colecoes/favoritos/actions";
import { AlertCircle, Heart, Search } from "lucide-react";
import { CardImagePreview } from "@/components/card/card-image-preview";
import { CardPreviewOverlay } from "@/components/card/card-preview-overlay";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import colecoesStyles from "@/components/colecoes/colecoes/colecoes.module.css";
import regionStyles from "@/components/colecoes/colecoes/library-modes.module.css";
import { favoriteHostClass } from "@/components/favorites/card-favorite-button";
import { CardFavoritesController } from "@/components/favorites/card-favorites-controller";
import { CardPriceSummary } from "@/components/card/card-price-summary";
import { CARD_GRID_SIZES, CardArt } from "@/components/colecoes/acervo/card-art";
import { CardFavoriteButton } from "@/components/favorites/card-favorite-button";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { usePricingBatch } from "@/hooks/use-pricing-batch";
import { formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import {
  type FavoriteReferenceValue,
  type FavoritesKpi,
  favoriteAnnouncement,
  favoriteErrorMessage,
  favoritesKpis,
  formatBrlWhole,
  visibleFavoriteCards,
} from "@/lib/favorites/card-favorites";
import { cardImageUrl, type PesquisaCard } from "@/lib/pesquisa/format";
import type { PricingCacheEntry } from "@/lib/pricing/pricing-batch-client";
import { canUseViewTransitions, cardImagePreviewTransitionName } from "@/lib/view-transitions";
import styles from "./card-favorite.module.css";

/** Carta da página de favoritos no formato do tile da Pesquisa. */
export type FavoriteCardView = PesquisaCard;

/**
 * Cartas favoritas (V1-10; hero refeito na PREMIUM HERO & KPI REFINEMENT-07).
 *
 * Mesmo palco de Minhas coleções (`library-view.tsx`): classes `hero`/`libraryHero`,
 * numeral de contorno com o total, elemento cenográfico de traço fino à direita e o
 * painel de números (`ledger`) com quatro indicadores, na mesma escala e com as mesmas
 * divisórias. Sem botão no palco — a ação "Pesquisar cartas" vive só no estado vazio.
 * Abaixo, a região editorial de Minhas coleções (`library-modes .region`) com a grade.
 *
 * Indicadores (regra pura em `favoritesKpis`): só números sustentados por contrato
 * aprovado; os pendentes aparecem como "—" com o motivo, nunca como zero.
 *
 * A grade usa colunas de largura própria (auto-fill). Cada carta é o tile da Pesquisa com
 * o mesmo coração. HOMOLOGATION-04: desfavoritar atenua a carta enquanto grava; quando o
 * banco confirma, ela sai da grade e a página é relida do servidor (total e indicadores
 * corretos); "Desfazer" refavorita e recoloca a carta sem recarregar. Falha = carta volta
 * ao normal + mensagem (nada some sem confirmação).
 */
export function FavoriteCardsView({
  cards,
  totalCount,
  referenceValue,
  ownedCount,
  favoriteCardSetCount,
  page,
  totalPages,
}: {
  /** `null` = leitura indisponível. */
  cards: FavoriteCardView[] | null;
  totalCount: number;
  /** Valor de referência com cobertura (5340); `null` = leitura indisponível. */
  referenceValue: FavoriteReferenceValue | null;
  /** Favoritas que o usuário possui (5339); `null` = leitura indisponível. */
  ownedCount: number | null;
  /** Card Sets com cartas favoritas (5338); `null` = leitura indisponível. */
  favoriteCardSetCount: number | null;
  page: number;
  totalPages: number;
}) {
  const pricingByCard = usePricingBatch((cards ?? []).map((card) => card.id));
  const [zoomCard, setZoomCard] = useState<FavoriteCardView | null>(null);
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const [hidden, setHidden] = useState<ReadonlySet<string>>(() => new Set());
  const [restored, setRestored] = useState<readonly FavoriteCardView[]>([]);
  const [lastRemoved, setLastRemoved] = useState<FavoriteCardView | null>(null);
  const [undoing, setUndoing] = useState(false);
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);
  const visible = cards === null ? null : visibleFavoriteCards(cards, hidden, restored);
  const hasFavorites = cards !== null && totalCount > 0;

  function refresh() {
    startRefresh(() => router.refresh());
  }

  function toggleHidden(cardId: string, on: boolean) {
    setHidden((prev) => {
      const next = new Set(prev);
      if (on) next.add(cardId.toLowerCase());
      else next.delete(cardId.toLowerCase());
      return next;
    });
  }

  /** Chamado pelo controlador só depois que o servidor confirma o estado final. */
  function onFavoriteConfirmed(cardId: string, isFavorite: boolean) {
    if (isFavorite) return;
    const card = (visible ?? []).find((item) => item.id.toLowerCase() === cardId.toLowerCase()) ?? null;
    toggleHidden(cardId, true);
    setLastRemoved(card);
    setError(null);
    refresh();
  }

  async function undo(card: FavoriteCardView) {
    if (undoing) return;
    setUndoing(true);
    setError(null);
    let reason: Parameters<typeof favoriteErrorMessage>[1] = "failed";
    let ok = false;
    try {
      const result = await setCardFavorite(card.id, true);
      ok = result.ok && result.favorite;
      if (!result.ok) reason = result.reason;
    } catch {
      ok = false;
    }
    setUndoing(false);
    if (ok) {
      setRestored((prev) => [card, ...prev.filter((item) => item.id.toLowerCase() !== card.id.toLowerCase())]);
      toggleHidden(card.id, false);
      setLastRemoved(null);
      setAnnouncement(favoriteAnnouncement(card.name, true));
      refresh();
    } else {
      setError(favoriteErrorMessage(card.name, reason));
    }
  }

  return (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${colecoesStyles.libraryHero}`}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <HeroFavoriteCards />
        {hasFavorites ? (
          <span className={acervoStyles.numeral} aria-hidden="true">
            {formatCount(totalCount)}
          </span>
        ) : null}
        <div className={acervoStyles.heroContent}>
          <h1 className={acervoStyles.title}>Cartas favoritas</h1>
          <p className={acervoStyles.lede}>Suas cartas preferidas, reunidas em um só lugar.</p>
        </div>
        {hasFavorites ? (
          <div className={acervoStyles.heroRow}>
            <FavoritesLedger kpis={favoritesKpis({
                favoriteCount: totalCount,
                referenceValue,
                ownedCount,
                favoriteCardSetCount,
                format: formatCount,
                formatMoney: formatBrlWhole,
              })} />
          </div>
        ) : null}
      </header>

      <div className={regionStyles.region}>
        {cards === null ? (
          <section className={acervoStyles.state} aria-labelledby="favoritos-erro">
            <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
              <AlertCircle className="h-6 w-6" />
            </div>
            <h2 id="favoritos-erro" className={acervoStyles.stateTitle}>
              Não foi possível carregar suas cartas favoritas
            </h2>
            <p className={acervoStyles.stateText}>Seus favoritos estão guardados. Recarregue a página para tentar de novo.</p>
            <div className={acervoStyles.stateActions}>
              <Button asChild variant="outline" className={acervoStyles.stateAction}>
                <a href={page > 1 ? `/colecoes/favoritos?pagina=${page}` : "/colecoes/favoritos"}>Tentar novamente</a>
              </Button>
            </div>
          </section>
        ) : visible === null ? null : visible.length === 0 && page === 1 && totalCount <= hidden.size ? (
          <section className={acervoStyles.state} aria-labelledby="favoritos-vazio">
            <div className={`${acervoStyles.stateIcon} ${styles.stateIconFavorite}`} aria-hidden="true">
              <Heart className="h-6 w-6" />
            </div>
            <h2 id="favoritos-vazio" className={acervoStyles.stateTitle}>
              Nenhuma carta favorita ainda
            </h2>
            <p className={acervoStyles.stateText}>
              Toque no coração de qualquer carta — na Pesquisa ou no seu acervo — para reuni-la aqui. Vale também para cartas
              que você ainda não tem.
            </p>
            <div className={acervoStyles.stateActions}>
              <Button asChild className={acervoStyles.stateAction}>
                <Link href="/pesquisa">
                  <Search className="h-4 w-4" aria-hidden="true" />
                  Pesquisar cartas
                </Link>
              </Button>
            </div>
          </section>
        ) : visible.length === 0 ? (
          <section className={acervoStyles.state} aria-labelledby="favoritos-pagina-vazia">
            <h2 id="favoritos-pagina-vazia" className={acervoStyles.stateTitle}>
              Esta página não tem cartas
            </h2>
            <p className={acervoStyles.stateText}>Sua lista mudou desde a última visita.</p>
            <div className={acervoStyles.stateActions}>
              <Button asChild variant="outline" className={acervoStyles.stateAction}>
                <Link href="/colecoes/favoritos">Voltar ao início</Link>
              </Button>
            </div>
          </section>
        ) : (
          <>
            <CardFavoritesController mode="favorites" onConfirmed={onFavoriteConfirmed}>
              <ul className={acervoStyles.grid} aria-label="Suas cartas favoritas">
                {visible.map((card) => (
                  <FavoriteCardTile
                    key={card.id}
                    card={card}
                    pricingEntry={pricingByCard.get(card.id)}
                    onZoom={() => setZoomCard(card)}
                  />
                ))}
              </ul>
            </CardFavoritesController>

            {totalPages > 1 ? (
              <nav className={acervoStyles.pagination} aria-label="Páginas de favoritos">
                {page > 1 ? (
                  <Button asChild variant="outline" size="sm">
                    <Link href={`/colecoes/favoritos?pagina=${page - 1}`}>Anterior</Link>
                  </Button>
                ) : null}
                <span>
                  Página {page} de {totalPages}
                </span>
                {page < totalPages ? (
                  <Button asChild variant="outline" size="sm">
                    <Link href={`/colecoes/favoritos?pagina=${page + 1}`}>Próxima</Link>
                  </Button>
                ) : null}
              </nav>
            ) : null}
          </>
        )}
      </div>

      <p className="sr-only" aria-live="polite">
        {announcement}
      </p>
      {lastRemoved || error ? (
        <div className="pointer-events-none sticky bottom-4 z-20 mt-6 flex justify-center">
          <div className="pointer-events-auto max-w-md bg-surface shadow-lg" role={error ? "alert" : undefined}>
            {error ? (
              <InlineFeedback tone="error">{error}</InlineFeedback>
            ) : lastRemoved ? (
              <InlineFeedback tone="success">
                <span className="inline-flex flex-wrap items-center gap-3">
                  {lastRemoved.name} saiu dos favoritos.
                  <Button type="button" variant="outline" size="sm" disabled={undoing} onClick={() => void undo(lastRemoved)}>
                    {undoing ? "Desfazendo…" : "Desfazer"}
                  </Button>
                </span>
              </InlineFeedback>
            ) : null}
          </div>
        </div>
      ) : null}

      <CardPreviewOverlay
        open={Boolean(zoomCard)}
        onClose={() => setZoomCard(null)}
        title={zoomCard?.name ?? "Carta"}
        useViewTransition={canUseViewTransitions()}
      >
        {zoomCard ? (
          <CardImagePreview
            imageUrl={cardImageUrl(zoomCard)}
            alt={zoomCard.name}
            viewTransitionName={cardImagePreviewTransitionName(zoomCard.id)}
          />
        ) : null}
      </CardPreviewOverlay>
    </div>
  );
}

/**
 * Painel de números — o mesmo `ledger` de Minhas coleções e Meu acervo (quatro colunas,
 * total em destaque, fio dourado no topo, divisórias finas, 2 × 2 em telas estreitas).
 * Indicador sem dado: "—" com o motivo na linha de apoio e nome acessível explícito.
 */
function FavoritesLedger({ kpis }: { kpis: FavoritesKpi[] }) {
  return (
    <dl className={`${acervoStyles.ledger} ${styles.favLedger}`} aria-label="Resumo das cartas favoritas">
      {kpis.map((kpi) => (
        <div
          key={kpi.key}
          className={[
            acervoStyles.ledgerItem,
            kpi.lead ? acervoStyles.ledgerLead : "",
            kpi.value === null ? styles.ledgerPending : "",
          ]
            .filter(Boolean)
            .join(" ")}
        >
          <dt className={acervoStyles.ledgerLabel}>
            <span className={acervoStyles.ledgerName}>{kpi.name}</span>
            <span className={acervoStyles.ledgerHint}>{kpi.hint}</span>
          </dt>
          <dd className={acervoStyles.ledgerValue}>
            {kpi.value === null ? (
              <>
                <span aria-hidden="true">—</span>
                <span className="sr-only">indisponível</span>
              </>
            ) : (
              kpi.value
            )}
          </dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Elemento cenográfico do palco (equivale à estante de Minhas coleções e ao leque de
 * Meu acervo): duas cartas em leque com um coração de traço fino. Mesma cor e
 * opacidade baixa do `heroShelf`; independe de quantas favoritas existem.
 */
function HeroFavoriteCards() {
  return (
    <svg className={colecoesStyles.heroShelf} viewBox="0 0 520 300" fill="none" aria-hidden="true" focusable="false">
      <g stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
        <rect x="150" y="40" width="150" height="208" rx="12" transform="rotate(-12 225 144)" />
        <rect x="250" y="34" width="150" height="208" rx="12" transform="rotate(8 325 138)" />
        <rect x="262" y="48" width="126" height="92" rx="6" transform="rotate(8 325 138)" />
        <path
          d="M325 230c-22-14-38-27-38-44 0-11 8-19 18-19 8 0 15 5 20 12 5-7 12-12 20-12 10 0 18 8 18 19 0 17-16 30-38 44z"
          transform="rotate(8 325 138)"
        />
      </g>
    </svg>
  );
}

/**
 * Carta favorita — CARD GRID UX STANDARDIZATION-01: mesma anatomia das grades do
 * módulo Coleções (arte 8:11, preço na base da arte, nome, Set · número). Contexto
 * próprio preservado: a arte amplia a carta (preview), o coração fica no canto e o
 * preço é o resumo por carta da Pesquisa (abre o detalhe), não o NM de uma variante.
 */
function FavoriteCardTile({
  card,
  pricingEntry,
  onZoom,
}: {
  card: FavoriteCardView;
  pricingEntry: PricingCacheEntry | undefined;
  onZoom: () => void;
}) {
  const caption = `${card.cardSet.code.toUpperCase()} · ${formatCollectorNumber(card.collectorNumber, card.collectorTotal)}`;
  return (
    <li data-fav-item className={`${acervoStyles.tileSlot} ${favoriteHostClass}`}>
      <div className={acervoStyles.artWrap}>
        <button type="button" onClick={onZoom} className={`${acervoStyles.tile} w-full text-left`} aria-label={`Ampliar ${card.name}, ${caption}`}>
          <div className={acervoStyles.art}>
            <CardArt src={cardImageUrl(card)} alt="" name={card.name} caption={caption} sizes={CARD_GRID_SIZES} />
          </div>
        </button>
        <CardPriceSummary cardId={card.id} cardName={card.name} entry={pricingEntry} className={styles.artPrice} />
      </div>
      <CardFavoriteButton cardId={card.id} cardName={card.name} isFavorite />
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{card.name}</div>
        <div className={acervoStyles.sub}>
          <span>{caption}</span>
        </div>
      </div>
    </li>
  );
}
