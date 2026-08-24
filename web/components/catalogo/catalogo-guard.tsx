import { redirect } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import type { ReactElement } from "react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Alert } from "@/components/ui/alert";
import { createClient } from "@/lib/supabase/server";
import { getCachedIsAdmin, getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";
import type { SupabaseClient, User } from "@supabase/supabase-js";

type CatalogoGuardResult =
  | { denied: ReactElement; supabase: SupabaseClient; user: User; isAdmin: false }
  | { denied: null; supabase: SupabaseClient; user: User; isAdmin: true };

/**
 * Guarda de servidor compartilhada por todas as rotas do Catálogo
 * Editorial (ADR-022 — todo o módulo é restrito a administradores):
 * sem sessão -> redireciona para /login; sem papel administrativo ->
 * alerta de acesso restrito, sem renderizar nenhum conteúdo real.
 *
 * A autorização de verdade está nas políticas de RLS catalog_admin_select
 * (Query 274) — esta função só decide o que MOSTRAR na interface; um
 * usuário comum que contornasse esta checagem ainda não conseguiria ler
 * nenhum dado do catálogo pela API.
 *
 * Uso: `const { denied, supabase } = await requireCatalogoAdmin("Jogos");
 * if (denied) return denied;` — mesmo padrão já validado em produção em
 * /usuarios/page.tsx, extraído aqui para reuso nas seis rotas do módulo.
 *
 * `icon` opcional (2026-07-31, padronização "mesmo ícone do menu antes do
 * título" iniciada em Expansões) — repassado ao `AppShell` da própria tela
 * de acesso restrito, pra manter o mesmo ícone do item de menu mesmo quando
 * o usuário não tem permissão de ver o conteúdo real.
 */
export async function requireCatalogoAdmin(title: string, icon?: LucideIcon): Promise<CatalogoGuardResult> {
  const supabase = await createClient();
  // getCachedUser()/getCachedIsAdmin() (Incremento 1 de performance,
  // 2026-08-14): mesma chamada de sempre (auth.getUser()/rpc("is_admin")),
  // agora memoizada por requisição via React cache() — AppShell e Header,
  // chamados mais adiante na mesma renderização, reaproveitam este
  // resultado em vez de refazer a chamada de rede. Ver
  // lib/supabase/request-auth-cache.ts para o racional completo.
  //
  // Promise.all (Incremento 4, gargalo #2 — 2026-08-14): as duas chamadas
  // são independentes — is_admin() lê auth.uid() do lado do Postgres, a
  // partir do JWT da própria requisição, sem depender do objeto `user`
  // resolvido aqui no lado do JS. Por isso podem ser disparadas juntas em
  // vez de esperar getUser() terminar para só então iniciar is_admin().
  // O redirect("/login") por ausência de usuário continua acontecendo
  // ANTES de qualquer decisão baseada em isAdmin — is_admin() sem sessão
  // apenas retorna erro de permissão (EXECUTE restrito a `authenticated`),
  // que é ignorado, já que o caminho sem usuário nunca chega a usar esse
  // resultado.
  const [
    {
      data: { user },
    },
    { data: isAdmin },
  ] = await Promise.all([getCachedUser(), getCachedIsAdmin()]);

  if (!user) {
    redirect("/login");
  }

  // Dispara a resolução de user_profile o MAIS CEDO possível, sem aguardar
  // aqui — a promise memoizada por cache() já fica "em voo" durante as
  // leituras específicas da página, em vez de só começar depois que
  // AppShell/Header renderizam. Também elimina a duplicidade observada
  // nesta rota (o `loading.tsx` de /catalogo renderiza um AppShell/Header
  // "real" próprio como esqueleto — ver app/catalogo/loading.tsx — então
  // Header rodava sua própria query DUAS vezes por requisição; com
  // getCachedUserProfile() memoizado, a segunda renderização reaproveita o
  // mesmo resultado, sem round-trip novo). Achado do diagnóstico P0 de
  // performance de /pricing (2026-08-23) — mesmo padrão em
  // requirePricingAdmin(), não é solução exclusiva de nenhuma das duas
  // rotas, vive na camada compartilhada de guard.
  void getCachedUserProfile().catch(() => {});

  if (!isAdmin) {
    return {
      denied: (
        <AppShell title={title} icon={icon}>
          <div className="mx-auto max-w-4xl">
            <Alert variant="destructive">Acesso restrito a administradores.</Alert>
          </div>
        </AppShell>
      ),
      supabase,
      user,
      isAdmin: false,
    };
  }

  return { denied: null, supabase, user, isAdmin: true };
}
