import { redirect } from "next/navigation";
import { LoginForm } from "@/components/auth/login-form";
import { createClient } from "@/lib/supabase/server";

/**
 * Server Component (2026-08-13, era `"use client"` direto) — checa sessão
 * antes de renderizar: usuário já autenticado que acessa `/login` não deve
 * precisar logar de novo, segue direto para a home (`/`). Mesmo padrão de
 * guarda por página já usado em `/perfil` e agora em `/` (sem guarda global
 * no middleware). Formulário (JSX/estilo idênticos ao anterior) extraído
 * para `components/auth/login-form.tsx` — layout da tela de login
 * inalterado.
 */
export default async function LoginPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/");
  }

  return <LoginForm />;
}
