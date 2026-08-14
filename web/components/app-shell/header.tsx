import type { LucideIcon } from "lucide-react";
import { MobileNav } from "@/components/app-shell/mobile-nav";
import { UserAvatarBadge } from "@/components/app-shell/user-avatar-badge";
import { ThemeToggle } from "@/components/theme-toggle";
import { createClient } from "@/lib/supabase/server";
import { getCachedUser } from "@/lib/supabase/request-auth-cache";

/**
 * Cabeçalho fixo do app shell: menu mobile (hambúrguer) + breadcrumb + ações
 * globais. `icon` opcional (2026-07-31) — mesmo ícone do item de menu
 * ativo, quando a página passa um; sem `icon`, o breadcrumb continua só
 * texto, como sempre foi.
 */
export async function Header({ title, icon: Icon, isAdmin }: { title: string; icon?: LucideIcon; isAdmin: boolean }) {
  // getCachedUser() (Incremento 1 de performance, 2026-08-14): mesma chamada
  // de sempre (auth.getUser()), memoizada por requisição — reusa o resultado
  // já obtido por requireCatalogoAdmin() em vez de refazer a chamada de rede.
  // Ver lib/supabase/request-auth-cache.ts. `supabase` continua criado aqui
  // normalmente (client novo, sem custo de rede) só para a query de
  // user_profile abaixo, que não faz parte da deduplicação pedida.
  const {
    data: { user },
  } = await getCachedUser();

  let avatarUrl: string | null = null;
  let initial = "?";

  if (user) {
    const supabase = await createClient();
    const { data: profile } = await supabase
      .from("user_profile")
      .select("username, display_name, avatar_path")
      .eq("id", user.id)
      .maybeSingle();

    if (profile) {
      initial = (profile.display_name || profile.username || "?").charAt(0).toUpperCase();
      if (profile.avatar_path) {
        avatarUrl = supabase.storage.from("avatars").getPublicUrl(profile.avatar_path).data.publicUrl;
      }
    }
  }

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-surface px-4 print:hidden">
      <div className="flex items-center gap-2">
        <MobileNav isAdmin={isAdmin} />
        {Icon && <Icon className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden="true" />}
        <p className="text-sm font-medium text-muted-foreground">{title}</p>
      </div>
      <div className="flex items-center gap-2">
        {user && <UserAvatarBadge avatarUrl={avatarUrl} initial={initial} />}
        <ThemeToggle />
      </div>
    </header>
  );
}
