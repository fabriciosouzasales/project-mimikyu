import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { BrandLogo } from "@/components/brand-logo";
import { PublicBinderShare } from "@/components/colecoes/sharing/public-binder-share";
import { PublicBinderShowcase } from "@/components/colecoes/sharing/public-binder-showcase";
import shareStyles from "@/components/colecoes/sharing/share.module.css";
import { resolveFinish } from "@/lib/colecoes/binder-finish";
import { COLECOES_PATH, isCollectionId } from "@/lib/colecoes/colecoes";
import { getSetLogoUrls } from "@/lib/colecoes/colecoes-queries";
import { sharedBatchStart } from "@/lib/colecoes/sharing";
import { getPublicCollectionBinder, getPublicCollectionBinderPages, getSharedCollectionCover } from "@/lib/colecoes/sharing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Fichário · MMKYU Collector", robots: { index: false, follow: false } };

/**
 * Vitrine pública do Fichário Digital — /fichario/[id] (V1-12 PUBLIC BINDER
 * EXPERIENCE). Sem login, por link compartilhável.
 *
 * Autorização só no banco (5317/5318): coleção PUBLIC e ativa. Privada,
 * arquivada ou inexistente → 404, indistinguíveis. Nada da coleção além do
 * fichário: sem galeria, progresso, acervo ou ajustes — inclusive para o
 * titular e participantes, que veem aqui exatamente o que o público vê.
 * `noindex`: público por link, não para buscadores.
 */
export default async function FicharioPublicoPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  if (!isCollectionId(id)) notFound();
  const collectionId = id.toLowerCase();

  const supabase = await createClient();
  const [binder, auth] = await Promise.all([getPublicCollectionBinder(supabase, collectionId), getCachedUser()]);
  if (!binder) notFound();

  const grid = binder.binder;
  const rawPage = Number(Array.isArray(query.pagina) ? query.pagina[0] : query.pagina);
  const page = grid && Number.isInteger(rawPage) && rawPage >= 1 && rawPage <= grid.pageCount ? rawPage : 0;

  const logoPath = binder.cardSetLogoPath;
  const [initialPages, logos, cover] = await Promise.all([
    grid && grid.pageCount > 0
      ? getPublicCollectionBinderPages(supabase, collectionId, sharedBatchStart(Math.max(1, page)), grid.columns, grid.rows)
      : Promise.resolve([]),
    logoPath ? getSetLogoUrls(supabase, [logoPath]) : Promise.resolve(new Map<string, string>()),
    // Capa enviada (5328/5329): prevalece sobre o logo do Set, como na página do titular.
    getSharedCollectionCover(supabase, collectionId),
  ]);
  const signedIn = Boolean(auth.data.user);

  return (
    <div className={`binder-nav-01-scope ${shareStyles.publicBinderFrame}`}>
      <header className={shareStyles.publicBinderTop}>
        {/* Identidade oficial (logo completa, troca por tema) — leva à entrada do produto. */}
        <Link href={signedIn ? "/" : "/login"} className={shareStyles.brand} aria-label="MMKYU Collector — página inicial">
          <BrandLogo className="h-7 w-auto sm:h-8" />
        </Link>
        <div className={shareStyles.publicBinderActions}>
          <PublicBinderShare collectionId={collectionId} title={binder.binderName ?? binder.name} />
          <Link
            href={signedIn ? COLECOES_PATH : "/login"}
            className="text-sm font-semibold text-primary-ink underline-offset-4 hover:underline"
          >
            {signedIn ? "Minhas coleções" : "Entrar"}
          </Link>
        </div>
      </header>
      <main>
        <PublicBinderShowcase
          binder={binder}
          finish={resolveFinish(collectionId, binder.coverFinish)}
          logoUrl={cover.logoUrl ?? (logoPath ? logos.get(logoPath) ?? null : null)}
          coverCode={cover.code}
          initialPage={page}
          initialPages={initialPages}
          createHref={signedIn ? COLECOES_PATH : "/cadastro"}
        />
      </main>
    </div>
  );
}
