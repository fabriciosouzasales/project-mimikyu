import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { LibraryBig } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CollectionView, type MasterSetView } from "@/components/colecoes/colecoes/collection-view";
import { FreeCollectionView } from "@/components/colecoes/colecoes/free-collection-view";
import { PokedexCollectionView } from "@/components/colecoes/colecoes/pokedex-collection-view";
import { getAcervoItems } from "@/lib/colecoes/acervo-queries";
import { getMyBinderIdentity, getMyCollectionBinder } from "@/lib/colecoes/binder-queries";
import { collectionHref, isCollectionId, parsePositionFilter } from "@/lib/colecoes/colecoes";
import {
  attachCoverLogos,
  getAvailableGroupCount,
  getCoverLogoUrls,
  getLinkableCount,
  getMasterSetLinkableCount,
  getMasterSetOutOfScopeCount,
  getMyCollection,
  getMyCollectionPositions,
  getMyMasterSetHeroPositions,
  getMyMasterSetPositions,
  getMyPokedexPositions,
  getPokedexGenerationOptions,
  getSetLogoUrls,
} from "@/lib/colecoes/colecoes-queries";
import { isFreeCollection, parseFreePage, wantsPicker } from "@/lib/colecoes/free-collection";
import { wantsRegister } from "@/lib/colecoes/collection-add";
import {
  isPokedexCollection,
  parseGenerationFilter,
  parseJumpNumber,
  pokedexHeroLineup,
  pokedexHeroPicks,
} from "@/lib/colecoes/pokedex";
import { getMyPokedexFavorites, getPokedexSpeciesByNumbers } from "@/lib/pokedex/queries";
import {
  MASTER_SET_ADD_FROM_ACERVO_ENABLED,
  masterSetHeroOffset,
  masterSetTotalPages,
  parseMasterSetPage,
} from "@/lib/colecoes/master-set";
import { readVariantPrices } from "@/lib/pricing/variant-pricing-queries";
import { getMasterSetPositionPrices, getPokedexPositionPrices, getSetPositionPrices } from "@/lib/pricing/position-pricing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";
import { getMyWishedByCard, getMyWishedPositionKeys } from "@/lib/wishlist/wishlist-queries";
import { wishedCardIds } from "@/lib/wishlist/wishlist";
import { getMyCardFavoriteIds, getMyCardFavoritesByVariant } from "@/lib/favorites/card-favorites-queries";

export const metadata: Metadata = { title: "Coleção · Minhas coleções" };

/**
 * Uma coleção — /colecoes/colecoes/[id] (MY-COLLECTIONS-FRONTEND-01).
 *
 * Coleção alheia ou inexistente → 404 (os contratos devolvem zero linhas sem
 * distinguir os dois casos, de propósito — não enumera). Leituras em
 * paralelo: resumo (R1), cartas do Set com o filtro (R2), quantas cartas do
 * acervo podem entrar agora (R3, uma linha) e — só com filtro ativo — a R2 sem
 * filtro para os destaques do hero.
 */
