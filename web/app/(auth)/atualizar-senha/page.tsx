import { AuthHeroShell } from "@/components/auth/auth-hero-shell";
import { UpdatePasswordForm } from "@/components/auth/update-password-form";

/**
 * Server Component "casca" — lógica em `UpdatePasswordForm` (Client
 * Component), migrada para lá nesta rodada (fechamento da Auth Experience
 * V1, 2026-08-16, ver docs/log.md). Mesmo padrão de `/login`/`/cadastro`.
 *
 * Acessada só após clicar no link de recuperação (sessão de recovery já
 * ativa via /auth/callback) — comportamento inalterado.
 */
export default function UpdatePasswordPage() {
  return (
    <AuthHeroShell>
      <UpdatePasswordForm />
    </AuthHeroShell>
  );
}
