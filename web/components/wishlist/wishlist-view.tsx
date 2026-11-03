"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { AlertCircle, Bookmark, Search, SearchX, X } from "lucide-react";
import { addWishlistEntry, removeWishlistEntries } from "@/app/colecoes/lista-de-desejos/actions";
import { AcervoPriceTag } from "@/components/colecoes/acervo/acervo-price";
import { CARD_GRID_SIZES as GRID_SIZES, CardArt } from "@/components/colecoes/acervo/card-art";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import colecoesStyles from "@/components/colecoes/colecoes/colecoes.module.css";
import regionStyles from "@/components/colecoes/colecoes/library-modes.module.css";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import { formatBrlWhole } from "@/lib/favorites/card-favorites";
import type { VariantPrice } from "@/lib/pricing/variant-pricing";
import {
  type WishlistFilterOptions,
  type WishlistFilters,
  type WishlistKpi,
  type WishlistSummary,
  NO_WISHLIST_FILTERS,
  clearedWishlistFilters,
  hasActiveWishlistFilters,
  needsFilteredWishlistRead,
  wishlistHref,
  wishlistResultSummary,
  ownershipLabel,
  visibleWishlistEntries,
  WISH_SUCCESS_NOTICE_MS,
  createDismissTimer,
  wishAnnouncement,
  wishErrorMessage,
  wishLanguageLabel,
  wishToggleLabel,
  wishlistKpis,
} from "@/lib/wishlist/wishlist";
import styles from "./wishlist.module.css";
import favStyles from "@/components/favorites/card-favorite.module.css";
import { WishlistFilterChips, WishlistToolbar } from "./wishlist-toolbar";

/** Desejo pronto para a tela (imagem já resolvida no servidor). */
export type WishlistEntryView = {
  entryId: string;
  cardVariantId: string;
  cardName: string;
  caption: string;
  variantLabel: string | null;
  variantAvailable: boolean;
  languageCode: string | null;
  ownership: Parameters<typeof ownershipLabel>[0];
  imageUrl: string | null;
};

/**
 * Lista de desejos — /colecoes/lista-de-desejos (V1-11 W1).
 *
 * Mesmo palco de Cartas favoritas e Minhas coleções (hero, numeral de contorno,
 * elemento cenográfico, painel de números) e a mesma região editorial abaixo. A carta é
 * a protagonista; selos discretos dizem variante, idioma ("Qualquer idioma" quando não
 * escolhido) e posse (C-213); a etiqueta NM por variante (V1-09) fica no canto inferior
 * esquerdo da arte. Variante desativada no catálogo continua na lista, sinalizada (C-214).
 *
 * Remover: o marcador dourado do card retira AQUELE desejo (variante + idioma); confirmada a
 * exclusão, a carta sai da grade e a página é relida; "Desfazer" inclui de novo a mesma
 * variante e idioma e a carta volta na hora.
 * Nada é removido automaticamente; a lista nunca é exposta a outras pessoas.
 */
