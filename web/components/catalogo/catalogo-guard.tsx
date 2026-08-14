import { redirect } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import type { ReactElement } from "react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Alert } from "@/components/ui/alert";
import { createClient } from "@/lib/supabase/server";
import { getCachedIsAdmin, getCachedUser } from "@/lib/supabase/request-auth-cache";
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
  const {
    data: { user },
    // getCachedUser()/getCachedIsAdmin() (Incremento 1 de performance,
    // 2026-08-14): mesma chamada de sempre (auth.getUser()/rpc("is_admin")),
    // agora memoizada por requisição via React cache() — AppShell e Header,
    // chamados mais adiante na mesma renderização, reaproveitam este
    // resultado em vez de refazer a chamada de rede. Ver
    // lib/supabase/request-auth-cache.ts para o racional completo.
  } = await getCachedUser();

  if (!user) {
    redirect("/login");
  }

  const { data: isAdmin } = await getCachedIsAdmin();

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