export default async function ColecaoPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!isCollectionId(id)) notFound();
  const collectionId = id.toLowerCase();
  const filter = parsePositionFilter(query);

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  void getCachedUserProfile().catch(() => {});

  // R1 e as leituras de Set saem em paralelo (como antes). Numa Coleção livre,
  // R2/R3 devolvem zero linhas na primeira checagem (sem referência de Set) e
  // são descartadas — custo de uma busca por chave, sem segunda ida ao banco
  // para as coleções de Set. O hero mostra os destaques do Set inteiro, estável
  // entre Todas/Tenho/Faltam: com filtro, uma leitura extra da mesma R2.
  // Cabeçalho do Fichário Digital (5223, uma linha) sai junto: a entrada do
  // fichário no hero mostra o estado real (abrir / montar / o que falta).
  // Identidade do fichário (P3-A, 5245): leitura leve, também em paralelo — a
  // entrada mostra o nome próprio; sem a função no banco, cai no fallback.
  const [summary, positions, linkable, heroSource, binderRead, binderIdentity] = await Promise.all([
    getMyCollection(supabase, collectionId),
    getMyCollectionPositions(supabase, collectionId, filter),
    getLinkableCount(supabase, collectionId),
    filter === "todas" ? Promise.resolve(null) : getMyCollectionPositions(supabase, collectionId, "todas"),
    getMyCollectionBinder(supabase, collectionId),
    getMyBinderIdentity(supabase, collectionId),
  ]);
  if (summary === undefined) notFound();
  const binder = binderRead ? { ...binderRead, identity: binderIdentity } : null;

  if (summary !== null && isFreeCollection(summary)) {
    const page = parseFreePage(query);
    const [[withCover], items, available] = await Promise.all([
      attachCoverLogos(supabase, [summary]),
      getAcervoItems(supabase, {
        query: null,
        setCode: null,
        languageCode: null,
        collection: { kind: "collection", id: collectionId },
        storage: { kind: "all" }, // WHERE-04: sem filtro de local (visão integral)
        sort: "recentes",
        page,
        detail: null,
      }),
      summary.lifecycleStatus === "ACTIVE" ? getAvailableGroupCount(supabase) : Promise.resolve(null),
    ]);
    const freeSummary = withCover ?? summary;
    // V1-09: preço NM por variante (3983) dos grupos exibidos (≤ 48), junto com a capa.
    // PRICING TIMEOUT CORRECTION-01: leitura com estado (falha avisa; nunca vira "sem preço").
    // V1-10 (extensão): Favoritos das cartas exibidas — uma leitura em lote (a mesma do Acervo); falha = sem corações.
    const [coverLogoUrl, priceRead, favorites] = await Promise.all([
      freeSummary.coverLogoPath
        ? getCoverLogoUrls(supabase, [freeSummary.coverLogoPath]).then((urls) => urls.get(freeSummary.coverLogoPath as string) ?? null)
        : Promise.resolve(null),
      readVariantPrices(supabase, (items?.items ?? []).map((item) => item.cardVariantId)),
      items ? getMyCardFavoritesByVariant(supabase, items.items.map((item) => item.cardVariantId)) : Promise.resolve(null),
    ]);
    return (
      <AppShell title={summary.name} icon={LibraryBig}>
        <FreeCollectionView
          collection={freeSummary}
          items={items}
          page={page}
          available={available}
          openPicker={wantsPicker(query)}
          registerMode={wantsRegister(query)}
          coverLogoUrl={coverLogoUrl}
          userId={user.id}
          binder={binder}
          prices={priceRead.status === "unavailable" ? null : priceRead.prices}
          priceStatus={priceRead.status}
          priceNow={Date.now()}
          favorites={favorites}
        />
      </AppShell>
    );
  }

  // Completar a Pokédex (PKX-02): grade da 5204 (uma página, ordem nacional)
  // e gerações da 5201 em paralelo. R2/R3 acima devolvem zero linhas para esta
  // política e são descartadas.
  if (summary !== null && isPokedexCollection(summary)) {
    const generation = parseGenerationFilter(query);
    // UX-07: palco do hero — a equipe de 6 (favoritos do colecionador,
    // sorteados, completados pelos iniciais da geração). Favoritos em paralelo;
    // depois uma leitura curta só dos 6 números (sem SQL novo).
    const [positionsPage, options, [withCover], favorites] = await Promise.all([
      getMyPokedexPositions(supabase, collectionId, filter, generation),
      getPokedexGenerationOptions(supabase, collectionId),
      attachCoverLogos(supabase, [summary]),
      getMyPokedexFavorites(supabase),
    ]);
    const heroPicks = pokedexHeroPicks(favorites, options, generation);
    const pokedexSummary = withCover ?? summary;
    const coverPath = pokedexSummary.coverLogoPath;
    // AUDIT CORRECTION-01 (C2): a equipe do palco e a URL da capa dependem só
    // da primeira rodada — saem juntas, sem uma ida-e-volta extra em série.
    // V1-09 Fase B: preço do exemplar representante (5334 + 3983) sai junto, sem nova rodada em série.
    const [heroSpecies, pokedexCoverUrl, pokedexPrices] = await Promise.all([
      getPokedexSpeciesByNumbers(supabase, heroPicks),
      coverPath ? getCoverLogoUrls(supabase, [coverPath]).then((urls) => urls.get(coverPath) ?? null) : Promise.resolve(null),
      positionsPage ? getPokedexPositionPrices(supabase, collectionId, positionsPage.items) : Promise.resolve(null),
    ]);
    const heroLineup = pokedexHeroLineup(heroSpecies, heroPicks);
    return (
      <AppShell title={summary.name} icon={LibraryBig}>
        <PokedexCollectionView
          collection={pokedexSummary}
          coverLogoUrl={pokedexCoverUrl}
          userId={user.id}
          filter={filter}
          generation={generation}
          focusNumber={parseJumpNumber(query)}
          positions={positionsPage}
          options={options}
          heroLineup={heroLineup}
          binder={binder}
          registerMode={wantsRegister(query)}
          positionPrices={pokedexPrices?.prices ?? null}
          priceStatus={pokedexPrices?.status ?? null}
          priceNow={Date.now()}
        />
      </AppShell>
    );
  }

  const collection = summary;

  // Master Set (MASTER-SET-FRONTEND-PHASE-02): a grade vem de 5189/5198, uma
  // página por vez (`?pagina=`). O hero lê a última janela de "Todas", onde
  // ficam as secretas (MASTER-SET-HERO-SECRET-CARDS-CORRECTION-01); só reusa a
  // página exibida quando o Set inteiro cabe nela. R2/R3 acima devolvem zero
  // linhas para esta política e são descartadas.
  let master: MasterSetView | null = null;
  if (collection?.completionPolicy === "MASTER_SET") {
    const requested = parseMasterSetPage(query.pagina);
    const heroFromPage = filter === "todas" && requested === 1 && masterSetHeroOffset(collection.totalPositions) === 0;
    const [positionsPage, heroPage, outOfScope, masterLinkable] = await Promise.all([
      getMyMasterSetPositions(supabase, collectionId, filter, requested),
      heroFromPage ? Promise.resolve(null) : getMyMasterSetHeroPositions(supabase, collectionId, collection.totalPositions),
      getMasterSetOutOfScopeCount(supabase, collectionId),
      // "Adicionar cartas" em lote (5200): só lê com o recurso ligado.
      MASTER_SET_ADD_FROM_ACERVO_ENABLED ? getMasterSetLinkableCount(supabase, collectionId) : Promise.resolve(null),
    ]);
    // Página além do fim (o objetivo encolheu, link antigo): volta ao início do filtro.
    if (requested > 1 && positionsPage !== null && positionsPage.items.length === 0) {
      redirect(collectionHref(collectionId, filter));
    }
    master = {
      positions: positionsPage,
      heroPositions: (heroFromPage ? positionsPage : heroPage)?.items ?? [],
      page: positionsPage ? Math.min(requested, masterSetTotalPages(positionsPage.total)) : requested,
      outOfScopeCount: outOfScope,
      linkable: masterLinkable,
    };
  }

  const logoPath = collection?.cardSetLogoPath ?? null;
  // V1-09 Fase B: preço por posição (5333 + 3983) em paralelo com o logo — só a página exibida.
  // V1-11 W2: estado da Lista de desejos das cartas da página exibida — uma leitura em
  // lote (5346, por carta), só no Set padrão; falha = sem marcador.
  // V1-11 W3: no Master Set, estado por posição (carta + acabamento) da página exibida —
  // uma leitura em lote (5348); falha ou 5348 ausente no LIVE = sem marcador.
  // V1-10 (extensão): Favoritos das cartas da página exibida (Set padrão ou Master Set) —
  // uma leitura em lote por carta (5336); falha = sem corações. Favorito é da carta (C-82).
  const shownCardIds = master?.positions ? master.positions.items.map((position) => position.cardId) : (positions?.items ?? []).map((position) => position.cardId);
  const [logoUrl, positionPrices, wishedCards, wishedPositions, favoriteCards] = await Promise.all([
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null),
    collection === null
      ? Promise.resolve(null)
      : master !== null
        ? master.positions
          ? getMasterSetPositionPrices(supabase, collectionId, master.positions.items)
          : Promise.resolve(null)
        : positions
          ? getSetPositionPrices(supabase, collectionId, positions.items)
          : Promise.resolve(null),
    collection !== null && master === null && positions
      ? getMyWishedByCard(
          supabase,
          positions.items.map((position) => position.cardId),
        ).then(wishedCardIds)
      : Promise.resolve(null),
    master?.positions
      ? getMyWishedPositionKeys(
          supabase,
          master.positions.items.map((position) => position.cardId),
        )
      : Promise.resolve(null),
    collection !== null && shownCardIds.length > 0 ? getMyCardFavoriteIds(supabase, shownCardIds) : Promise.resolve(null),
  ]);

  return (
    <AppShell title={collection?.name ?? "Minhas coleções"} icon={LibraryBig}>
      {collection === null ? (
        <ReadFailure />
      ) : (
        <CollectionView
          collection={collection}
          filter={filter}
          positions={positions}
          heroPositions={(filter === "todas" ? positions : heroSource)?.items ?? []}
          linkable={linkable}
          logoUrl={logoUrl}
          master={master ? { ...master, wishedPositions } : null}
          binder={binder}
          registerMode={wantsRegister(query)}
          positionPrices={positionPrices?.prices ?? null}
          priceStatus={positionPrices?.status ?? null}
          priceNow={Date.now()}
          wishedCards={wishedCards}
          favoriteCards={favoriteCards}
        />
      )}
    </AppShell>
  );
}

function ReadFailure() {
  return (
    <div className="mx-auto max-w-md py-24 text-center" role="alert">
      <h1 className="font-heading text-2xl font-extrabold tracking-tight">Não conseguimos abrir esta coleção</h1>
      <p className="mt-2 text-sm text-muted-foreground">Nada foi perdido. Recarregue a página em instantes.</p>
    </div>
  );
}
