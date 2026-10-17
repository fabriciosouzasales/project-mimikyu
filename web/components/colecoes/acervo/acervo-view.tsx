import Link from "next/link";
import { AlertTriangle, Box, Globe, Layers, Library, SearchX, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  type AcervoState,
  PRIORITY_CARD_COUNT,
  acervoHref,
  cardFrontUrl,
  formatCollectorNumber,
  formatCount,
  hasActiveFilters,
  pluralize,
  resultSummary,
  totalPages,
  variantTag,
  withoutDetail,
} from "@/lib/colecoes/acervo";
import type { AddLanguage } from "@/lib/colecoes/acervo-add";
import type {
  AcervoFilterOptions,
  AcervoItem,
  AcervoItemDetail,
  AcervoItemsPage,
  AcervoSummary,
} from "@/lib/colecoes/acervo-queries";
import { AcervoAddActions } from "./acervo-add";
import { AcervoDetailSheet } from "./acervo-detail-sheet";
import { AcervoToolbar } from "./acervo-toolbar";
import { CardArt } from "./card-art";
import { CopyQuantityControl } from "./copy-quantity-control";
import { CopyRemoveButton } from "./copy-remove-button";
import styles from "./acervo.module.css";

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const GRID_SIZES = "(max-width: 767px) 50vw, 11rem";

/**
 * Meu acervo — composição da página (Server Component).
 *
 * Camadas, na ordem de percepção: título e números do acervo → busca/filtros →
 * as cartas. Cada carta é um link para o detalhe (`?carta=`); o painel abre
 * por cima da mesma lista, renderizado no servidor.
 *
 * Estados (B6): vazio (acervo novo), sem resultados (filtros), erro de leitura
 * (com "Tentar novamente" — nunca uma lista vazia enganosa) e carregando
 * (`loading.tsx`, esqueleto no formato final).
 *
 * Cadastro (MY-INVENTORY-ACTIONS-01): "Adicionar cartas" e "Adicionar um Set
 * inteiro" (`acervo-add.tsx`), no cabeçalho ou no estado vazio. Só aparecem
 * quando há idiomas disponíveis para cadastro (sem eles a gravação não teria
 * como funcionar). Coleção e local continuam fora: nada visível finge funcionar.
 */
export function AcervoView({
  state,
  summary,
  page,
  options,
  detail,
  addLanguages,
}: {
  state: AcervoState;
  summary: AcervoSummary | null;
  page: AcervoItemsPage | null;
  options: AcervoFilterOptions | null;
  /** `undefined` = sem detalhe pedido ou grupo não encontrado; `null` = falha de leitura. */
  detail: AcervoItemDetail | null | undefined;
  /** Idiomas aceitos no cadastro; vazio = ações de adicionar indisponíveis (não aparecem). */
  addLanguages: AddLanguage[];
}) {
  const canAdd = addLanguages.length > 0;
  const isEmptyAcervo = summary !== null && summary.totalCopies === 0;
  const filtered = hasActiveFilters(state);
  const pages = page ? totalPages(page.totalGroups) : 1;
  const closeHref = acervoHref(withoutDetail(state));

  return (
    <div className={styles.root}>
      <header className={styles.hero}>
        <div className={styles.stageGlow} aria-hidden="true" />
        <HeroCards />
        {summary && summary.totalCopies > 0 ? (
          <span className={styles.numeral} aria-hidden="true">
            {formatCount(summary.totalCopies)}
          </span>
        ) : null}
        <div className={styles.heroContent}>
          <h1 className={styles.title}>Meu acervo</h1>
          <p className={styles.lede}>
            {isEmptyAcervo ? (
              <>
                Cada carta física que você tem, <strong>exemplar por exemplar</strong> — o retrato fiel do que está
                nas suas mãos.
              </>
            ) : (
              <>
                Todas as suas cartas físicas, <strong>estejam ou não em uma coleção</strong>.
              </>
            )}
          </p>
        </div>
        {summary ? (
          <div className={styles.heroRow}>
            <SummaryLedger summary={summary} quiet={isEmptyAcervo} />
            {canAdd && !isEmptyAcervo ? <AcervoAddActions languages={addLanguages} layout="hero" /> : null}
          </div>
        ) : null}
      </header>

      {page === null || summary === null ? (
        <ReadError retryHref={acervoHref(state)} />
      ) : summary.totalCopies === 0 ? (
        <EmptyAcervo addLanguages={canAdd ? addLanguages : null} />
      ) : (
        <>
          <AcervoToolbar
            state={state}
            options={options}
            resultLabel={filtered ? resultSummary(page.totalGroups) : pluralize(summary.totalCopies, "carta", "cartas")}
          />
          <ActiveFilterChips state={state} options={options} />

          {page.items.length === 0 ? (
            <NoResults state={state} />
          ) : (
            <>
              <ul className={styles.grid} aria-label="Cartas do seu acervo">
                {page.items.map((item, index) => (
                  <li key={`${item.cardVariantId}.${item.languageCode}`}>
                    <AcervoTile item={item} state={state} priority={state.page === 1 && index < PRIORITY_CARD_COUNT} />
                  </li>
                ))}
              </ul>
              {pages > 1 ? <Pagination state={state} pages={pages} /> : null}
            </>
          )}
        </>
      )}

      {state.detail ? (
        <AcervoDetailSheet
          key={`${state.detail.cardVariantId}.${state.detail.languageCode}`}
          title="Detalhe da carta"
          closeHref={closeHref}
        >
          <DetailContent detail={detail} closeHref={closeHref} addLanguages={addLanguages} />
        </AcervoDetailSheet>
      ) : null}
    </div>
  );
}

