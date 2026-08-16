import { redirect } from "next/navigation";
import { AuthHeroShell } from "@/components/auth/auth-hero-shell";
import { LoginForm } from "@/components/auth/login-form";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Component — checa sessão antes de renderizar: usuário já
 * autenticado que acessa `/login` não deve precisar logar de novo, segue
 * direto para a home (`/`). Mesmo padrão de guarda por página já usado em
 * `/perfil` e `/` (sem guarda global no middleware — ver
 * `components/auth/session-refresher.tsx` para o porquê).
 *
 * De volta a `app/(auth)/login/page.tsx` em rodada anterior (implementação
 * real da direção "cartas reais", 2026-08-15) — na Etapa 1 (2026-08-16,
 * visual "Collector's Ledger", depois reprovado) a página tinha sido
 * movida para fora do route group (`app/login/page.tsx`) porque
 * `(auth)/layout.tsx` impunha seu chrome simples a todas as rotas irmãs.
 * `(auth)/layout.tsx` foi removido naquela rodada. A URL `/login` nunca
 * mudou (route groups não entram na URL).
 *
 * Fechamento da Auth Experience V1 (2026-08-16, ver docs/log.md): Cadastro,
 * Recuperar Senha e Atualizar Senha migraram da casca legada temporária
 * (`LegacyAuthShell`, removida) para `AuthHeroShell` também — as 4 rotas
 * de autenticação agora compartilham exatamente esta mesma fundação
 * visual.
 *
 * O andaime `?copy=a|b|c` (rodada de polish, comparação de 3 alternativas
 * de copy dentro da composição real) foi removido depois da decisão de
 * Fabrício — a copy definitiva agora vive fixa em `auth-hero.tsx`.
 */
export default async function LoginPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/");
  }

  return (
    <AuthHeroShell>
      <LoginForm />
    </AuthHeroShell>
  );
}
