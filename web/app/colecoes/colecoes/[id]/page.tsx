import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { LibraryBig } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CollectionView } from "@/components/colecoes/colecoes/collection-view";
import { FreeCollectionView } from "@/components/colecoes/colecoes/free-collection-view";
import { getAcervoItems } from "@/lib/colecoes/acervo-queries";
import { isCollectionId, parsePositionFilter } from "@/lib/colecoes/colecoes";
import {
  attachCoverLogos,
  getAvailableGroupCount,
  getCoverLogoUrls,
  getLinkableCount,
  getMyCollection,
  getMyCollectionPositions,
  getSetLogoUrls,
} from "@/lib/colecoes/colecoes-queries";
import { isFreeCollection, parseFreePage, wantsPicker } from "@/lib/colecoes/free-collection";
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
  const [summary, positions, linkable, heroSource] = await Promise.all([
    getMyCollection(supabase, collectionId),
    getMyCollectionPositions(supabase, collectionId, filter),
    getLinkableCount(supabase, collectionId),
    filter === "todas" ? Promise.resolve(null) : getMyCollectionPositions(supabase, collectionId, "todas"),
  ]);
  if (summary === undefined) notFound();

  if (summary !== null && isFreeCollection(summary)) {
    const page = parseFreePage(query);
    const [[withCover], items, available] = await Promise.all([
      attachCoverLogos(supabase, [summary]),
      getAcervoItems(supabase, {
        query: null,
        setCode: null,
        languageCode: null,
        collection: { kind: "collection", id: collectionId },
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
        />
      </AppShell>
    );
  }

  const collection = summary;

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
