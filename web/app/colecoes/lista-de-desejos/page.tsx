import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Bookmark } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { WishlistView, type WishlistEntryView } from "@/components/wishlist/wishlist-view";
import { formatCollectorNumber } from "@/lib/colecoes/acervo";
import { getVariantPrices, pricesToRecord } from "@/lib/pricing/variant-pricing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";
import { WISHLIST_PAGE_SIZE, needsFilteredWishlistRead, parsePageParam, parseWishlistFilters } from "@/lib/wishlist/wishlist";
import {
  getMyWishlistFilterOptions,
  getMyWishlistFilteredPage,
  getMyWishlistPage,
  getMyWishlistSummary,
} from "@/lib/wishlist/wishlist-queries";

export const metadata: Metadata = { title: "Lista de desejos · Coleções" };

/**
 * Lista de desejos — /colecoes/lista-de-desejos (V1-11 W1).
 *
 * Página pessoal e privada: sem sessão → /login; a autorização real está no banco
 * (`get_my_wishlist`/`get_my_wishlist_summary`, Queries 5346/5347, resolvem o dono por
 * `auth.uid()`). Três leituras em paralelo, cada uma falha sozinha: a página (60 por
 * página, mais recentes primeiro), os indicadores e — depois da página — o preço NM por
 * variante (3983, a mesma etiqueta do V1-09). Imagens: mesma origem pública da Pesquisa
 * (bucket `card-front`, frente primária pt-BR ou en).
 *
 * W6 (filtros, 5350; ordenação, 5351): o estado vive na URL (q, set, raridade, idioma, acervo,
 * ordem, pagina). Sem filtro e na ordem padrão ("Mais recentes"), a leitura é a mesma da W1
 * (`get_my_wishlist`); com filtro ou "Set e número" (`ordem=set`), `get_my_wishlist_filtered`
 * aplica os critérios ao conjunto inteiro do usuário ANTES de paginar — total e páginas são do
 * resultado filtrado, nunca da página carregada. As opções (só Card Sets, raridades e idiomas
 * presentes na lista) vêm de `get_my_wishlist_filter_options`; se indisponíveis, a barra some e a
 * página continua como na W1.
 */
export default async function WishlistPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const page = parsePageParam(params.pagina);
  const filters = parseWishlistFilters(params);
  const filtered = needsFilteredWishlistRead(filters);

  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  const supabase = await createClient();
  const [result, summary, filterOptions] = await Promise.all([
    filtered ? getMyWishlistFilteredPage(supabase, filters, page) : getMyWishlistPage(supabase, page),
    getMyWishlistSummary(supabase),
    getMyWishlistFilterOptions(supabase),
  ]);
  const prices = result ? await getVariantPrices(supabase, result.entries.map((entry) => entry.cardVariantId)) : null;
  const priceNow = Date.now();

  const publicUrl = (path: string | null) => (path ? supabase.storage.from("card-front").getPublicUrl(path).data.publicUrl : null);
  const entries: WishlistEntryView[] | null = result
    ? result.entries.map((entry) => ({
        entryId: entry.entryId,
        cardVariantId: entry.cardVariantId,
        cardName: entry.cardName,
        // CARD GRID UX STANDARDIZATION-01: mesma legenda das demais grades ("ME2 · 125/094").
        caption: [entry.cardSetCode.toUpperCase(), entry.collectorNumber ? formatCollectorNumber(entry.collectorNumber, entry.collectorTotal) : null]
          .filter(Boolean)
          .join(" · "),
        variantLabel: entry.variantLabel,
        variantAvailable: entry.variantAvailable,
        languageCode: entry.languageCode,
        ownership: entry.ownership,
        imageUrl: publicUrl(entry.imagePathPt) ?? publicUrl(entry.imagePathEn),
      }))
    : null;

  const totalCount = result?.totalCount ?? 0;
  const totalPages = Math.max(1, Math.ceil(totalCount / WISHLIST_PAGE_SIZE));

  return (
    <AppShell title="Lista de desejos" icon={Bookmark}>
      <WishlistView
        entries={entries}
        totalCount={totalCount}
        summary={summary}
        prices={pricesToRecord(prices)}
        priceNow={priceNow}
        page={page}
        totalPages={totalPages}
        filters={filters}
        filterOptions={filterOptions}
      />
    </AppShell>
  );
}