/**
 * Painel de números do acervo — um bloco só, com o total em destaque e as três
 * medidas derivadas, cada uma com a frase do que mede (linguagem do colecionador).
 */
function SummaryLedger({ summary, quiet }: { summary: AcervoSummary; quiet: boolean }) {
  const items = [
    {
      key: "total",
      value: summary.totalCopies,
      name: summary.totalCopies === 1 ? "carta" : "cartas",
      hint: "exemplares físicos no acervo",
      lead: true,
    },
    {
      key: "distinct",
      value: summary.distinctItems,
      name: summary.distinctItems === 1 ? "diferente" : "diferentes",
      hint: "carta, variante e idioma",
    },
    {
      key: "sets",
      value: summary.distinctSets,
      name: summary.distinctSets === 1 ? "Set" : "Sets",
      hint: "edições representadas",
    },
    {
      key: "dupes",
      value: summary.duplicateCopies,
      name: summary.duplicateCopies === 1 ? "repetida" : "repetidas",
      hint: "além da primeira cópia",
    },
  ];
  return (
    <dl className={quiet ? `${styles.ledger} ${styles.ledgerQuiet}` : styles.ledger} aria-label="Resumo do acervo">
      {items.map((item) => (
        <div key={item.key} className={item.lead ? `${styles.ledgerItem} ${styles.ledgerLead}` : styles.ledgerItem}>
          <dt className={styles.ledgerLabel}>
            <span className={styles.ledgerName}>{item.name}</span>
            <span className={styles.ledgerHint}>{item.hint}</span>
          </dt>
          <dd className={styles.ledgerValue}>{formatCount(item.value)}</dd>
        </div>
      ))}
    </dl>
  );
}

/** Três silhuetas de carta em leque — elemento cenográfico do palco (equivale à lente da Pokédex). */
function HeroCards() {
  return (
    <svg className={styles.heroCards} viewBox="0 0 420 320" fill="none" aria-hidden="true" focusable="false">
      <g stroke="currentColor" strokeWidth="1.5">
        <rect x="70" y="70" width="160" height="220" rx="12" transform="rotate(-14 150 180)" />
        <rect x="190" y="40" width="160" height="220" rx="12" transform="rotate(10 270 150)" />
        <rect x="130" y="50" width="160" height="220" rx="12" />
        <rect x="146" y="66" width="128" height="96" rx="6" />
        <path d="M146 182h96M146 198h70M146 214h84" strokeLinecap="round" />
      </g>
    </svg>
  );
}

