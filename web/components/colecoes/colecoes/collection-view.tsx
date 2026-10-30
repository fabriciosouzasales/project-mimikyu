import Link from "next/link";
import { BinderCoverLink, BinderEntry } from "@/components/colecoes/fichario/binder-entry";
import { type BinderHeader, binderEntryVisible } from "@/lib/colecoes/binder";
import type { ReactNode } from "react";
import { AlertTriangle, ArrowLeft, Check, Trophy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PRIORITY_CARD_COUNT, cardFrontUrl, formatCollectorNumber, formatCount } from "@/lib/colecoes/acervo";
import {
  COLECOES_PATH,
  type PositionFilter,
  collectionHref,
  collectionKindLabel,
  missingCount,
  pickHeroCards,
  progressBarPercent,
  progressPercentText,
} from "@/lib/colecoes/colecoes";
import type { CollectionPosition, CollectionSummary, PositionsPage } from "@/lib/colecoes/colecoes-queries";
import { CardZoomProvider, CardZoomTrigger } from "@/components/card/card-zoom";
import { CardArt } from "../acervo/card-art";
import acervoStyles from "../acervo/acervo.module.css";
import { BinderCover } from "./binder-cover";
import { CollectionHeroBackdrop, CollectionHeroFan } from "./collection-hero-fan";
import heroStyles from "./collection-hero.module.css";
import { CollectionTitle } from "./collection-title";
import { LinkCardsLauncher } from "./link-cards";
import { COLLECTION_MANAGE_ENABLED } from "@/lib/colecoes/collection-manage";
import { CollectionManageProvider, CollectionSettingsButton, ManageCopiesButton } from "./collection-manage";
import { ReactivateCollectionButton, ReactivatedStatus } from "./collection-lifecycle";
import { CollectionAddLauncher } from "./collection-add";
import type { RegisterMode } from "@/lib/colecoes/collection-add";
import manageStyles from "./collection-manage.module.css";
import { type MasterSetPosition, type MasterSetPositionsPage, heroCardsFromMasterSet } from "@/lib/colecoes/master-set";
import { MasterSetGallery } from "./master-set-gallery";
import { MasterSetLinkLauncher } from "./master-set-link";
import styles from "./colecoes.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";

/**
 * Uma coleção (Server Component): progresso "X de Y" (N10) em destaque, a
 * alternância Todas · Tenho · Faltam na URL (`?ver=`) e o Set inteiro em
 * cartas reais. A carta que falta aparece apagada — e, se o acervo tem uma
 * fora de coleção, a etiqueta diz isso. Repetidas aparecem como contagem
 * (N12), sem inflar o progresso.
 *
 * Ações: "Renomear" (título, 5035) e "Adicionar cartas" (R3 + 5046, na barra da galeria, antes dos filtros), só em coleção ativa e
 * quando existe algo a adicionar — o colecionador escolhe quais cartas entram (uma de cada). Gerenciar (COLLECTION-MANAGEMENT-RECOVERY-01, só coleção ativa):
 * "Ajustes" no topo (identidade em leitura + Onde guardo, 5036) e, em cada carta que você tem, o
 * botão de exemplares para tirar um exemplar específico da coleção (5047).
 */
/** Coleção em Master Set (MASTER-SET-FRONTEND-PHASE-02): grade por posição, paginada. */
export type MasterSetView = {
  positions: MasterSetPositionsPage | null;
  heroPositions: readonly MasterSetPosition[];
  page: number;
  /** `null` = leitura falhou (a seção não aparece). */
  outOfScopeCount: number | null;
  /**
   * Posições faltantes com carta livre no acervo (5200). `null` = recurso
   * desligado ou leitura falhou (inclusive antes da 5200 existir) — o botão
   * "Adicionar cartas" não aparece.
   */
  linkable: number | null;
};

