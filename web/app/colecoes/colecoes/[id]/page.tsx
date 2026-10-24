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
  getMyMasterSetPositions,
  getMyPokedexPositions,
  getPokedexGenerationOptions,
  getSetLogoUrls,
} from "@/lib/colecoes/colecoes-queries";
import { isFreeCollection, parseFreePage, wantsPicker } from "@/lib/colecoes/free-collection";
import {
  isPokedexCollection,
  parseGenerationFilter,
  parseJumpNumber,
  pokedexHeroLineup,
  pokedexHeroPicks,
} from "@/lib/colecoes/pokedex";
import { getMyPokedexFavorites, getPokedexSpeciesByNumbers } from "@/lib/pokedex/queries";
import { MASTER_SET_ADD_FROM_ACERVO_ENABLED, masterSetTotalPages, parseMasterSetPage } from "@/lib/colecoes/master-set";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

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
    const coverLogoUrl = freeSummary.coverLogoPath
      ? (await getCoverLogoUrls(supabase, [freeSummary.coverLogoPath])).get(freeSummary.coverLogoPath) ?? null
      : null;
    return (
      <AppShell title={summary.name} icon={LibraryBig}>
        <FreeCollectionView
          collection={freeSummary}
          items={items}
          page={page}
          available={available}
          openPicker={wantsPicker(query)}
          coverLogoUrl={coverLogoUrl}
          userId={user.id}
          binder={binder}
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
    const [heroSpecies, pokedexCoverUrl] = await Promise.all([
      getPokedexSpeciesByNumbers(supabase, heroPicks),
      coverPath ? getCoverLogoUrls(supabase, [coverPath]).then((urls) => urls.get(coverPath) ?? null) : Promise.resolve(null),
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
        />
      </AppShell>
    );
  }

  const collection = summary;

  // Master Set (MASTER-SET-FRONTEND-PHASE-02): a grade vem de 5189/5198, uma
  // página por vez (`?pagina=`); o hero usa a primeira página de "Todas" (sem
  // leitura extra quando é a própria página exibida). R2/R3 acima devolvem
  // zero linhas para esta política e são descartadas.
  let master: MasterSetView | null = null;
  if (collection?.completionPolicy === "MASTER_SET") {
    const requested = parseMasterSetPage(query.pagina);
    const [positionsPage, heroPage, outOfScope, masterLinkable] = await Promise.all([
      getMyMasterSetPositions(supabase, collectionId, filter, requested),
      filter === "todas" && requested === 1 ? Promise.resolve(null) : getMyMasterSetPositions(supabase, collectionId, "todas", 1),
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
      heroPositions: (filter === "todas" && requested === 1 ? positionsPage : heroPage)?.items ?? [],
      page: positionsPage ? Math.min(requested, masterSetTotalPages(positionsPage.total)) : requested,
      outOfScopeCount: outOfScope,
      linkable: masterLinkable,
    };
  }

  const logoPath = collection?.cardSetLogoPath ?? null;
  const logoUrl = logoPath ? (await getSetLogoUrls(supabase, [logoPath])).get(logoPath) ?? null : null;

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
          master={master}
          binder={binder}
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
