import Link from "next/link";
import { ArrowLeft, ChevronLeft, ChevronRight, Globe2, Trophy } from "lucide-react";
import { CardZoomProvider, CardZoomTrigger } from "@/components/card/card-zoom";
import { BinderCoverLink } from "@/components/colecoes/fichario/binder-entry";
import { PRIORITY_CARD_COUNT, cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import { resolveFinish } from "@/lib/colecoes/binder-finish";
import {
  COLECOES_PATH,
  type HeroCardSource,
  collectionKindLabel,
  missingCount,
  pickHeroCards,
  progressBarPercent,
  progressPercentText,
} from "@/lib/colecoes/colecoes";
import {
  SHARED_PAGE_SIZE,
  type SharedBinderIdentity,
  type SharedCard,
  type SharedCollection,
  type SharedPosition,
  type SharedPositionFilter,
  sharedCollectionHref,
  sharedPositionsHref,
} from "@/lib/colecoes/sharing";
import { CardArt } from "../acervo/card-art";
import { PositionTile } from "../colecoes/collection-view";
import acervoStyles from "../acervo/acervo.module.css";
import { BinderCover } from "../colecoes/binder-cover";
import { CollectionHeroBackdrop, CollectionHeroFan } from "../colecoes/collection-hero-fan";
import heroStyles from "../colecoes/collection-hero.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import { CollectionTitle } from "../colecoes/collection-title";
import styles from "../colecoes/colecoes.module.css";
import shareStyles from "./share.module.css";
import { SharedAccessMenu } from "./leave-shared-collection";
import { SharedBinderEntry } from "./shared-binder-entry";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";

/**
 * Coleção vista pelo participante VIEWER (V1-12; paridade visual em SHARED
 * EXPERIENCE-01). Mesma composição da página do titular (`CollectionView`):
 * palco com fundo tingido pela carta-destaque, capa 3D do fichário na
 * identidade, título/linha do Set, progresso, entrada do fichário e leque
 * de destaques — as MESMAS peças e os mesmos módulos CSS, sem cópia de
 * layout. Muda só o que é permissão: no lugar de Compartilhar/Ajustes, o
 * selo de acesso com menu (titular, o que a visualização permite e "Sair
 * desta coleção"); nenhum controle de escrita.
 *
 * O fichário abre na mesma sobreposição imersiva do titular
 * (`SharedBinderEntry` → `BinderOverlayShell`), em modo só leitura.
 *
 * Server Component: os dados já chegam filtrados pelo banco (5312/5313/5314).
 * O leque usa as cartas da página atual da galeria (5313) — nenhuma leitura
 * extra e nada do acervo privado do titular.
 */
export function SharedCollectionView({
  collection,
  cards,
  page,
  logoUrl,
  coverCode = null,
  signedIn,
  binder = null,
  positions = null,
}: {
  collection: SharedCollection;
  cards: { items: SharedCard[]; total: number } | null;
  page: number;
  logoUrl: string | null;
  /** Código da capa da própria coleção (5328) — na capa, como na página do titular. */
  coverCode?: string | null;
  signedIn: boolean;
  /** Fichário visível ao participante (5314); `null` = sem fichário ou sem acesso a ele. */
  binder?: { columns: number; rows: number; pageCount: number; ownFilled: number; identity: SharedBinderIdentity | null } | null;
  /**
   * Grade Todas · Tenho · Faltam (5320). `null` = coleção sem Set de
   * referência ou contrato ainda ausente → galeria de cartas alocadas (5313).
   */
  positions?: {
    filter: SharedPositionFilter;
    page: { items: SharedPosition[]; total: number } | null;
    hero: readonly SharedPosition[];
  } | null;
}) {
  const progress = collection.progress && collection.progress.total > 0 ? collection.progress : null;
  const pages = cards ? Math.max(1, Math.ceil(cards.total / SHARED_PAGE_SIZE)) : 1;
  const viewer = collection.access === "VIEWER";
  const finish = resolveFinish(collection.collectionId, collection.coverFinish);
  const complete = Boolean(progress?.complete);
  const hero = positions
    ? pickHeroCards(positions.hero.map(positionHeroSource), 5, collection.cardSetCode)
    : pickHeroCards((cards?.items ?? []).map(heroSource), 5, collection.cardSetCode);
  const setCode = collection.cardSetCode;

  return (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${heroStyles.hero}`} data-has-fan={hero.cards.length > 0 || undefined}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <CollectionHeroBackdrop selection={hero} />
        <div className={`${manageStyles.heroBar} ${shareStyles.heroBarRaised}`}>
          {signedIn ? (
            <Link href={COLECOES_PATH} className={styles.backLink}>
              <ArrowLeft className="h-4 w-4" aria-hidden="true" />
              Minhas coleções
            </Link>
          ) : (
            <span />
          )}
          <div className={manageStyles.heroBarActions}>
            {viewer ? (
              <SharedAccessMenu collectionId={collection.collectionId} collectionName={collection.name} ownerDisplayName={collection.ownerDisplayName} />
            ) : (
              <span className={shareStyles.accessBadge}>
                <Globe2 aria-hidden="true" />
                Coleção pública · somente visualização
              </span>
            )}
          </div>
        </div>
        <div className={heroStyles.stage}>
          <div className={heroStyles.text}>
            <div className={heroStyles.identity}>
              <div className={heroStyles.identityCover}>
                <BinderCoverLink collectionId={collection.collectionId} ready={Boolean(binder && binder.pageCount > 0)} available={false}>
                  <BinderCover
                    finish={finish}
                    setName={collection.cardSetName}
                    setCode={coverCode ?? setCode}
                    logoUrl={logoUrl}
                    fallbackTitle={collection.name}
                    complete={complete}
                    size="compact"
                    priority
                  />
                </BinderCoverLink>
              </div>
              <div className={heroStyles.identityText}>
                <div className={heroStyles.title}>
                  <CollectionTitle name={collection.name} archived={collection.archived} />
                </div>
                <p className={heroStyles.setLine}>
                  {setCode ? <span className={heroStyles.setCode}>{setCode.toUpperCase()}</span> : null}
                  {collection.cardSetName && collection.cardSetName !== collection.name ? <strong>{collection.cardSetName}</strong> : null}
                  <span>{collectionKindLabel(collection.completionPolicy)}</span>
                </p>
                <p className={shareStyles.ownerLine}>
                  Coleção de <strong>{collection.ownerDisplayName}</strong>
                </p>
              </div>
            </div>
            {collection.description ? <p className={shareStyles.lead}>{collection.description}</p> : null}

            {progress ? (
              <section className={heroStyles.progress} aria-label="Progresso da coleção">
                <div className={styles.progressFigure}>
                  <span className={heroStyles.progressBig}>{formatCount(progress.satisfied)}</span>
                  <span className={styles.progressOf}>de {formatCount(progress.total)}</span>
                  <span className={styles.progressPct}>{progress.complete ? "100%" : progressPercentText(progress.satisfied, progress.total)}</span>
                </div>
                <div
                  className={`${styles.track} ${heroStyles.track}`}
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={progress.total}
                  aria-valuenow={progress.satisfied}
                  aria-valuetext={`${formatCount(progress.satisfied)} de ${formatCount(progress.total)}`}
                >
                  <div
                    className={progress.complete ? `${styles.fill} ${styles.fillComplete}` : styles.fill}
                    style={{ width: `${progressBarPercent(progress.satisfied, progress.total)}%` }}
                  />
                </div>
                <div className={styles.progressFoot}>
                  {progress.complete ? (
                    <span className={styles.completeNote}>
                      <Trophy className="h-4 w-4" aria-hidden="true" />
                      Completa
                    </span>
                  ) : (
                    <span>
                      Faltam <strong>{formatCount(missingCount(progress.satisfied, progress.total))}</strong>
                    </span>
                  )}
                  <span>
                    <strong>{formatCount(collection.copies)}</strong> {collection.copies === 1 ? "carta" : "cartas"} na coleção
                  </span>
                </div>
              </section>
            ) : (
              <section className={heroStyles.progress} aria-label="Resumo da coleção">
                <div className={styles.progressFigure}>
                  <span className={heroStyles.progressBig}>{formatCount(collection.copies)}</span>
                  <span className={styles.progressOf}>{collection.copies === 1 ? "carta na coleção" : "cartas na coleção"}</span>
                </div>
              </section>
            )}

            {viewer && binder ? (
              <SharedBinderEntry
                collectionId={collection.collectionId}
                collectionName={collection.name}
                ownerDisplayName={collection.ownerDisplayName}
                finish={finish}
                binder={binder}
              />
            ) : null}

          </div>

          <CollectionHeroFan selection={hero} />
        </div>
      </header>

      {positions ? (
        <PositionsGallery collection={collection} positions={positions} />
      ) : (
      <section className={heroStyles.gallery} aria-labelledby="compartilhada-cartas">
        <div className={heroStyles.galleryHead}>
          <div className={heroStyles.galleryHeadText}>
            <h2 id="compartilhada-cartas" className={heroStyles.galleryTitle}>
              Cartas da coleção
            </h2>
            {cards && cards.total > 0 ? (
              <p className={heroStyles.galleryMeta}>
                {formatCount(cards.total)} {cards.total === 1 ? "carta diferente" : "cartas diferentes"} · as mais recentes primeiro
              </p>
            ) : null}
          </div>
        </div>

        {cards === null ? (
          <p className="py-12 text-center text-sm text-muted-foreground" role="alert">
            Não conseguimos carregar as cartas agora. Recarregue a página em instantes.
          </p>
        ) : cards.items.length === 0 ? (
          <p className="py-12 text-center text-sm text-muted-foreground">
            {page > 1 ? "Não há mais cartas nesta página." : "Esta coleção ainda não tem cartas."}
          </p>
        ) : (
          <>
            <CardZoomProvider>
              <ul className={acervoStyles.grid} aria-label="Cartas da coleção">
                {cards.items.map((card, index) => (
                  <li key={`${card.cardVariantId}.${card.languageCode}`}>
                    <SharedTile card={card} priority={page === 1 && index < PRIORITY_CARD_COUNT} />
                  </li>
                ))}
              </ul>
            </CardZoomProvider>
            {pages > 1 ? (
              <nav className="mt-8 flex items-center justify-center gap-3 text-sm" aria-label="Páginas da coleção">
                {page > 1 ? (
                  <Link href={sharedCollectionHref(collection.collectionId, page - 1)} className={styles.backLink} aria-label="Página anterior">
                    <ChevronLeft className="h-4 w-4" aria-hidden="true" />
                    Anterior
                  </Link>
                ) : null}
                <span className="text-muted-foreground">
                  Página {page} de {pages}
                </span>
                {page < pages ? (
                  <Link href={sharedCollectionHref(collection.collectionId, page + 1)} className={styles.backLink} aria-label="Próxima página">
                    Próxima
                    <ChevronRight className="h-4 w-4" aria-hidden="true" />
                  </Link>
                ) : null}
              </nav>
            ) : null}
          </>
        )}
      </section>
      )}
    </div>
  );
}

function SharedTile({ card, priority }: { card: SharedCard; priority: boolean }) {
  const number = formatCollectorNumber(card.collectorNumber, card.collectorTotal);
  const caption = `${card.cardSetCode.toUpperCase()} · ${number}`;
  const imageUrl = cardFrontUrl(SUPABASE_URL, card.imagePath);
  const spoken = [card.cardName, caption, card.variantLabel, card.languageCode, `${card.copies} ${card.copies === 1 ? "exemplar" : "exemplares"}`]
    .filter(Boolean)
    .join(", ");
  return (
    <article className={acervoStyles.tile} aria-label={spoken}>
      <div className={card.copies > 1 ? `${acervoStyles.artWrap} ${acervoStyles.stack}` : acervoStyles.artWrap}>
        <CardZoomTrigger id={`${card.cardVariantId}.${card.languageCode}`} imageUrl={imageUrl} name={card.cardName} className={styles.zoomTrigger}>
          <div className={acervoStyles.art}>
            <CardArt src={imageUrl} alt="" name={card.cardName} caption={caption} priority={priority} sizes={GRID_SIZES} />
          </div>
        </CardZoomTrigger>
        {card.copies > 1 ? (
          <span className={acervoStyles.qty} aria-hidden="true">
            ×{formatCount(card.copies)}
          </span>
        ) : null}
      </div>
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{card.cardName}</div>
        <div className={acervoStyles.sub}>
          <span>{caption}</span>
          {card.variantLabel ? <span className={acervoStyles.tag}>{card.variantLabel}</span> : null}
          <span className={acervoStyles.tag}>{card.languageCode}</span>
        </div>
      </div>
    </article>
  );
}

/** Carta da galeria compartilhada → fonte do leque/fundo do hero (mesma seleção do titular). */
function heroSource(card: SharedCard): HeroCardSource {
  return {
    cardId: `${card.cardVariantId}.${card.languageCode}`,
    cardName: card.cardName,
    collectorNumber: card.collectorNumber,
    collectorTotal: card.collectorTotal,
    imagePath: card.imagePath,
    isSatisfied: true,
  };
}

/**
 * Grade do participante com a MESMA navegação do titular: abas sublinhadas
 * Todas · Tenho · Faltam com contadores (progresso da 5312), ordem do Set e
 * a carta do titular (`PositionTile`) — sem gerenciar exemplares e sem a tag
 * "No seu acervo" (acervo privado do titular não chega aqui).
 */
function PositionsGallery({
  collection,
  positions,
}: {
  collection: SharedCollection;
  positions: { filter: SharedPositionFilter; page: { items: SharedPosition[]; total: number } | null };
}) {
  const total = collection.progress?.total ?? 0;
  const owned = collection.progress?.satisfied ?? 0;
  const segments: { key: SharedPositionFilter; label: string; count: number }[] = [
    { key: "todas", label: "Todas", count: total },
    { key: "tenho", label: "Tenho", count: owned },
    { key: "faltam", label: "Faltam", count: missingCount(owned, total) },
  ];
  const current = segments.find((segment) => segment.key === positions.filter);
  const page = positions.page;
  const shown = page?.total ?? 0;
  const setCode = collection.cardSetCode;
  return (
    <section className={heroStyles.gallery} aria-labelledby="compartilhada-cartas">
      <div className={heroStyles.galleryHead}>
        <div className={heroStyles.galleryHeadText}>
          <h2 id="compartilhada-cartas" className={heroStyles.galleryTitle}>
            Cartas da coleção
          </h2>
          {page !== null ? (
            <p className={heroStyles.galleryMeta}>
              {current?.label} · {formatCount(shown)} {shown === 1 ? "carta" : "cartas"}
            </p>
          ) : null}
        </div>
        <div className={heroStyles.galleryTools}>
          <nav className={styles.filterTabs} aria-label="Mostrar cartas">
            {segments.map((segment) => (
              <Link
                key={segment.key}
                href={sharedPositionsHref(collection.collectionId, segment.key)}
                scroll={false}
                className={styles.filterTab}
                aria-current={segment.key === positions.filter ? "page" : undefined}
              >
                {segment.label}
                <span className={styles.filterTabCount}>{formatCount(segment.count)}</span>
              </Link>
            ))}
          </nav>
        </div>
      </div>

      {page === null ? (
        <p className="py-12 text-center text-sm text-muted-foreground" role="alert">
          Não conseguimos carregar as cartas agora.{" "}
          <Link href={sharedPositionsHref(collection.collectionId, positions.filter)} className="underline underline-offset-2">
            Tentar de novo
          </Link>
        </p>
      ) : page.items.length === 0 ? (
        <p className="py-12 text-center text-sm text-muted-foreground">
          {positions.filter === "faltam"
            ? "Nenhuma carta faltando — esta coleção está completa."
            : positions.filter === "tenho"
              ? "Esta coleção ainda não tem cartas."
              : "Este Set ainda não tem cartas no catálogo."}
        </p>
      ) : (
        <CardZoomProvider>
          <ul className={acervoStyles.grid} aria-label={`Cartas — ${current?.label ?? "Todas"}`}>
            {page.items.map((position, index) => (
              <li key={position.cardId}>
                <PositionTile
                  position={{ ...position, copiesAvailable: 0 }}
                  priority={index < PRIORITY_CARD_COUNT}
                  setCode={setCode}
                  manageable={false}
                />
              </li>
            ))}
          </ul>
        </CardZoomProvider>
      )}
    </section>
  );
}

/** Posição do Set → fonte do leque/fundo do hero (mesma seleção do titular: Set inteiro). */
function positionHeroSource(position: SharedPosition): HeroCardSource {
  return {
    cardId: position.cardId,
    cardName: position.cardName,
    collectorNumber: position.collectorNumber,
    collectorTotal: position.collectorTotal,
    imagePath: position.imagePath,
    isSatisfied: position.isSatisfied,
  };
}
