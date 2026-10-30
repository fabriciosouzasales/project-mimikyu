import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { LibraryBig } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { LibraryView } from "@/components/colecoes/colecoes/library-view";
import { getAcervoFilterOptions } from "@/lib/colecoes/acervo-queries";
import { LIBRARY_MODE_COOKIE, libraryHref, parseLibraryPage, resolveLibraryMode } from "@/lib/colecoes/colecoes";
import {
  attachCoverLogos,
  getCoverLogoUrls,
  getMyArchivedCollections,
  getMyArchivedCount,
  getMyCollections,
  getMyStorageLocations,
  getSetLogoUrls,
} from "@/lib/colecoes/colecoes-queries";
import { archivedLibraryHref, isArchivedView } from "@/lib/colecoes/collection-lifecycle";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Minhas coleções · Coleções" };

/**
 * Minhas coleções — /colecoes/colecoes (MY-COLLECTIONS-FRONTEND-01).
 *
 * Acesso: qualquer usuário autenticado (sem sessão → /login). A autorização
 * real está no banco (5166–5170: `auth.uid()`, EXECUTE só `authenticated`).
 *
 * Leituras em paralelo: página da Biblioteca (R1, 5168), locais do próprio
 * Inventory (RLS select-own — decide D-A na criação) e os Sets que já estão
 * no acervo (5161, para sugerir primeiro no seletor de Set).
 */
export default async function ColecoesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const pageNumber = parseLibraryPage(params);
  // Modo de visualização (NS-17): URL › cookie do navegador › Cards. Sem banco.
  const mode = resolveLibraryMode(params, (await cookies()).get(LIBRARY_MODE_COOKIE)?.value);

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  void getCachedUserProfile().catch(() => {});

  // `?arquivadas=1` (V1-04): estante das coleções arquivadas, só leitura e sem reordenar.
  const archivedView = isArchivedView(params);

  const [rawPage, locations, options] = await Promise.all([
    archivedView ? getMyArchivedCollections(supabase, pageNumber) : getMyCollections(supabase, pageNumber),
    archivedView ? Promise.resolve(null) : getMyStorageLocations(supabase),
    archivedView ? Promise.resolve(null) : getAcervoFilterOptions(supabase),
  ]);
  // Entrada "Arquivadas" da estante ativa: reaproveita o total de ativas já lido.
  const archivedCount = archivedView || !rawPage ? null : await getMyArchivedCount(supabase, rawPage.total);

  // Coleção livre com capa enviada (desligado até 5176–5178 no LIVE).
  const page = rawPage ? { ...rawPage, items: await attachCoverLogos(supabase, rawPage.items) } : null;

  // Página além do fim (link antigo): volta para a primeira em vez de um vazio enganoso.
  if (page && page.items.length === 0 && pageNumber > 1) redirect(archivedView ? archivedLibraryHref(1) : libraryHref(1));

  // Uma chamada para todos os logos da página (bucket privado; sem acesso → mapa vazio).
  const [setLogos, coverLogos] = page
    ? await Promise.all([
        getSetLogoUrls(supabase, page.items.map((item) => item.cardSetLogoPath)),
        getCoverLogoUrls(supabase, page.items.map((item) => item.coverLogoPath)),
      ])
    : [new Map<string, string>(), new Map<string, string>()];
  const logoUrls = new Map<string, string>([...setLogos, ...coverLogos]);

  const ownedSets = (options?.sets ?? []).map((set) => ({ code: set.value, name: set.label, count: set.count }));

  return (
    <AppShell title={archivedView ? "Coleções arquivadas" : "Minhas coleções"} icon={LibraryBig}>
      <LibraryView
        page={page}
        pageNumber={pageNumber}
        locations={locations}
        ownedSets={ownedSets}
        logoUrls={logoUrls}
        mode={mode}
        view={archivedView ? "archived" : "active"}
        archivedCount={archivedCount}
      />
    </AppShell>
  );
}
