import { redirect } from "next/navigation";
import type { LucideIcon } from "lucide-react";
import type { ReactElement } from "react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Alert } from "@/components/ui/alert";
import { createClient } from "@/lib/supabase/server";
import { getCachedIsAdmin, getCachedUser } from "@/lib/supabase/request-auth-cache";
import type { SupabaseClient, User } from "@supabase/supabase-js";

type PricingGuardResult =
  | { denied: ReactElement; supabase: SupabaseClient; user: User; isAdmin: false }
  | { denied: null; supabase: SupabaseClient; user: User; isAdmin: true };

/**
 * Guarda de servidor compartilhada por todas as rotas do Pricing Admin
 * (Bloco 1, 2026-08-22) — todo o módulo é restrito a administradores, mesma
 * disciplina já aplicada ao Catálogo Editorial (ADR-022): sem sessão ->
 * redireciona para /login; sem papel administrativo -> alerta de acesso
 * restrito, sem renderizar nenhum conteúdo real.
 *
 * A autorização de verdade está nas RPCs SECURITY DEFINER do módulo
 * (get_pricing_admin_overview, admin_set_pricing_refresh_frequency,
 * get_pricing_refresh_policy — todas checam public.is_admin() internamente)
 * — esta função só decide o que MOSTRAR na interface; um usuário comum que
 * contornasse esta checagem ainda não conseguiria ler nenhum dado de
 * Pricing pela API.
 *
 * Extraída como um arquivo próprio (em vez de reaproveitar
 * `requireCatalogoAdmin` diretamente) para manter os dois módulos
 * independentes na navegação/mensagens de erro, mesmo a lógica de
 * autorização sendo idêntica hoje (só checa `is_admin()`, não um módulo
 * específico) — mesmo racional de `catalogo-guard.tsx`.
 *
 * Uso: `const { denied, supabase } = await requirePricingAdmin("Pricing");
 * if (denied) return denied;`
 */
export async function requirePricingAdmin(title: string, icon?: LucideIcon): Promise<PricingGuardResult> {
  const supabase = await createClient();
  const [
    {
      data: { user },
    },
    { data: isAdmin },
  ] = await Promise.all([getCachedUser(), getCachedIsAdmin()]);

  if (!user) {
    redirect("/login");
  }

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