export function WishlistView({
  entries,
  totalCount,
  summary,
  prices,
  priceNow,
  page,
  totalPages,
  filters = NO_WISHLIST_FILTERS,
  filterOptions = null,
}: {
  /** `null` = leitura indisponível. */
  entries: WishlistEntryView[] | null;
  totalCount: number;
  /** Indicadores (5347); `null` = leitura indisponível. */
  summary: WishlistSummary | null;
  /** Preço NM por variante (3983, V1-09); `null` = leitura indisponível. */
  prices: Record<string, VariantPrice> | null;
  priceNow: number;
  page: number;
  totalPages: number;
  /** W6: filtros da URL; `totalCount`/`totalPages` já são do resultado filtrado (5350). */
  filters?: WishlistFilters;
  /** W6: opções presentes na lista (5350); `null` = indisponíveis — a barra não aparece. */
  filterOptions?: WishlistFilterOptions | null;
}) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  // HOMOLOGATION-04 (Defeito A): a carta sai da grade só DEPOIS da exclusão confirmada pelo
  // banco (nada otimista) e a página é relida do servidor (router.refresh) — a lista, o total
  // e os indicadores passam a refletir o estado persistido. Até a releitura chegar, os ids
  // confirmados ficam ocultos localmente; "Desfazer" recria o desejo (id novo), mostra a
  // carta de volta na hora e também relê a página.
  const [hidden, setHidden] = useState<ReadonlySet<string>>(() => new Set());
  const [restored, setRestored] = useState<readonly WishlistEntryView[]>([]);
  const [pending, setPending] = useState<ReadonlySet<string>>(() => new Set());
  const [lastRemoved, setLastRemoved] = useState<WishlistEntryView | null>(null);
  const [announcement, setAnnouncement] = useState("");
  const [error, setError] = useState<string | null>(null);
  // TOAST UX CORRECTION-07: o aviso de sucesso ("saiu da lista" + Desfazer) fecha sozinho
  // após ~8 s, com pausa em hover/foco; uma nova remoção reinicia o prazo (um aviso só);
  // fechar, Desfazer confirmado ou desmontar cancelam o temporizador. Erro não fecha sozinho.
  const dismissRef = useRef<ReturnType<typeof createDismissTimer> | null>(null);
  const hoverRef = useRef(false);
  const focusRef = useRef(false);
  const noticeRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!lastRemoved || error) return;
    // O estado de hover/foco vem do DOM real no momento em que o aviso aparece — nunca de um
    // aviso anterior que sumiu com o ponteiro/foco dentro (sem mouseleave/blur), o que
    // deixava o prazo pausado para sempre.
    const node = noticeRef.current;
    hoverRef.current = node?.matches(":hover") ?? false;
    focusRef.current = node ? node.contains(document.activeElement) : false;
    const timer = createDismissTimer(() => setLastRemoved(null), WISH_SUCCESS_NOTICE_MS);
    dismissRef.current = timer;
    timer.start();
    if (hoverRef.current || focusRef.current) timer.pause();
    return () => {
      timer.cancel();
      if (dismissRef.current === timer) dismissRef.current = null;
      hoverRef.current = false;
      focusRef.current = false;
    };
  }, [lastRemoved, error]);

  function holdNotice(kind: "hover" | "focus", on: boolean) {
    if (kind === "hover") hoverRef.current = on;
    else focusRef.current = on;
    if (hoverRef.current || focusRef.current) dismissRef.current?.pause();
    else dismissRef.current?.resume();
  }

  function closeNotice() {
    dismissRef.current?.cancel();
    setLastRemoved(null);
    setError(null);
  }
  const visible = entries === null ? null : visibleWishlistEntries(entries, hidden, restored);
  const filtered = hasActiveWishlistFilters(filters);
  // "Set e número" sem filtro também usa a leitura da 5350/5351 (ordem do conjunto inteiro).
  const filteredRead = needsFilteredWishlistRead(filters);
  // W6: com filtro, `totalCount` é do resultado; o palco e o vazio "de verdade" seguem a lista inteira.
  const listCount = filtered ? (summary?.entryCount ?? null) : totalCount;
  const hasEntries = entries !== null && (filtered ? (listCount ?? 1) > 0 : totalCount > 0);
  const showToolbar = filterOptions !== null && (filtered || (entries !== null && totalCount > 0));

  const nameOf = (entry: WishlistEntryView) => (entry.variantLabel ? `${entry.cardName} · ${entry.variantLabel}` : entry.cardName);

  function mark(set: ReadonlySet<string>, id: string, on: boolean) {
    const next = new Set(set);
    if (on) next.add(id);
    else next.delete(id);
    return next;
  }

  function refresh() {
    startRefresh(() => router.refresh());
  }

  async function remove(entry: WishlistEntryView) {
    if (pending.has(entry.entryId) || hidden.has(entry.entryId)) return;
    setError(null);
    setPending((prev) => mark(prev, entry.entryId, true));
    let ok = false;
    let reason: Parameters<typeof wishErrorMessage>[1] = "failed";
    try {
      const result = await removeWishlistEntries([entry.entryId]);
      ok = result.ok;
      if (!result.ok) reason = result.reason;
    } catch {
      ok = false;
    }
    setPending((prev) => mark(prev, entry.entryId, false));
    if (ok) {
      setHidden((prev) => mark(prev, entry.entryId, true));
      setLastRemoved(entry);
      setAnnouncement(wishAnnouncement(nameOf(entry), false));
      refresh();
    } else {
      setError(wishErrorMessage(nameOf(entry), reason));
    }
  }

  async function undo(entry: WishlistEntryView) {
    if (pending.has(entry.entryId)) return;
    dismissRef.current?.pause();
    setError(null);
    setPending((prev) => mark(prev, entry.entryId, true));
    let reason: Parameters<typeof wishErrorMessage>[1] = "failed";
    let entryId: string | null = null;
    try {
      const result = await addWishlistEntry(entry.cardVariantId, entry.languageCode);
      if (result.ok) entryId = result.entryId;
      else reason = result.reason;
    } catch {
      entryId = null;
    }
    setPending((prev) => mark(prev, entry.entryId, false));
    if (entryId) {
      const back = { ...entry, entryId };
      setRestored((prev) => [back, ...prev.filter((item) => item.entryId !== entryId)]);
      setHidden((prev) => mark(prev, entryId, false));
      setLastRemoved(null);
      setAnnouncement(wishAnnouncement(nameOf(entry), true));
      refresh();
    } else {
      setError(wishErrorMessage(nameOf(entry), reason));
    }
  }

  return (
    <div className={acervoStyles.root}>
      <header className={`${acervoStyles.hero} ${colecoesStyles.libraryHero}`}>
        <div className={acervoStyles.stageGlow} aria-hidden="true" />
        <HeroWishlist />
        {hasEntries && listCount !== null ? (
          <span className={acervoStyles.numeral} aria-hidden="true">
            {formatCount(listCount)}
          </span>
        ) : null}
        <div className={acervoStyles.heroContent}>
          <h1 className={acervoStyles.title}>Lista de desejos</h1>
          <p className={acervoStyles.lede}>As variantes que você quer conquistar. Só você vê esta lista.</p>
        </div>
        {hasEntries ? (
          <div className={acervoStyles.heroRow}>
            <WishlistLedger
              kpis={wishlistKpis({ summary, fallbackEntryCount: listCount ?? totalCount, format: formatCount, formatMoney: formatBrlWhole })}
            />
          </div>
        ) : null}
      </header>

      <div className={showToolbar ? `${regionStyles.region} ${acervoStyles.workspace}` : regionStyles.region}>
        {showToolbar && filterOptions ? (
          <>
            <WishlistToolbar filters={filters} options={filterOptions} />
            <WishlistFilterChips filters={filters} options={filterOptions} />
            {filtered && entries !== null ? (
              // Contagem do conjunto filtrado inteiro (total da 5350), nunca só da página.
              <p className={acervoStyles.resultCount} aria-live="polite">
                {wishlistResultSummary(totalCount, formatCount)}
              </p>
            ) : null}
          </>
        ) : null}
        {entries === null ? (
          <section className={acervoStyles.state} aria-labelledby="desejos-erro">
            <div className={`${acervoStyles.stateIcon} ${acervoStyles.stateIconDanger}`} aria-hidden="true">
              <AlertCircle className="h-6 w-6" />
            </div>
            <h2 id="desejos-erro" className={acervoStyles.stateTitle}>
              {filtered
                ? "Não foi possível aplicar os filtros agora"
                : filteredRead
                  ? "Não foi possível ordenar sua lista agora"
                  : "Não foi possível carregar sua lista de desejos"}
            </h2>
            <p className={acervoStyles.stateText}>Seus desejos estão guardados. Recarregue a página para tentar de novo.</p>
            <div className={acervoStyles.stateActions}>
              <Button asChild variant="outline" className={acervoStyles.stateAction}>
                <a href={wishlistHref(filters, page)}>Tentar novamente</a>
              </Button>
              {filteredRead ? (
                <Button asChild variant="ghost" className={acervoStyles.stateAction}>
                  <Link href={wishlistHref(NO_WISHLIST_FILTERS)}>Ver a lista completa</Link>
                </Button>
              ) : null}
            </div>
          </section>
        ) : visible === null ? null : filtered && visible.length === 0 && page === 1 && totalCount <= hidden.size ? (
          // W6: nenhum desejo atende aos filtros — estado próprio, nunca "lista vazia".
          <section className={acervoStyles.state} aria-labelledby="desejos-sem-resultado">
            <div className={acervoStyles.stateIcon} aria-hidden="true">
              <SearchX className="h-6 w-6" />
            </div>
            <h2 id="desejos-sem-resultado" className={acervoStyles.stateTitle}>
              Nenhum desejo encontrado
            </h2>
            <p className={acervoStyles.stateText}>
              {filters.query
                ? `Nenhum desejo da sua lista corresponde a “${filters.query}” com esses filtros.`
                : "Nenhum desejo da sua lista corresponde a esses filtros."}
            </p>
            <div className={acervoStyles.stateActions}>
              <Button asChild variant="outline" className={acervoStyles.stateAction}>
                <Link href={wishlistHref(clearedWishlistFilters(filters))} scroll={false}>
                  Limpar filtros
                </Link>
              </Button>
            </div>
          </section>
        ) : visible.length === 0 && page === 1 && totalCount <= hidden.size ? (
          <section className={acervoStyles.state} aria-labelledby="desejos-vazio">
            <div className={`${acervoStyles.stateIcon} ${styles.stateIconWish}`} aria-hidden="true">
              <Bookmark className="h-6 w-6" />
            </div>
            <h2 id="desejos-vazio" className={acervoStyles.stateTitle}>
              Sua lista de desejos está vazia
            </h2>
            <p className={acervoStyles.stateText}>
              Toque no marcador de uma carta — na Pesquisa ou no seu acervo — para guardar a variante que você quer. Você
              escolhe a variante; o idioma pode ser qualquer um.
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
          <section className={acervoStyles.state} aria-labelledby="desejos-pagina-vazia">
            <h2 id="desejos-pagina-vazia" className={acervoStyles.stateTitle}>
              Esta página não tem desejos
            </h2>
            <p className={acervoStyles.stateText}>Sua lista mudou desde a última visita.</p>
            <div className={acervoStyles.stateActions}>
              <Button asChild variant="outline" className={acervoStyles.stateAction}>
                <Link href={wishlistHref(filters)}>Voltar ao início</Link>
              </Button>
            </div>
          </section>
        ) : (
          <>
            <ul className={acervoStyles.grid} aria-label="Sua lista de desejos">
              {visible.map((entry) => {
                const owned = ownershipLabel(entry.ownership);
                return (
                  // CARD GRID UX STANDARDIZATION-01: mesma anatomia do Meu acervo e das coleções
                  // (arte 8:11 com preço na base, nome, Set · número e selos); o marcador da
                  // Lista de desejos fica no canto da arte, irmão dela.
                  <li
                    key={entry.entryId}
                    className={`${acervoStyles.tileSlot} ${styles.wishHost}`}
                    data-unavailable={!entry.variantAvailable || undefined}
                  >
                    <div className={acervoStyles.artWrap}>
                      <div className={acervoStyles.art}>
                        <CardArt src={entry.imageUrl} alt={entry.cardName} name={entry.cardName} caption={entry.caption} sizes={GRID_SIZES} />
                        <AcervoPriceTag price={prices?.[entry.cardVariantId] ?? null} now={priceNow} />
                      </div>
                    </div>
                    <button
                      type="button"
                      className={`${styles.wish} ${styles.wishCorner}`}
                      aria-pressed
                      aria-label={wishToggleLabel(entry.cardName, entry.variantLabel)}
                      data-pending={pending.has(entry.entryId) || undefined}
                      aria-busy={pending.has(entry.entryId) || undefined}
                      disabled={pending.has(entry.entryId)}
                      onClick={() => void remove(entry)}
                    >
                      <Bookmark className={styles.wishIcon} strokeWidth={2} aria-hidden="true" />
                    </button>
                    <div className={acervoStyles.meta}>
                      <div className={acervoStyles.name}>{entry.cardName}</div>
                      <div className={acervoStyles.sub}>
                        <span>{entry.caption}</span>
                      </div>
                      {/* FINAL VISUAL POLISH: selos numa linha própria, variante → idioma → posse,
                          lado a lado e quebrando linha só quando não cabem na largura do item. */}
                      <div className={styles.tagRow}>
                        {entry.variantLabel ? <span className={acervoStyles.tag}>{entry.variantLabel}</span> : null}
                        <span className={acervoStyles.tag}>{wishLanguageLabel(entry.languageCode)}</span>
                        {owned ? <span className={`${acervoStyles.tag} ${styles.tagOwned}`}>{owned}</span> : null}
                        {!entry.variantAvailable ? (
                          <span className={`${acervoStyles.tag} ${styles.tagWarning}`}>Indisponível no catálogo</span>
                        ) : null}
                      </div>
                    </div>
                  </li>
                );
              })}
            </ul>

            {totalPages > 1 ? (
              <nav className={acervoStyles.pagination} aria-label="Páginas da lista de desejos">
                {page > 1 ? (
                  <Button asChild variant="outline" size="sm">
                    <Link href={wishlistHref(filters, page - 1)}>Anterior</Link>
                  </Button>
                ) : null}
                <span>
                  Página {page} de {totalPages}
                </span>
                {page < totalPages ? (
                  <Button asChild variant="outline" size="sm">
                    <Link href={wishlistHref(filters, page + 1)}>Próxima</Link>
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
          <div
            ref={noticeRef}
            className="pointer-events-auto max-w-md bg-surface shadow-lg"
            role={error ? "alert" : undefined}
            onMouseEnter={() => holdNotice("hover", true)}
            onMouseLeave={() => holdNotice("hover", false)}
            onFocus={() => holdNotice("focus", true)}
            onBlur={(event) => {
              if (!event.currentTarget.contains(event.relatedTarget as Node | null)) holdNotice("focus", false);
            }}
          >
            {error ? (
              <InlineFeedback tone="error">
                <span className={styles.notice}>
                  <span className={styles.undo}>{error}</span>
                  <NoticeClose onClose={closeNotice} />
                </span>
              </InlineFeedback>
            ) : lastRemoved ? (
              <InlineFeedback tone="success">
                <span className={styles.notice}>
                  <span className={styles.undo}>
                    {nameOf(lastRemoved)} saiu da lista.
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      disabled={pending.has(lastRemoved.entryId)}
                      onClick={() => void undo(lastRemoved)}
                    >
                      Desfazer
                    </Button>
                  </span>
                  <NoticeClose onClose={closeNotice} />
                </span>
              </InlineFeedback>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}

/** Fechar o aviso (X) — botão nomeado, alcançável por teclado. */
function NoticeClose({ onClose }: { onClose: () => void }) {
  return (
    <Button type="button" variant="ghost" size="icon-sm" aria-label="Fechar aviso" title="Fechar" onClick={onClose}>
      <X className="h-3.5 w-3.5" aria-hidden="true" />
    </Button>
  );
}

function WishlistLedger({ kpis }: { kpis: WishlistKpi[] }) {
  return (
    <dl className={`${acervoStyles.ledger} ${styles.wishLedger}`} aria-label="Resumo da lista de desejos">
      {kpis.map((kpi) => (
        <div
          key={kpi.key}
          className={[acervoStyles.ledgerItem, kpi.lead ? acervoStyles.ledgerLead : "", kpi.value === null ? favStyles.ledgerPending : ""]
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

/** Elemento cenográfico do palco: duas cartas em leque com um marcador de traço fino. */
function HeroWishlist() {
  return (
    <svg className={colecoesStyles.heroShelf} viewBox="0 0 520 300" fill="none" aria-hidden="true" focusable="false">
      <g stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
        <rect x="150" y="40" width="150" height="208" rx="12" transform="rotate(-12 225 144)" />
        <rect x="250" y="34" width="150" height="208" rx="12" transform="rotate(8 325 138)" />
        <path d="M352 30v74l-22-16-22 16V30z" transform="rotate(8 325 138)" />
      </g>
    </svg>
  );
}
