import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Library } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { AcervoView } from "@/components/colecoes/acervo/acervo-view";
import { acervoHref, parseAcervoState } from "@/lib/colecoes/acervo";
import {
  getAddLanguages,
  getAcervoFilterOptions,
  getAcervoItemDetail,
  getAcervoItems,
  getAcervoSummary,
} from "@/lib/colecoes/acervo-queries";
import { getPageConditionMix } from "@/lib/colecoes/acervo-condition-queries";
import { getCopyStorageContext, getMyStorageLocations } from "@/lib/colecoes/storage-locations-queries";
import { getMyCardFavoritesByVariant } from "@/lib/favorites/card-favorites-queries";
import { getMyWishedVariants } from "@/lib/wishlist/wishlist-queries";
import { getVariantPrices } from "@/lib/pricing/variant-pricing-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Meu acervo · Coleções" };

/** E0: auth.getUser + user_profile + is_admin, 5159–5161 + idiomas + 5219, preço + favoritos + desejos + condições (V1-16 UX-C). */
const ACERVO_RENDER_READS_BASE = 12;
/** E0: 5162 + local de cada exemplar (`physical_card`) + local padrão das coleções (`collection`). */
const ACERVO_RENDER_READS_DETAIL = 3;

/**
 * Meu acervo — /colecoes/acervo (MY-INVENTORY-IMPLEMENTATION-01, Etapa B).
 *
 * Acesso: qualquer usuário autenticado (sem sessão → /login). A autorização
 * real está no banco: as funções 5159–5162 exigem `auth.uid()`, resolvem o
 * dono no servidor e não existem para `anon`.
 *
 * Estado na URL (lib/colecoes/acervo.ts). Leituras em paralelo, uma de cada
 * por página: resumo (5160), página de grupos (5159), opções de filtro (5161),
 * idiomas aceitos no cadastro e — só com `?carta=` — o detalhe com os
 * exemplares (5162) e o contexto de localização (WHERE-03). Locais do usuário
 * (5219) uma vez só: alimentam o filtro "Localização física" (WHERE-04, 5220)
 * e o contexto do detalhe. Cadastro
 * (MY-INVENTORY-ACTIONS-01) e localização dos exemplares (5024): `actions.ts`.
 */
export default async function AcervoPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const state = parseAcervoState(params);
  const renderStartedAt = Date.now();

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  void getCachedUserProfile().catch(() => {});

  // Uma leitura da 5219 por renderização, compartilhada pelo filtro e pelo detalhe.
  const locationsRead = getMyStorageLocations(supabase);

  const [summary, page, options, detail, addLanguages, storage, locations] = await Promise.all([
    getAcervoSummary(supabase),
    getAcervoItems(supabase, state),
    getAcervoFilterOptions(supabase),
    state.detail ? getAcervoItemDetail(supabase, state.detail) : Promise.resolve(undefined),
    getAddLanguages(supabase),
    // WHERE-03: local de cada exemplar + locais do usuário, só com o detalhe aberto.
    state.detail ? getCopyStorageContext(supabase, state.detail.cardVariantId, locationsRead) : Promise.resolve(null),
    locationsRead,
  ]);

  // Página além do fim (link antigo, cartas removidas): a 5159 não devolve o total sem
  // linhas, então volta para a primeira página em vez de mostrar um vazio enganoso.
  if (page && page.items.length === 0 && state.page > 1) {
    redirect(acervoHref({ ...state, page: 1 }));
  }

  // V1-09: preço NM por variante (3983) da página exibida (≤ 48 grupos) e do
  // exemplar aberto, numa leitura só. Falha = sem preço, nunca erro na página.
  // V1-10: carta + estado favorito das variantes da página, em paralelo com o preço
  // (uma leitura em lote, 5336). Falha = grade sem corações, nunca erro na página.
  const pageVariantIds = (page?.items ?? []).map((item) => item.cardVariantId);
  // V1-11 W1: variantes da página na Lista de desejos (5346), na mesma rodada paralela.
  // V1-16 UX-C (G1): exemplares não-NM das variantes da página (RLS), na mesma rodada.
  // Falha = grade sem chips de condição, nunca erro na página.
  const [prices, favorites, wishedVariants, conditionMix] = await Promise.all([
    getVariantPrices(supabase, [...pageVariantIds, state.detail?.cardVariantId]),
    getMyCardFavoritesByVariant(supabase, pageVariantIds),
    getMyWishedVariants(supabase, pageVariantIds),
    getPageConditionMix(supabase, page?.items ?? [], addLanguages),
  ]);
  const priceNow = Date.now();

  // INCIDENT-01 E0: uma linha por renderização completa da página (sem dados do usuário). Com as
  // linhas das mutações (`acervo.add`, `acervo.remove`, `colecoes.copy_storage`, `acervo.move`), mostra
  // quantas renderizações cada operação provoca. `plannedReads` = leituras ao banco previstas
  // pelo caminho do código (3 de sessão/casca + 5 da 1ª rodada + 3 com o detalhe + 4 da 2ª rodada).
  console.info(
    JSON.stringify({
      scope: "acervo.render",
      ms: priceNow - renderStartedAt,
      detail: state.detail !== null,
      plannedReads: ACERVO_RENDER_READS_BASE + (state.detail ? ACERVO_RENDER_READS_DETAIL : 0),
    }),
  );

  return (
    <AppShell title="Meu acervo" icon={Library}>
      <AcervoView
        state={state}
        summary={summary}
        page={page}
        options={options}
        detail={detail}
        addLanguages={addLanguages}
        storage={storage}
        locations={locations}
        prices={prices}
        priceNow={priceNow}
        favorites={favorites}
        wishedVariants={wishedVariants}
        conditionMix={conditionMix}
      />
    </AppShell>
  );
}
