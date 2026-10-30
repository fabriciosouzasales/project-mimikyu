import Link from "next/link";
import { AlertTriangle, Archive, ArrowLeft, Layers, ShieldCheck, TrendingUp } from "lucide-react";
import { libraryItemHref, sharedOwnerText } from "@/lib/colecoes/shared-library";
import { Button } from "@/components/ui/button";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  FREE_COLLECTION_ENABLED,
  type LibraryMode,
  type StorageOption,
  collectionSpokenSubtitle,
  LIBRARY_PAGE_SIZE,
  libraryHref,
  librarySummary,
  libraryTotalPages,
  collectionProgressView,
  progressLabel,
  progressBarPercent,
  progressPercentText,
} from "@/lib/colecoes/colecoes";
import type { CollectionSummary, CollectionsPage } from "@/lib/colecoes/colecoes-queries";
import { plateCode, plateLogoKey } from "@/lib/colecoes/free-collection";
import acervoStyles from "../acervo/acervo.module.css";
import { BinderCover } from "./binder-cover";
import { isPokedexCollection } from "@/lib/colecoes/pokedex";
import coverStyles from "./binder-cover.module.css";
import { CreateCollectionLauncher, type OwnedSet } from "./create-collection";
import { LibraryModes } from "./library-modes";
import { CollectionKindLine, SharedCollectionBadge } from "./collection-kind-badge";
import styles from "./colecoes.module.css";
import lifecycleStyles from "./collection-lifecycle.module.css";
import { archivedLibraryHref } from "@/lib/colecoes/collection-lifecycle";

/**
 * Minhas coleções — Biblioteca (Server Component). Três modos (NS-17), com os
 * mesmos dados da página: Cards (padrão aprovado — cada coleção é um fichário,
 * objeto 3D `binder-cover.tsx`, na cor da coleção, com a identidade do Set na
 * placa, nunca a imagem de uma carta), Lista (`library-list.tsx`) e Carrossel
 * (`library-carousel.tsx`). O seletor (`library-modes.tsx`) troca o modo no
 * cliente, sem nova consulta.
 *
 * Estados: vazio (primeira coleção), erro de leitura (com "Tentar
 * novamente"), carregando (`loading.tsx`).
 */
