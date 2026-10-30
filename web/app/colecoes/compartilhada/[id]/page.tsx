import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { Users } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { SharedCollectionView } from "@/components/colecoes/sharing/shared-collection-view";
import { collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
import { getSetLogoUrls } from "@/lib/colecoes/colecoes-queries";
import { type SharedPositionFilter, publicBinderHref } from "@/lib/colecoes/sharing";
import {
  getPublicCollectionBinder,
  getSharedCollection,
  getSharedCollectionBinder,
  getSharedCollectionCards,
  getSharedCollectionCover,
  getSharedCollectionPositions,
} from "@/lib/colecoes/sharing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Coleção compartilhada", robots: { index: false, follow: false } };

/**
 * Coleção vista pelo participante VIEWER — /colecoes/compartilhada/[id]
 * (V1-12). Mesma composição da página do titular; o fichário abre em
 * sobreposição (SHARED EXPERIENCE-01). /fichario segue como link direto.
 *
 * Acesso decidido só pelo banco (5312, só OWNER/VIEWER desde a v1.1). Quem
 * não participa — inclusive sem sessão — e chega aqui por um link antigo de
 * coleção publicada vai para a vitrine pública do fichário (5317); sem
 * publicação, 404 (inexistente, privada alheia, convite pendente ou recusado
 * são indistinguíveis). O titular é levado à página completa dele.
 * `noindex`.
 */
export default async function ColecaoCompartilhadaPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!isCollectionId(id)) notFound();
  const collectionId = id.toLowerCase();
  const rawPage = Number(Array.isArray(query.pagina) ? query.pagina[0] : query.pagina);
  const page = Number.isInteger(rawPage) && rawPage >= 1 && rawPage <= 2000 ? rawPage : 1;

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();

  const ver = Array.isArray(query.ver) ? query.ver[0] : query.ver;
  const filter: SharedPositionFilter = ver === "tenho" || ver === "faltam" ? ver : "todas";

  // Participante só existe com sessão (5312/5313/5314/5320 sem EXECUTE para anon).
  // Em paralelo: cabeçalho, fichário e a grade do Set (5320 devolve zero
  // linhas para coleção sem Set — custo desprezível). Só se a 5320 ainda não
  // existir no banco (ou a coleção não tiver Set) a galeria de cartas (5313)
  // é lida, depois.
  const [collection, binder, positionsRead, heroRead] = user
    ? await Promise.all([
        getSharedCollection(supabase, collectionId),
        getSharedCollectionBinder(supabase, collectionId),
        getSharedCollectionPositions(supabase, collectionId, filter),
        filter === "todas" ? Promise.resolve(null) : getSharedCollectionPositions(supabase, collectionId, "todas"),
      ])
    : [null, null, null, null];
  if (collection?.access === "OWNER") redirect(collectionHref(collectionId));
  if (!collection || collection.access !== "VIEWER") {
    // Não participa: a única coisa que pode ver é a vitrine pública, se houver.
    const published = await getPublicCollectionBinder(supabase, collectionId);
    if (published) redirect(publicBinderHref(collectionId));
    notFound();
  }

  const setGrid =
    collection.completionPolicy === "STANDARD_SET" && collection.cardSetCode !== null && positionsRead !== null && positionsRead.status !== "unavailable";
  const positions = setGrid
    ? {
        filter,
        page: positionsRead.status === "ok" ? positionsRead.page : null,
        hero:
          filter === "todas"
            ? positionsRead.status === "ok"
              ? positionsRead.page.items
              : []
            : heroRead?.status === "ok"
              ? heroRead.page.items
              : [],
      }
    : null;
  const cards = setGrid ? null : await getSharedCollectionCards(supabase, collectionId, page);

  const logoPath = collection.cardSetLogoPath;
  // Capa enviada pela titular (5328/5329) prevalece sobre o logo do Set, como na página dela.
  const [setLogoUrl, cover] = await Promise.all([
    logoPath ? getSetLogoUrls(supabase, [logoPath]).then((urls) => urls.get(logoPath) ?? null) : Promise.resolve(null),
    getSharedCollectionCover(supabase, collectionId),
  ]);
  const logoUrl = cover.logoUrl ?? setLogoUrl;

  const view = (
    <SharedCollectionView
      collection={collection}
      cards={cards}
      positions={positions}
      page={page}
      logoUrl={logoUrl}
      coverCode={cover.code}
      signedIn={Boolean(user)}
      binder={
        collection.access === "VIEWER" && binder?.hasBinder
          ? { columns: binder.columns, rows: binder.rows, pageCount: binder.pageCount, ownFilled: binder.ownFilled, identity: binder.identity }
          : null
      }
    />
  );

  return (
    <AppShell title={collection.name} icon={Users}>
      {view}
    </AppShell>
  );
}
