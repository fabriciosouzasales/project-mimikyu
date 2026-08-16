import { AuthHeroShell } from "@/components/auth/auth-hero-shell";
import { SignupForm } from "@/components/auth/signup-form";

/**
 * Server Component "casca" — a lógica (useActionState, debounce de
 * username, estado de sucesso) vive em `SignupForm` (Client Component),
 * migrada para lá nesta rodada (fechamento da Auth Experience V1,
 * 2026-08-16, ver docs/log.md). Mesmo padrão de `/login`: a página só
 * decide a casca (`AuthHeroShell`, compartilhada com as outras 3 rotas de
 * autenticação) e delega o conteúdo do painel ao form component.
 */
export default function SignupPage() {
  return (
    <AuthHeroShell>
      <SignupForm />
    </AuthHeroShell>
  );
}
