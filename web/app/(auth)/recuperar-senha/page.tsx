import { AuthHeroShell } from "@/components/auth/auth-hero-shell";
import { ResetPasswordForm } from "@/components/auth/reset-password-form";

/**
 * Server Component "casca" — lógica em `ResetPasswordForm` (Client
 * Component), migrada para lá nesta rodada (fechamento da Auth Experience
 * V1, 2026-08-16, ver docs/log.md). Mesmo padrão de `/login`/`/cadastro`.
 */
export default function ResetPasswordPage() {
  return (
    <AuthHeroShell>
      <ResetPasswordForm />
    </AuthHeroShell>
  );
}
