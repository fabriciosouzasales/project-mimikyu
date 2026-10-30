import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { BookOpen } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { SharedBinderWorkspace } from "@/components/colecoes/sharing/shared-binder-workspace";
import { resolveFinish } from "@/lib/colecoes/binder-finish";
import { collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
import { sharedBatchStart, sharedCollectionHref } from "@/lib/colecoes/sharing";
import { getSharedCollection, getSharedCollectionBinder, getSharedCollectionBinderPages } from "@/lib/colecoes/sharing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Fichário compartilhado", robots: { index: false, follow: false } };

/**
 * Fichário de uma coleção compartilhada, só leitura —
 * /colecoes/compartilhada/[id]/fichario (V1-12 SHARING CORRECTION).
 *
 * Exige sessão e participação ACTIVE (5314/5315 negam PUBLIC, convite
 * pendente/recusado, ex-participante e estranho — tudo vira 404, como a
 * coleção inexistente). O titular vai para o fichário completo dele. Sem
 * fichário, volta para a coleção compartilhada. O primeiro lote de páginas
 * sai no servidor; o resto o cliente lê sob demanda.
 */
export default async function FicharioCompartilhadoPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!isCollectionId(id)) notFound();
  const collectionId = id.toLowerCase();

  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  const [collection, binder] = await Promise.all([getSharedCollection(supabase, collectionId), getSharedCollectionBinder(supabase, collectionId)]);
  if (!collection) notFound();
  if (collection.access === "OWNER") redirect(`${collectionHref(collectionId)}/fichario`);
  if (collection.access !== "VIEWER" || !binder) notFound();
  if (!binder.hasBinder) redirect(sharedCollectionHref(collectionId));

  const rawPage = Number(Array.isArray(query.pagina) ? query.pagina[0] : query.pagina);
  const anchor = Number.isInteger(rawPage) && rawPage >= 1 && rawPage <= Math.max(1, binder.pageCount) ? rawPage : 1;
  const initialPages =
    binder.pageCount > 0 ? await getSharedCollectionBinderPages(supabase, collectionId, sharedBatchStart(anchor), binder.columns, binder.rows) : [];

  return (
    <AppShell title={collection.name} icon={BookOpen}>
      <SharedBinderWorkspace
        variant="page"
        titleId="fichario-compartilhado-titulo"
        collectionId={collectionId}
        collectionName={collection.name}
        ownerDisplayName={collection.ownerDisplayName}
        finish={resolveFinish(collectionId, collection.coverFinish)}
        identity={binder.identity}
        columns={binder.columns}
        rows={binder.rows}
        pageCount={binder.pageCount}
        ownFilled={binder.ownFilled}
        initialAnchor={anchor}
        initialPages={initialPages}
        backHref={sharedCollectionHref(collectionId)}
      />
    </AppShell>
  );
}
