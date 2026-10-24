import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { BookOpen } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { BinderView } from "@/components/colecoes/fichario/binder-view";
import { canJoinExistingBinder, parsePageParam, readBatchStart } from "@/lib/colecoes/binder";
import {
  getMyBinderIdentity,
  getMyBinderJoinCandidates,
  getMyBinderSpeciesReferenceState,
  getMyCollectionBinder,
  getMyCollectionBinderPages,
} from "@/lib/colecoes/binder-queries";
import { type SpeciesReferenceState, mayHaveSpeciesReferences } from "@/lib/colecoes/binder-species";
import { isCollectionId } from "@/lib/colecoes/colecoes";
import { getMyCollection } from "@/lib/colecoes/colecoes-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Fichário · Minhas coleções" };

/**
 * Fichário Digital de uma coleção — /colecoes/colecoes/[id]/fichario (P2-B).
 *
 * Leituras em paralelo: resumo da coleção (R1 — nome e acabamento da capa) e
 * cabeçalho do fichário (5223). Com fichário, o primeiro lote de até quatro
 * páginas que contém `?pagina=` sai no servidor; o restante é lido sob demanda
 * pelo cliente, em lotes do mesmo tamanho. Coleção alheia ou inexistente → 404
 * (o banco não distingue os dois casos, de propósito).
 */
export default async function FicharioPage({
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
  // Identidade do fichário (P3-A, 5245) em paralelo: contracapa e título já
  // saem com o nome próprio na primeira pintura (sem piscar).
  const [summary, headerRead, identity] = await Promise.all([
    getMyCollection(supabase, collectionId),
    getMyCollectionBinder(supabase, collectionId),
    getMyBinderIdentity(supabase, collectionId),
  ]);
  if (summary === undefined || headerRead === undefined) notFound();
  const header = headerRead ? { ...headerRead, identity } : null;

  if (summary === null || header === null) {
    return (
      <AppShell title="Fichário" icon={BookOpen}>
        <ReadFailure />
      </AppShell>
    );
  }

  // Sem ?pagina= o fichário abre pela capa (lote 1 já vem junto, para abrir na hora).
  // Referências de espécie (5259): só fichários de Pokédex (ou convidadas) leem; os demais não fazem chamada nova.
  const speciesReferences = mayHaveSpeciesReferences(header);
  let initialAnchor = 0;
  let initialPages = null;
  let speciesState: SpeciesReferenceState | null = null;
  if (header.hasBinder && header.pageCount > 0) {
    initialAnchor = query.pagina === undefined ? 0 : parsePageParam(query.pagina, header.pageCount);
    [initialPages, speciesState] = await Promise.all([
      getMyCollectionBinderPages(supabase, collectionId, readBatchStart(Math.max(1, initialAnchor)), { speciesReferences }),
      speciesReferences ? getMyBinderSpeciesReferenceState(supabase, collectionId) : Promise.resolve(null),
    ]);
    if (initialPages === undefined) notFound();
  }

  // Sem fichário, mas com um fichário digital no mesmo local físico (5230): a
  // página oferece primeiro usar o existente. Falha na leitura = cai na montagem.
  const joinCandidates = canJoinExistingBinder(header) ? await getMyBinderJoinCandidates(supabase, collectionId) : null;

  return (
    <AppShell title={header.hasBinder && identity ? identity.effectiveName : summary.name} icon={BookOpen}>
      <BinderView
        collection={{
          id: collectionId,
          name: summary.name,
          finish: summary.finish,
          setName: summary.cardSetName,
          setCode: summary.cardSetCode,
          policy: summary.completionPolicy,
        }}
        header={header}
        initialAnchor={initialAnchor}
        initialPages={initialPages}
        speciesState={speciesState}
        joinCandidates={joinCandidates ?? null}
      />
    </AppShell>
  );
}

function ReadFailure() {
  return (
    <div className="mx-auto max-w-md py-24 text-center" role="alert">
      <h1 className="font-heading text-2xl font-extrabold tracking-tight">Não conseguimos abrir o fichário</h1>
      <p className="mt-2 text-sm text-muted-foreground">Nada foi perdido. Recarregue a página em instantes.</p>
    </div>
  );
}