function AcervoTile({ item, state, priority }: { item: AcervoItem; state: AcervoState; priority: boolean }) {
  const number = formatCollectorNumber(item.collectorNumber, item.collectorTotal);
  const tag = variantTag(item.isDefaultVariant, item.variantLabel);
  const caption = `${item.cardSetCode.toUpperCase()} · ${number}`;
  const copies = item.copiesCount;
  const accessibleName = [
    item.cardName,
    caption,
    tag,
    item.languageName,
    copies === 1 ? "1 exemplar" : `${formatCount(copies)} exemplares`,
  ]
    .filter(Boolean)
    .join(", ");

  return (
    <Link
      href={acervoHref({ ...state, detail: { cardVariantId: item.cardVariantId, languageCode: item.languageCode } })}
      scroll={false}
      className={styles.tile}
      aria-label={accessibleName}
    >
      <div className={copies > 1 ? `${styles.artWrap} ${styles.stack}` : styles.artWrap}>
        <div className={styles.art}>
          <CardArt
            src={cardFrontUrl(SUPABASE_URL, item.imagePath)}
            alt=""
            name={item.cardName}
            caption={caption}
            priority={priority}
            sizes={GRID_SIZES}
          />
        </div>
        {copies > 1 ? (
          <span className={styles.qty} aria-hidden="true">
            ×{formatCount(copies)}
          </span>
        ) : null}
      </div>
      <div className={styles.meta} aria-hidden="true">
        <div className={styles.name}>{item.cardName}</div>
        <div className={styles.sub}>
          <span>{caption}</span>
          {tag ? <span className={styles.tag}>{tag}</span> : null}
          <span className={styles.tag}>{item.languageCode}</span>
        </div>
      </div>
    </Link>
  );
}

function ActiveFilterChips({ state, options }: { state: AcervoState; options: AcervoFilterOptions | null }) {
  const chips: { label: string; href: string }[] = [];
  if (state.query) chips.push({ label: `“${state.query}”`, href: acervoHref({ ...state, query: null, page: 1, detail: null }) });
  if (state.setCode) {
    const name = options?.sets.find((option) => option.value === state.setCode)?.label ?? state.setCode.toUpperCase();
    chips.push({ label: `Set: ${name}`, href: acervoHref({ ...state, setCode: null, page: 1, detail: null }) });
  }
  if (state.languageCode) {
    const name = options?.languages.find((option) => option.value === state.languageCode)?.label ?? state.languageCode;
    chips.push({ label: `Idioma: ${name}`, href: acervoHref({ ...state, languageCode: null, page: 1, detail: null }) });
  }
  if (state.collection.kind === "none") {
    chips.push({ label: "Sem coleção", href: acervoHref({ ...state, collection: { kind: "all" }, page: 1, detail: null }) });
  } else if (state.collection.kind === "collection") {
    const id = state.collection.id;
    const name = options?.collections.find((option) => option.value === id)?.label ?? "Coleção";
    chips.push({ label: `Coleção: ${name}`, href: acervoHref({ ...state, collection: { kind: "all" }, page: 1, detail: null }) });
  }
  if (chips.length === 0) return null;

  return (
    <div className={styles.chips}>
      {chips.map((chip) => (
        <span key={chip.label} className={styles.chip}>
          {chip.label}
          <Link href={chip.href} scroll={false} className={styles.chipRemove} aria-label={`Remover filtro ${chip.label}`}>
            <X className="h-3 w-3" aria-hidden="true" />
          </Link>
        </span>
      ))}
      {chips.length > 1 ? (
        <Link href={acervoHref({ sort: state.sort })} scroll={false} className={styles.chipClear}>
          Limpar filtros
        </Link>
      ) : null}
    </div>
  );
}

