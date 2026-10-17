import type { CSSProperties } from "react";
import { cardFrontUrl } from "@/lib/colecoes/acervo";
import type { HeroSelection } from "@/lib/colecoes/colecoes";
import type { CollectionPosition } from "@/lib/colecoes/colecoes-queries";
import styles from "./collection-hero.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;

/**
 * Composição editorial do hero da coleção (COLLECTION DETAIL UX REFINEMENT-01):
 * os destaques do Set em leque — a carta de número mais alto à frente, as
 * demais abrindo para os lados, menores e mais giradas. Cartas reais do
 * catálogo (bucket público `card-front`, as mesmas URLs da grade: nenhum
 * download a mais). A arte da carta da frente, desfocada, tinge o palco com a
 * cor do Set.
 *
 * Representa o Set, não a posse: carta que o colecionador ainda não tem fica
 * velada (mesma camada da grade, sem filter). Sem legenda (REFINEMENT-02): a
 * composição é editorial, não um segundo indicador de progresso.
 *
 * Server Component: sem JS no cliente. Entrada em leque só com CSS, desligada
 * em prefers-reduced-motion.
 */

/** Ordem visual dos slots: frente, esquerda, direita, extrema esquerda, extrema direita. */
const SLOT_ORDER = [0, 1, 2, 3, 4] as const;

export function CollectionHeroBackdrop({ selection }: { selection: HeroSelection<CollectionPosition> }) {
  const lead = selection.cards[0];
  const src = lead ? cardFrontUrl(SUPABASE_URL, lead.imagePath) : null;
  if (!src) return null;
  return (
    <span className={styles.backdrop} aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- mesma URL pública da grade (já em cache), só tinge o palco */}
      <img src={src} alt="" width={367} height={512} decoding="async" fetchPriority="low" draggable={false} />
    </span>
  );
}

export function CollectionHeroFan({ selection }: { selection: HeroSelection<CollectionPosition> }) {
  const cards = selection.cards.slice(0, SLOT_ORDER.length);
  if (cards.length === 0) return null;
  const label = selection.secret > 0 ? (selection.secret === 1 ? "Carta secreta do Set" : "Secretas do Set") : "Destaques do Set";
  const names = cards.map((card) => card.cardName).join(", ");

  return (
    <figure className={styles.fan} data-count={cards.length} aria-label={`${label}: ${names}`}>
      <div className={styles.fanStage}>
        {cards.map((card, index) => {
          const src = cardFrontUrl(SUPABASE_URL, card.imagePath);
          return (
            <span
              key={card.cardId}
              className={styles.fanCard}
              data-slot={SLOT_ORDER[index]}
              data-owned={card.isSatisfied || undefined}
              style={{ "--i": index } as CSSProperties}
            >
              {src ? (
                // eslint-disable-next-line @next/next/no-img-element -- asset já otimizado no pipeline, URL pública imutável
                <img
                  src={src}
                  alt=""
                  width={367}
                  height={512}
                  loading={index === 0 ? "eager" : "lazy"}
                  decoding="async"
                  fetchPriority={index === 0 ? "high" : "low"}
                  draggable={false}
                />
              ) : null}
            </span>
          );
        })}
      </div>
    </figure>
  );
}
