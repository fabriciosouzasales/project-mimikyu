import { MobileNav } from "@/components/app-shell/mobile-nav";
import { UserAvatarBadge } from "@/components/app-shell/user-avatar-badge";
import { ThemeToggle } from "@/components/theme-toggle";
import { createClient } from "@/lib/supabase/server";

/** Cabeçalho fixo do app shell: menu mobile (hambúrguer) + breadcrumb + ações globais. */
export async function Header({ title }: { title: string }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  let avatarUrl: string | null = null;
  let initial = "?";

  if (user) {
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
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-surface px-4">
      <div className="flex items-center gap-2">
        <MobileNav />
        <p className="text-sm font-medium text-muted-foreground">{title}</p>
      </div>
      <div className="flex items-center gap-2">
        {user && <UserAvatarBadge avatarUrl={avatarUrl} initial={initial} />}
        <ThemeToggle />
      </div>
    </header>
  );
}