function Pagination({ state, pages }: { state: AcervoState; pages: number }) {
  const current = Math.min(state.page, pages);
  return (
    <nav className={styles.pagination} aria-label="Páginas do acervo">
      {current > 1 ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={acervoHref({ ...state, page: current - 1, detail: null })}>Anterior</Link>
        </Button>
      ) : null}
      <span aria-current="page">
        Página {formatCount(current)} de {formatCount(pages)}
      </span>
      {current < pages ? (
        <Button asChild variant="outline" className="h-11 min-w-11">
          <Link href={acervoHref({ ...state, page: current + 1, detail: null })}>Próxima</Link>
        </Button>
      ) : null}
    </nav>
  );
}

function EmptyAcervo({ addLanguages }: { addLanguages: AddLanguage[] | null }) {
  const promises = [
    {
      icon: Layers,
      title: "Repetidas agrupadas",
      text: "Cópias da mesma carta, variante e idioma aparecem juntas, com a contagem à vista.",
    },
    {
      icon: Globe,
      title: "Idioma de cada exemplar",
      text: "Português, inglês, japonês — cada cópia guarda o seu.",
    },
    {
      icon: Box,
      title: "Onde cada uma está guardada",
      text: "Fichário, caixa ou coleção: o lugar físico de cada carta, sem adivinhação.",
    },
  ];
  return (
    <section className={styles.emptyStage} aria-labelledby="acervo-vazio">
      <div className={styles.binderPage} aria-hidden="true">
        {Array.from({ length: 9 }, (_, index) => (
          <span key={index} className={index === 4 ? `${styles.socket} ${styles.socketLit}` : styles.socket} />
        ))}
      </div>
      <div className={styles.emptyCopy}>
        <h2 id="acervo-vazio" className={styles.emptyTitle}>
          Seu acervo começa com a primeira carta
        </h2>
        <p className={styles.emptyText}>
          Aqui fica tudo o que você tem de verdade. Assim que as primeiras cartas forem registradas, elas ocupam esta
          página — e o acervo passa a contar a sua história como colecionador.
        </p>
        {addLanguages ? <AcervoAddActions languages={addLanguages} layout="empty" /> : null}
        <ul className={styles.promiseList}>
          {promises.map(({ icon: Icon, title, text }) => (
            <li key={title} className={styles.promise}>
              <span className={styles.promiseIcon} aria-hidden="true">
                <Icon className="h-4 w-4" />
              </span>
              <div>
                <p className={styles.promiseTitle}>{title}</p>
                <p className={styles.promiseText}>{text}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

function NoResults({ state }: { state: AcervoState }) {
  return (
    <section className={styles.state} aria-labelledby="acervo-sem-resultados">
      <div className={styles.stateIcon} aria-hidden="true">
        <SearchX className="h-6 w-6" />
      </div>
      <h2 id="acervo-sem-resultados" className={styles.stateTitle}>
        Nenhuma carta encontrada
      </h2>
      <p className={styles.stateText}>
        {state.query
          ? `Nenhuma carta do seu acervo corresponde a “${state.query}” com esses filtros.`
          : "Nenhuma carta do seu acervo corresponde a esses filtros."}
      </p>
      <Button asChild variant="outline" className={styles.stateAction}>
        <Link href={acervoHref({ sort: state.sort })} scroll={false}>
          Limpar filtros
        </Link>
      </Button>
    </section>
  );
}

function ReadError({ retryHref }: { retryHref: string }) {
  return (
    <section className={styles.state} role="alert" aria-labelledby="acervo-erro">
      <div className={`${styles.stateIcon} ${styles.stateIconDanger}`} aria-hidden="true">
        <AlertTriangle className="h-6 w-6" />
      </div>
      <h2 id="acervo-erro" className={styles.stateTitle}>
        Não conseguimos carregar seu acervo
      </h2>
      <p className={styles.stateText}>
        Suas cartas estão seguras. Foi uma falha ao buscá-las — tente novamente em instantes.
      </p>
      <Button asChild className={styles.stateAction}>
        <Link href={retryHref} prefetch={false}>
          Tentar novamente
        </Link>
      </Button>
    </section>
  );
}

function DetailContent({
  detail,
  closeHref,
  addLanguages,
}: {
  detail: AcervoItemDetail | null | undefined;
  closeHref: string;
  addLanguages: AddLanguage[];
}) {
  if (detail === null) {
    return (
      <div className={styles.state} role="alert">
        <h2 className={styles.stateTitle}>Não conseguimos abrir esta carta</h2>
        <p className={styles.stateText}>Feche o painel e tente de novo em instantes.</p>
      </div>
    );
  }
  if (detail === undefined) {
    return (
      <div className={styles.state}>
        <h2 className={styles.stateTitle}>Carta não encontrada no seu acervo</h2>
        <p className={styles.stateText}>Ela pode ter sido removida, ou o link não é deste acervo.</p>
      </div>
    );
  }

  const { item, copies, copiesTotal } = detail;
  const number = formatCollectorNumber(item.collectorNumber, item.collectorTotal);
  const tag = variantTag(item.isDefaultVariant, item.variantLabel);
  const inCollections = copies.filter((copy) => copy.collectionName !== null).length;

  return (
    <>
      <div className={styles.detailHero}>
        <div className={styles.art} style={{ width: "100%" }}>
          <CardArt
            src={cardFrontUrl(SUPABASE_URL, item.imagePath)}
            alt={`${item.cardName}, ${item.cardSetName} ${number}`}
            name={item.cardName}
            caption={`${item.cardSetCode.toUpperCase()} · ${number}`}
            priority
            sizes="(max-width: 767px) 68vw, 12.5rem"
          />
        </div>
        <div>
          <h2 className={styles.detailName}>{item.cardName}</h2>
          <div className={styles.detailSub}>
            <span>
              {item.cardSetName} · {number}
            </span>
            <span className={styles.tag}>{tag ?? "Variante padrão"}</span>
          </div>
          <dl className={styles.facts}>
            <dt>Idioma</dt>
            <dd>{item.languageName}</dd>
            <dt>Exemplares</dt>
            <dd>{formatCount(copiesTotal)}</dd>
            <dt>Em coleções</dt>
            <dd>{formatCount(inCollections)}</dd>
            <dt>Sem coleção</dt>
            <dd>{formatCount(copies.length - inCollections)}</dd>
          </dl>
        </div>
      </div>

      <CopyQuantityControl
        cardVariantId={item.cardVariantId}
        languageId={addLanguages.find((language) => language.code === item.languageCode)?.id ?? null}
        copies={copies.map((copy) => ({
          physicalCardId: copy.physicalCardId,
          copyNumber: copy.copyNumber,
          inCollection: copy.collectionName !== null,
        }))}
        total={copiesTotal}
      />

      <div className={styles.sectionHead}>
        <h3 className={styles.sectionTitle}>Seus exemplares</h3>
      </div>
      <ol className={styles.copies}>
        {copies.map((copy) => (
          <li key={copy.physicalCardId} className={styles.copy}>
            <span className={styles.copyNumber} aria-hidden="true">
              {copy.copyNumber}
            </span>
            <div>
              <div className={styles.copyTitle}>Exemplar {copy.copyNumber}</div>
              <div className={styles.copyFacts}>
                <span>
                  <Globe className="h-3 w-3" aria-hidden="true" />
                  {item.languageName}
                </span>
                <span>
                  <Library className="h-3 w-3" aria-hidden="true" />
                  {copy.collectionName ?? <span className={styles.unset}>Sem coleção</span>}
                </span>
                <span>
                  <Box className="h-3 w-3" aria-hidden="true" />
                  {copy.storageName ?? <span className={styles.unset}>Sem localização definida</span>}
                </span>
              </div>
            </div>
            <CopyRemoveButton
              physicalCardId={copy.physicalCardId}
              copyNumber={copy.copyNumber}
              inCollection={copy.collectionName !== null}
              isLastCopy={copiesTotal === 1}
              closeHref={closeHref}
            />
          </li>
        ))}
      </ol>
      {copiesTotal > copies.length ? (
        <p className={styles.detailNote}>
          Mostrando os {formatCount(copies.length)} primeiros de {formatCount(copiesTotal)} exemplares.
        </p>
      ) : null}
    </>
  );
}