export function CollectionView({
  collection,
  filter,
  positions,
  linkable,
  logoUrl,
  heroPositions,
  master = null,
  binder = null,
  registerMode = null,
}: {
  collection: CollectionSummary;
  /** Cartas do Set inteiro (R2 sem filtro) para os destaques do hero. */
  heroPositions: readonly CollectionPosition[];
  /** Logo do Set assinado; `null` quando a sessão não pode lê-lo. */
  logoUrl: string | null;
  filter: PositionFilter;
  positions: PositionsPage | null;
  /** `null` = leitura falhou (ação some, nada finge funcionar). */
  linkable: number | null;
  /** Só coleção em MASTER_SET; a grade padrão (R2/R3) não se aplica a ela. */
  master?: MasterSetView | null;
  /** Cabeçalho do Fichário Digital (5223); `null` = sem leitura. */
  binder?: BinderHeader | null;
  /** V1-06: `?cadastrar=` — abre o cadastro de cartas novas ao chegar (Fluxo 1.6). */
  registerMode?: RegisterMode | null;
}) {
  const total = collection.totalPositions;
  const owned = collection.satisfiedPositions;
  const missing = missingCount(owned, total);
  const active = collection.lifecycleStatus === "ACTIVE";
  const setCode = collection.cardSetCode;
  const canLink = active && setCode !== null && linkable !== null && linkable > 0;
  const canManage = COLLECTION_MANAGE_ENABLED && active;

  const segments: { key: PositionFilter; label: string; count: number }[] = [
    { key: "todas", label: "Todas", count: total },
    { key: "tenho", label: "Tenho", count: owned },
    { key: "faltam", label: "Faltam", count: missing },
  ];

  const isMaster = master !== null;
  const hero = pickHeroCards(isMaster ? heroCardsFromMasterSet(master.heroPositions) : heroPositions, 5, collection.cardSetCode);
  const shown = (isMaster ? master.positions?.total : positions?.total) ?? 0;
  const unit = isMaster ? (shown === 1 ? "posição" : "posições") : shown === 1 ? "carta" : "cartas";
  const currentSegment = segments.find((segment) => segment.key === filter);

  const page = (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${heroStyles.hero}`} data-has-fan={hero.cards.length > 0 || undefined}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <CollectionHeroBackdrop selection={hero} />
        <div className={manageStyles.heroBar}>
          <Link href={COLECOES_PATH} className={styles.backLink}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Minhas coleções
          </Link>
          {canManage ? (
            <div className={manageStyles.heroBarActions}>
              <ReactivatedStatus collectionId={collection.id} />
              <CollectionSettingsButton
                collectionId={collection.id}
                collectionName={collection.name}
                kind="card_set"
                identity={{
                  name: collection.name,
                  finish: collection.finish,
                  finishEditable: collection.finishEditable,
                  setName: collection.cardSetName,
                }}
              />
            </div>
          ) : !active ? (
            <ReactivateCollectionButton collectionId={collection.id} collectionName={collection.name} />
          ) : null}
        </div>
        <div className={heroStyles.stage}>
          <div className={heroStyles.text}>
            <div className={heroStyles.identity}>
              <div className={heroStyles.identityCover}>
                <BinderCoverLink collectionId={collection.id} ready={Boolean(binder?.hasBinder && binder.pageCount > 0)} available={binderEntryVisible(binder)}>
                <BinderCover
                  finish={collection.finish}
                  setName={collection.cardSetName}
                  setCode={collection.cardSetCode}
                  logoUrl={logoUrl}
                  fallbackTitle={collection.name}
                  complete={collection.isComplete}
                  size="compact"
                  priority
                />
                </BinderCoverLink>
              </div>
              <div className={heroStyles.identityText}>
                <div className={heroStyles.title}>
                  <CollectionTitle name={collection.name} archived={!active} />
                </div>
                <p className={heroStyles.setLine}>
                  {setCode ? <span className={heroStyles.setCode}>{setCode.toUpperCase()}</span> : null}
                  {/* O título já é o nome do Set na maioria das coleções; só repete quando difere. */}
                  {collection.cardSetName && collection.cardSetName !== collection.name ? (
                    <strong>{collection.cardSetName}</strong>
                  ) : null}
                  <span>
                    {collectionKindLabel(collection.completionPolicy)}
                  </span>
                </p>
              </div>
            </div>

            <section className={heroStyles.progress} aria-label="Progresso da coleção">
              <div className={styles.progressFigure}>
                <span className={heroStyles.progressBig}>{formatCount(owned)}</span>
                <span className={styles.progressOf}>de {formatCount(total)}</span>
                <span className={styles.progressPct}>{collection.isComplete ? "100%" : progressPercentText(owned, total)}</span>
              </div>
              <div
                className={`${styles.track} ${heroStyles.track}`}
                role="progressbar"
                aria-valuemin={0}
                aria-valuemax={total}
                aria-valuenow={owned}
                aria-valuetext={`${formatCount(owned)} de ${formatCount(total)} ${isMaster ? "posições" : "cartas"}`}
              >
                <div
                  className={collection.isComplete ? `${styles.fill} ${styles.fillComplete}` : styles.fill}
                  style={{ width: `${progressBarPercent(owned, total)}%` }}
                />
              </div>
              <div className={styles.progressFoot}>
                {collection.isComplete ? (
                  <span className={styles.completeNote}>
                    <Trophy className="h-4 w-4" aria-hidden="true" />
                    {isMaster ? "Master Set completo" : "Set completo"}
                  </span>
                ) : (
                  <span>
                    Faltam <strong>{formatCount(missing)}</strong>
                  </span>
                )}
                <span>
                  <strong>{formatCount(collection.copiesCount)}</strong>{" "}
                  {collection.copiesCount === 1 ? "carta" : "cartas"} na coleção
                </span>
              </div>
            </section>

            <BinderEntry collectionId={collection.id} collectionName={collection.name} coverCode={collection.cardSetCode} cardSetName={collection.cardSetName} finish={collection.finish} binder={binder} />
          </div>

          <CollectionHeroFan selection={hero} />
        </div>
      </header>


      <section className={heroStyles.gallery} aria-labelledby="colecao-cartas">
        <div className={heroStyles.galleryHead}>
          <div className={heroStyles.galleryHeadText}>
            <h2 id="colecao-cartas" className={heroStyles.galleryTitle}>
              Cartas da coleção
            </h2>
            {(isMaster ? master.positions : positions) !== null ? (
              <p className={heroStyles.galleryMeta}>
                {currentSegment?.label} · {formatCount(shown)} {unit}
              </p>
            ) : null}
          </div>
          <div className={heroStyles.galleryTools}>
            {/* Abas sublinhadas (opção A, Fabrício 2026-10-18): texto puro, linha dourada sob a ativa. */}
            <nav className={styles.filterTabs} aria-label="Mostrar cartas">
              {segments.map((segment) => (
                <Link
                  key={segment.key}
                  href={collectionHref(collection.id, segment.key)}
                  scroll={false}
                  className={styles.filterTab}
                  aria-current={segment.key === filter ? "page" : undefined}
                >
                  {segment.label}
                  <span className={styles.filterTabCount}>{formatCount(segment.count)}</span>
                </Link>
              ))}
            </nav>
            {setCode && !isMaster ? (
              // Sempre visível; desabilitado quando não há o que adicionar.
              <LinkCardsLauncher
                collectionId={collection.id}
                setCode={setCode}
                linkable={canLink && linkable !== null ? linkable : 0}
                layout="hero"
              />
            ) : null}
            {isMaster && master.linkable !== null ? (
              <MasterSetLinkLauncher collectionId={collection.id} linkable={active ? master.linkable : 0} />
            ) : null}
            {canManage && setCode ? (
              <CollectionAddLauncher
                autoOpen={registerMode}
                target={{
                  collectionId: collection.id,
                  collectionName: collection.name,
                  kind: "set",
                  cardSet: { code: setCode, name: collection.cardSetName ?? setCode.toUpperCase() },
                }}
              />
            ) : null}
          </div>
        </div>

      {isMaster ? (
        <MasterSetGallery
          collectionId={collection.id}
          collectionName={collection.name}
          filter={filter}
          page={master.page}
          positions={master.positions}
          outOfScopeCount={master.outOfScopeCount}
          setCode={setCode}
          manageable={canManage}
        />
      ) : positions === null ? (
        <ReadError retryHref={collectionHref(collection.id, filter)} />
      ) : positions.items.length === 0 ? (
        <EmptyFilter
          filter={filter}
          collection={collection}
          linkLauncher={
            canLink && setCode ? (
              <LinkCardsLauncher collectionId={collection.id} setCode={setCode} linkable={linkable} layout="empty" />
            ) : null
          }
        />
      ) : (
        // Clicar na carta amplia — mesmo preview e mesmo morph do Catálogo Editorial.
        <CardZoomProvider>
          <ul className={acervoStyles.grid} aria-label={`Cartas — ${segments.find((segment) => segment.key === filter)?.label}`}>
            {positions.items.map((position, index) => (
              <li key={position.cardId}>
                <PositionTile
                  position={position}
                  priority={index < PRIORITY_CARD_COUNT}
                  setCode={setCode}
                  manageable={canManage}
                />
              </li>
            ))}
          </ul>
        </CardZoomProvider>
      )}
      </section>
    </div>
  );

  return canManage ? (
    <CollectionManageProvider collectionId={collection.id} collectionName={collection.name} kind="card_set">
      {page}
    </CollectionManageProvider>
  ) : (
    page
  );
}

function PositionTile({
  position,
  priority,
  setCode,
  manageable,
}: {
  position: CollectionPosition;
  priority: boolean;
  setCode: string | null;
  manageable: boolean;
}) {
  const number = formatCollectorNumber(position.collectorNumber, position.collectorTotal);
  const caption = setCode ? `${setCode.toUpperCase()} · ${number}` : number;
  const imageUrl = cardFrontUrl(SUPABASE_URL, position.imagePath);
  const repeated = position.isSatisfied ? position.copiesAvailable : 0;
  const status = position.isSatisfied
    ? "na coleção"
    : position.copiesAvailable > 0
      ? "falta na coleção, mas você tem no acervo"
      : "falta";

  return (
    <article className={acervoStyles.tile} aria-label={`${position.cardName}, ${caption}, ${status}`}>
      <div className={acervoStyles.artWrap}>
        <CardZoomTrigger id={position.cardId} imageUrl={imageUrl} name={position.cardName} className={styles.zoomTrigger}>
          <div className={position.isSatisfied ? acervoStyles.art : `${acervoStyles.art} ${styles.missing}`}>
            <CardArt
              src={imageUrl}
              alt=""
              name={position.cardName}
              caption={caption}
              priority={priority}
              sizes={GRID_SIZES}
            />
            {!position.isSatisfied ? (
              <span
                className={position.copiesAvailable > 0 ? `${styles.missingTag} ${styles.availableTag}` : styles.missingTag}
                aria-hidden="true"
              >
                {position.copiesAvailable > 0 ? "No seu acervo" : "Falta"}
              </span>
            ) : null}
          </div>
        </CardZoomTrigger>
        {position.copiesInCollection > 1 ? (
          <span className={acervoStyles.qty} aria-hidden="true">
            ×{formatCount(position.copiesInCollection)}
          </span>
        ) : null}
        {manageable && setCode && position.copiesInCollection > 0 ? (
          <ManageCopiesButton
            target={{
              query: { kind: "set_card", setCode, collectorNumber: position.collectorNumber },
              cardName: position.cardName,
              caption,
              imageUrl,
            }}
          />
        ) : null}
      </div>
      <div className={acervoStyles.meta} aria-hidden="true">
        <div className={acervoStyles.name}>{position.cardName}</div>
        <div className={acervoStyles.sub}>
          <span>{caption}</span>
          {position.isSatisfied ? (
            <span className={acervoStyles.tag}>
              <Check className="mr-0.5 inline h-3 w-3" />
              Tenho
            </span>
          ) : null}
          {repeated > 0 ? (
            <span className={acervoStyles.tag}>
              {repeated === 1 ? "1 repetida" : `${formatCount(repeated)} repetidas`}
            </span>
          ) : null}
        </div>
      </div>
    </article>
  );
}

function EmptyFilter({
  filter,
  collection,
  linkLauncher,
}: {
  filter: PositionFilter;
  collection: CollectionSummary;
  linkLauncher: ReactNode;
}) {
  if (filter === "faltam") {
    return (
      <section className={acervoStyles.state} aria-labelledby="colecao-completa">
        <div className={acervoStyles.stateIcon} aria-hidden="true">
          <Trophy className="h-6 w-6" />
        </div>
        <h2 id="colecao-completa" className={acervoStyles.stateTitle}>
          Não falta nenhuma carta
        </h2>
        <p className={acervoStyles.stateText}>{collection.name} está completa — uma de cada carta do Set.</p>
      </section>
    );
  }
  if (filter === "tenho") {
    return (
      <section className={acervoStyles.state} aria-labelledby="colecao-vazia">
        <h2 id="colecao-vazia" className={acervoStyles.stateTitle}>
          Esta coleção ainda não tem cartas
        </h2>
        <p className={acervoStyles.stateText}>
          {linkLauncher
            ? "Você já tem cartas deste Set no acervo. Adicione uma de cada para começar o progresso."
            : "Quando você registrar cartas deste Set no acervo, poderá adicioná-las aqui."}
        </p>
        {linkLauncher}
      </section>
    );
  }
  return (
    <section className={acervoStyles.state} aria-labelledby="colecao-indisponivel">
      <h2 id="colecao-indisponivel" className={acervoStyles.stateTitle}>
        Esta coleção ainda não pode ser exibida aqui
      </h2>
      <p className={acervoStyles.stateText}>Por enquanto, só coleções de Set padrão mostram as cartas nesta tela.</p>
      <Button asChild variant="outline" className={acervoStyles.stateAction}>
        <Link href={COLECOES_PATH}>Voltar às coleções</Link>
      </Button>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={acervoStyles.state} role="alert" aria-labelledby="colecao-erro">
      <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="colecao-erro" className={acervoStyles.stateTitle}>
        Não conseguimos carregar as cartas desta coleção
      </h2>
      <p className={acervoStyles.stateText}>Nada foi perdido. Tente novamente em instantes.</p>
      <Button asChild className={acervoStyles.stateAction}>
        <Link href={retryHref} prefetch={false}>
          Tentar novamente
        </Link>
      </Button>
    </section>
  );
}
