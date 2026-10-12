import { Images } from "lucide-react";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ArtworkAdminView } from "@/components/pokedex/admin/artwork-admin-view";
import { parseArtworkStatusParam, parsePageParam } from "@/lib/pokedex/admin-artwork-format";
import { getArtworkAdminPage, getArtworkCoverage } from "@/lib/pokedex/admin-artwork";
import { parseQueryParam } from "@/lib/pokedex/format";
import { POKEDEX_QUERY_MAX_LENGTH } from "@/lib/pokedex/queries";

/** Reprocessamento pontual (Server Action desta rota): uma espécie leva ~1–3 s; folga para a origem lenta. */
export const maxDuration = 60;

/**
 * Pokédex → Cadastro → Imagens (Pokédex P2 Lote E) — só administradores.
 *
 * Guarda de servidor compartilhada (`requireCatalogoAdmin`: sem sessão →
 * /login; sem papel admin → acesso restrito, nada é lido). A autorização
 * real está no banco: as funções da Query 6132 recusam quem não é admin.
 *
 * Estado na URL: `?q=`, `?status=importadas|pendentes|com-falha`, `?pagina=`.
 */
export default async function PokedexImagensPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Imagens", Images);
  if (denied) return denied;

  const params = await searchParams;
  const query = parseQueryParam(params.q, POKEDEX_QUERY_MAX_LENGTH);
  const status = parseArtworkStatusParam(params.status);
  const page = parsePageParam(params.pagina);

  const [coverage, result] = await Promise.all([
    getArtworkCoverage(supabase),
    getArtworkAdminPage(supabase, { status, query, page }),
  ]);

  // Página além do fim (link antigo ou filtro que encolheu): volta à primeira.
  if (result && page > 0 && result.rows.length === 0) {
    const next = new URLSearchParams();
    if (query) next.set("q", query);
    if (typeof params.status === "string" && status) next.set("status", params.status);
    const search = next.toString();
    redirect(search ? `/pokedex/imagens?${search}` : "/pokedex/imagens");
  }

  return (
    <AppShell title="Imagens" icon={Images}>
      <ArtworkAdminView coverage={coverage} result={result} query={query} status={status} page={page} />
    </AppShell>
  );
}
