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
import { getCopyStorageContext } from "@/lib/colecoes/storage-locations-queries";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

export const metadata: Metadata = { title: "Meu acervo · Coleções" };

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
 * exemplares (5162) e o contexto de localização (WHERE-03). Cadastro
 * (MY-INVENTORY-ACTIONS-01) e localização dos exemplares (5024): `actions.ts`.
 */
export default async function AcervoPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const state = parseAcervoState(params);

  const supabase = await createClient();
  const {
    data: { user },
  } = await getCachedUser();
  if (!user) redirect("/login");

  void getCachedUserProfile().catch(() => {});

  const [summary, page, options, detail, addLanguages, storage] = await Promise.all([
    getAcervoSummary(supabase),
    getAcervoItems(supabase, state),
    getAcervoFilterOptions(supabase),
    state.detail ? getAcervoItemDetail(supabase, state.detail) : Promise.resolve(undefined),
    getAddLanguages(supabase),
    // WHERE-03: local de cada exemplar + locais do usuário, só com o detalhe aberto.
    state.detail ? getCopyStorageContext(supabase, state.detail.cardVariantId) : Promise.resolve(null),
  ]);

  // Página além do fim (link antigo, cartas removidas): a 5159 não devolve o total sem
  // linhas, então volta para a primeira página em vez de mostrar um vazio enganoso.
  if (page && page.items.length === 0 && state.page > 1) {
    redirect(acervoHref({ ...state, page: 1 }));
  }

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
      />
    </AppShell>
  );
}