export function LibraryView({
  page,
  pageNumber,
  locations,
  ownedSets,
  logoUrls,
  mode = "cards",
  view = "active",
  archivedCount = null,
  ownedTotal = null,
}: {
  page: CollectionsPage | null;
  /** Estante ativa (padrão) ou coleções arquivadas (V1-04). */
  view?: "active" | "archived";
  /** Quantas arquivadas existem (só na estante ativa); `null`/0 = entrada some. */
  archivedCount?: number | null;
  /**
   * V1-12: total só das coleções PRÓPRIAS. `page.total` soma as compartilhadas
   * (mesma estante); os agregados de cartas do painel usam só as suas.
   */
  ownedTotal?: number | null;
  /** Modo inicial (URL › cookie › Cards), resolvido no servidor para não piscar. */
  mode?: LibraryMode;
  /** Logos de Set assinados para esta página (vazio quando a sessão não pode lê-los). */
  logoUrls: Map<string, string>;
  pageNumber: number;
  locations: StorageOption[] | null;
  ownedSets: OwnedSet[];
}) {
  const isEmpty = page !== null && page.total === 0;
  const pages = page ? libraryTotalPages(page.total) : 1;
  const logoUrlRecord = Object.fromEntries(logoUrls);
  const archivedView = view === "archived";
  const pageHref = archivedView ? archivedLibraryHref : libraryHref;

  if (archivedView) {
    return (
      <div className={acervoStyles.root}>
        <header className={`${acervoStyles.hero} ${styles.libraryHero}`}>
          <div className={acervoStyles.stageGlow} aria-hidden="true" />
          {page && page.total > 0 ? (
            <span className={acervoStyles.numeral} aria-hidden="true">
              {formatCount(page.total)}
            </span>
          ) : null}
          <div className={acervoStyles.heroContent}>
            <Link href={libraryHref(1)} className={styles.backLink}>
              <ArrowLeft className="h-4 w-4" aria-hidden="true" />
              Minhas coleções
            </Link>
            <h1 className={acervoStyles.title}>Coleções arquivadas</h1>
            <p className={acervoStyles.lede}>
              Fora da estante, <strong>nada perdido</strong>: cartas, vínculos e fichários continuam guardados. Abra uma
              coleção para consultar ou reativá-la.
            </p>
          </div>
        </header>

        {page === null ? (
          <ReadError retryHref={archivedLibraryHref(pageNumber)} />
        ) : isEmpty ? (
          <section className={acervoStyles.state} aria-labelledby="arquivadas-vazio">
            <div className={acervoStyles.stateIcon} aria-hidden="true">
              <Archive className="h-6 w-6" />
            </div>
            <h2 id="arquivadas-vazio" className={acervoStyles.stateTitle}>
              Nenhuma coleção arquivada
            </h2>
            <p className={acervoStyles.stateText}>
              Para arquivar uma coleção que você não está mais acompanhando, abra a coleção e use Ajustes → Arquivar coleção.
            </p>
            <Button asChild variant="outline" className={acervoStyles.stateAction}>
              <Link href={libraryHref(1)}>Voltar para Minhas coleções</Link>
            </Button>
          </section>
        ) : (
          <LibraryModes
            key={`arquivadas-${pageNumber}`}
            initialMode={mode}
            items={page.items}
            logoUrls={logoUrlRecord}
            title="Arquivadas"
            reorderable={false}
            meta={
              pages > 1
                ? `${formatCount((pageNumber - 1) * LIBRARY_PAGE_SIZE + 1)}–${formatCount(
                    Math.min(pageNumber * LIBRARY_PAGE_SIZE, page.total),
                  )} de ${formatCount(page.total)} arquivadas`
                : null
            }
            cardNodes={Object.fromEntries(
              page.items.map((collection, index) => [
                collection.id,
                <Shelf
                  key={collection.id}
                  collection={collection}
                  logoUrl={plateLogoKey(collection) ? logoUrls.get(plateLogoKey(collection) ?? "") ?? null : null}
                  priority={pageNumber === 1 && index < 4}
                />,
              ]),
            )}
          >
            <Pagination pageNumber={pageNumber} pages={pages} href={pageHref} label="Páginas das coleções arquivadas" />
          </LibraryModes>
        )}
      </div>
    );
  }

  return (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${styles.libraryHero}`}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <HeroShelf />
        {page && page.total > 0 ? (
          <span className={acervoStyles.numeral} aria-hidden="true">
            {formatCount(page.total)}
          </span>
        ) : null}
        <div className={acervoStyles.heroContent}>
          <h1 className={acervoStyles.title}>Minhas coleções</h1>
          <p className={acervoStyles.lede}>
            {isEmpty ? (
              <>
                Cada coleção é um objetivo: escolha um Set e acompanhe, <strong>carta por carta</strong>, o quanto
                falta para completá-lo.
              </>
            ) : (
              <>
                Cada fichário, um objetivo — <strong>o progresso de todos à vista</strong>, lado a lado na sua
                estante.
              </>
            )}
          </p>
        </div>
        {page && !isEmpty ? (
          <div className={acervoStyles.heroRow}>
            <LibraryLedger page={page} ownedTotal={ownedTotal ?? page.total} />
            <CreateCollectionLauncher locations={locations} ownedSets={ownedSets} layout="hero" />
          </div>
        ) : null}
      </header>

      {page === null ? (
        <ReadError retryHref={libraryHref(pageNumber)} />
      ) : isEmpty ? (
        <EmptyLibrary locations={locations} ownedSets={ownedSets} archivedCount={archivedCount} />
      ) : (
        <LibraryModes
          key={pageNumber}
          initialMode={mode}
          items={page.items}
          logoUrls={logoUrlRecord}
          headerAside={archivedCount ? <ArchivedLink count={archivedCount} /> : null}
          meta={
            pages > 1
              ? `${formatCount((pageNumber - 1) * LIBRARY_PAGE_SIZE + 1)}–${formatCount(
                  Math.min(pageNumber * LIBRARY_PAGE_SIZE, page.total),
                )} de ${formatCount(page.total)} coleções`
              : null
          }
          cardNodes={Object.fromEntries(
            page.items.map((collection, index) => [
              collection.id,
              <Shelf
                key={collection.id}
                collection={collection}
                logoUrl={plateLogoKey(collection) ? logoUrls.get(plateLogoKey(collection) ?? "") ?? null : null}
                priority={pageNumber === 1 && index < 4}
              />,
            ]),
          )}
        >
          <Pagination pageNumber={pageNumber} pages={pages} href={pageHref} label="Páginas das coleções" />
        </LibraryModes>
      )}
    </div>
  );
}

/**
 * Painel de números do conjunto (mesmo vocabulário do painel de Meu acervo).
 * Os agregados só aparecem quando a página contém todas as coleções; numa página
 * parcial ficaria errado somar, então resta só o total (que vem do banco).
 */
function LibraryLedger({ page, ownedTotal }: { page: CollectionsPage; ownedTotal: number }) {
  // As compartilhadas contam na estante, mas não nos agregados de cartas: o que
  // elas reúnem é do acervo de outra pessoa (C-157).
  const summary = librarySummary(
    page.items.filter((item) => !item.sharedBy),
    ownedTotal,
  );
  const items: { key: string; value: string; name: string; hint: string; lead?: boolean }[] = [
    {
      key: "collections",
      value: formatCount(page.total),
      name: page.total === 1 ? "coleção" : "coleções",
      hint: "na sua biblioteca",
      lead: true,
    },
  ];
  if (summary && summary.targetCards > 0) {
    items.push(
      {
        key: "owned",
        value: formatCount(summary.ownedCards),
        name: summary.ownedCards === 1 ? "carta reunida" : "cartas reunidas",
        hint: `de ${formatCount(summary.targetCards)} nos objetivos`,
      },
      {
        key: "overall",
        value: `${summary.overallPercent}%`,
        name: "progresso geral",
        hint: "somando todos os Sets",
      },
      {
        key: "complete",
        value: formatCount(summary.complete),
        name: summary.complete === 1 ? "completa" : "completas",
        hint: summary.complete === 0 ? "a primeira está a caminho" : "objetivos concluídos",
      },
    );
  }
  return (
    <dl
      className={`${acervoStyles.ledger} ${items.length === 1 ? styles.ledgerSolo : ""}`}
      aria-label="Resumo das coleções"
    >
      {items.map((item) => (
        <div
          key={item.key}
          className={item.lead ? `${acervoStyles.ledgerItem} ${acervoStyles.ledgerLead}` : acervoStyles.ledgerItem}
        >
          <dt className={acervoStyles.ledgerLabel}>
            <span className={acervoStyles.ledgerName}>{item.name}</span>
            <span className={acervoStyles.ledgerHint}>{item.hint}</span>
          </dt>
          <dd className={acervoStyles.ledgerValue}>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * Elemento cenográfico do palco (equivale à lente da Pokédex e ao leque de cartas
 * de Meu acervo): uma estante com vários fichários de alturas diferentes, um deles
 * inclinado e um de frente com o zíper. Traço fino na cor do texto, opacidade
 * baixa — sugere o conjunto sem depender de quantas coleções existem.
 */
function HeroShelf() {
  return (
    <svg className={styles.heroShelf} viewBox="0 0 520 300" fill="none" aria-hidden="true" focusable="false">
      <g stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
        {/* prateleira */}
        <path d="M8 262h504" strokeLinecap="round" />
        <path d="M24 262v14M496 262v14" strokeLinecap="round" />
        {/* lombadas em pé */}
        <rect x="40" y="96" width="44" height="166" rx="6" />
        <path d="M50 120h24M50 128h16" strokeLinecap="round" />
        <rect x="50" y="222" width="24" height="18" rx="3" />
        <rect x="90" y="70" width="52" height="192" rx="6" />
        <path d="M101 96h30M101 104h20" strokeLinecap="round" />
        <rect x="102" y="220" width="28" height="20" rx="3" />
        <rect x="148" y="110" width="40" height="152" rx="6" />
        <path d="M157 132h22" strokeLinecap="round" />
        <rect x="158" y="224" width="20" height="16" rx="3" />
        {/* lombada inclinada */}
        <g transform="translate(14 0) rotate(-8 234 262)">
          <rect x="198" y="92" width="46" height="170" rx="6" />
          <path d="M208 116h26M208 124h16" strokeLinecap="round" />
          <rect x="209" y="222" width="24" height="18" rx="3" />
        </g>
        {/* fichário de frente: capa com zíper e placa */}
        <rect x="282" y="58" width="150" height="204" rx="12" />
        <path d="M424 70v180" strokeDasharray="3 5" strokeLinecap="round" />
        <rect x="304" y="106" width="100" height="52" rx="6" />
        <path d="M304 196h46" strokeLinecap="round" />
        <rect x="296" y="72" width="122" height="176" rx="8" strokeDasharray="2 6" opacity="0.6" />
        {/* lombada atrás, à direita */}
        <rect x="444" y="88" width="42" height="174" rx="6" />
        <path d="M453 112h24M453 120h14" strokeLinecap="round" />
        <rect x="454" y="222" width="22" height="18" rx="3" />
      </g>
    </svg>
  );
}

function Shelf({
  collection,
  logoUrl,
  priority,
}: {
  collection: CollectionSummary;
  logoUrl: string | null;
  priority: boolean;
}) {
  const view = collectionProgressView(collection);
  const label =
    view.kind === "free"
      ? `${formatCount(view.copies)} ${view.copies === 1 ? "carta reunida" : "cartas reunidas"}`
      : progressLabel(collection.satisfiedPositions, collection.totalPositions);
  const subtitle = collectionSpokenSubtitle(collection);
  const owner = sharedOwnerText(collection);

  return (
    <Link
      href={libraryItemHref(collection)}
      className={`${styles.shelfItem} ${coverStyles.trigger}`}
      aria-label={`${collection.name}, ${subtitle}${owner ? `, compartilhada ${owner}` : ""}, ${label}${collection.isComplete ? ", completa" : ""}${collection.lifecycleStatus === "ARCHIVED" ? ", arquivada" : ""}`}
    >
      <BinderCover
        finish={collection.finish}
        setName={collection.cardSetName}
        setCode={plateCode(collection)}
        logoUrl={logoUrl}
        fallbackTitle={collection.name}
        emblem={isPokedexCollection(collection) ? "pokedex" : null}
        complete={collection.isComplete}
        priority={priority}
      />
      <div className={styles.shelfMeta} aria-hidden="true">
        <span className={styles.shelfName}>{collection.name}</span>
        <span className={styles.shelfKind}>
          <CollectionKindLine collection={collection} />
        </span>
        {owner ? <SharedCollectionBadge owner={owner} /> : null}
        {collection.lifecycleStatus === "ARCHIVED" ? (
          <span className={lifecycleStyles.archivedTag}>
            <Archive className="h-3 w-3" aria-hidden="true" />
            Arquivada
          </span>
        ) : null}
        {view.kind === "free" ? (
          // Coleção livre: sem meta, sem barra — só o que ela reúne (C-20).
          <div className={styles.shelfProgress}>
            <span className={styles.shelfCount}>
              <strong>{label}</strong>
            </span>
          </div>
        ) : (
          <div className={styles.shelfProgress}>
            <div className={styles.shelfTrack}>
              <div
                className={collection.isComplete ? `${styles.fill} ${styles.fillComplete}` : styles.fill}
                style={{ width: `${progressBarPercent(collection.satisfiedPositions, collection.totalPositions)}%` }}
              />
            </div>
            <span className={styles.shelfCount}>
              <strong>{label}</strong>
              {collection.isComplete ? " · completa" : ` · ${progressPercentText(collection.satisfiedPositions, collection.totalPositions)}`}
            </span>
          </div>
        )}
      </div>
    </Link>
  );
}

function EmptyLibrary({
  locations,
  ownedSets,
  archivedCount,
}: {
  locations: StorageOption[] | null;
  ownedSets: OwnedSet[];
  archivedCount: number | null;
}) {
  const promises = [
    {
      icon: TrendingUp,
      title: "Progresso de verdade",
      text: "“146 de 158” — quantas você tem e exatamente quais faltam.",
    },
    {
      icon: Layers,
      title: "Com as cartas que você já tem",
      text: "Adicione de uma vez uma de cada carta do Set que já está no seu acervo.",
    },
    {
      icon: ShieldCheck,
      title: "Nada sai do lugar",
      text: "Uma coleção organiza o que você tem; nenhuma carta é movida ou removida do acervo.",
    },
  ];
  return (
    <section className={acervoStyles.emptyStage} aria-labelledby="colecoes-vazio">
      <div className={acervoStyles.binderPage} aria-hidden="true">
        {Array.from({ length: 9 }, (_, index) => (
          <span key={index} className={index === 4 ? `${acervoStyles.socket} ${acervoStyles.socketLit}` : acervoStyles.socket} />
        ))}
      </div>
      <div className={acervoStyles.emptyCopy}>
        <h2 id="colecoes-vazio" className={acervoStyles.emptyTitle}>
          {FREE_COLLECTION_ENABLED ? "Comece sua primeira coleção" : "Sua primeira coleção começa com um Set"}
        </h2>
        <p className={acervoStyles.emptyText}>
          {ownedSets.length > 0
            ? `Você já tem cartas de ${ownedSets.length === 1 ? "1 Set" : `${formatCount(ownedSets.length)} Sets`} no acervo. Escolha um para ver quanto falta para completá-lo.`
            : "Escolha um Set e acompanhe o que falta. As cartas que você registrar no acervo depois podem entrar na coleção."}
          {FREE_COLLECTION_ENABLED ? " Ou monte uma coleção livre com as cartas que quiser, de qualquer Set." : null}
        </p>
        <CreateCollectionLauncher locations={locations} ownedSets={ownedSets} layout="empty" />
        {archivedCount ? (
          <div className={lifecycleStyles.archivedEmpty}>
            <ArchivedLink count={archivedCount} />
          </div>
        ) : null}
        {locations === null ? (
          <p className={acervoStyles.emptyText}>Não foi possível preparar a criação agora. Recarregue a página em instantes.</p>
        ) : null}
        <ul className={acervoStyles.promiseList}>
          {promises.map(({ icon: Icon, title, text }) => (
            <li key={title} className={acervoStyles.promise}>
              <span className={acervoStyles.promiseIcon} aria-hidden="true">
                <Icon className="h-4 w-4" />
              </span>
              <div>
                <p className={acervoStyles.promiseTitle}>{title}</p>
                <p className={acervoStyles.promiseText}>{text}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={acervoStyles.state} role="alert" aria-labelledby="colecoes-erro">
      <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="colecoes-erro" className={acervoStyles.stateTitle}>
        Não conseguimos carregar suas coleções
      </h2>
      <p className={acervoStyles.stateText}>Nada foi perdido. Foi uma falha ao buscá-las — tente novamente em instantes.</p>
      <Button asChild className={acervoStyles.stateAction}>
        <Link href={retryHref} prefetch={false}>
          Tentar novamente
        </Link>
      </Button>
    </section>
  );
}

function Pagination({
  pageNumber,
  pages,
  href,
  label,
}: {
  pageNumber: number;
  pages: number;
  href: (page: number) => string;
  label: string;
}) {
  if (pages <= 1) return null;
  return (
    <nav className={acervoStyles.pagination} aria-label={label}>
      {pageNumber > 1 ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={href(pageNumber - 1)}>Anterior</Link>
        </Button>
      ) : null}
      <span aria-current="page">
        Página {formatCount(Math.min(pageNumber, pages))} de {formatCount(pages)}
      </span>
      {pageNumber < pages ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={href(pageNumber + 1)}>Próxima</Link>
        </Button>
      ) : null}
    </nav>
  );
}

/** Entrada discreta para as arquivadas (só aparece quando existe alguma). */
function ArchivedLink({ count }: { count: number | null }) {
  if (!count) return null;
  return (
    <Link href={archivedLibraryHref(1)} className={lifecycleStyles.archivedLink}>
      <Archive className="h-4 w-4" aria-hidden="true" />
      Arquivadas
      <span className={lifecycleStyles.archivedCount} aria-label={`${formatCount(count)} ${count === 1 ? "coleção" : "coleções"}`}>
        {formatCount(count)}
      </span>
    </Link>
  );
}
