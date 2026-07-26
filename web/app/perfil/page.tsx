import { redirect } from "next/navigation";
import { AppShell } from "@/components/app-shell/app-shell";
import { PerfilForm } from "@/components/perfil/perfil-form";
import { Alert } from "@/components/ui/alert";
import { createClient } from "@/lib/supabase/server";

export default async function PerfilPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Não existe guarda de rota global no projeto ainda (ver
  // lib/supabase/middleware.ts) — cada página protegida precisa checar a
  // sessão por conta própria. Sessão ausente/expirada aqui = redireciona
  // para o login, comportamento padrão para uma página autenticada.
  if (!user) {
    redirect("/login");
  }

  const { data: profile, error } = await supabase
    .from("user_profile")
    .select("username, display_name, avatar_path")
    .eq("id", user.id)
    .maybeSingle();

  return (
    <AppShell title="Meu perfil">
      <div className="mx-auto max-w-2xl">
        <div className="mb-6">
          <h1 className="font-heading text-xl font-medium text-foreground">Meu perfil</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Dados pessoais, identidade pública e foto de perfil.
          </p>
        </div>

        {error ? (
          <Alert variant="destructive">
            Não foi possível carregar seu perfil agora. Tente recarregar a página.
          </Alert>
        ) : !profile ? (
          <Alert variant="warning">
            Perfil ainda não carregado. Se você acabou de criar sua conta, aguarde alguns instantes
            e recarregue a página.
          </Alert>
        ) : (
          <PerfilForm
            userId={user.id}
            username={profile.username}
            initialDisplayName={profile.display_name}
            initialAvatarPath={profile.avatar_path}
          />
        )}
      </div>
    </AppShell>
  );
}
