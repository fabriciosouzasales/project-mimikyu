import type { LucideIcon } from "lucide-react";
import { MobileNav } from "@/components/app-shell/mobile-nav";
import { GlobalSearch } from "@/components/app-shell/global-search";
import { UserAvatarBadge } from "@/components/app-shell/user-avatar-badge";
import { ThemeToggle } from "@/components/theme-toggle";
import { getCachedUser, getCachedUserProfile } from "@/lib/supabase/request-auth-cache";

/**
 * Cabeçalho fixo do app shell: menu mobile (hambúrguer) + breadcrumb + ações
 * globais. `icon` opcional (2026-07-31) — mesmo ícone do item de menu
 * ativo, quando a página passa um; sem `icon`, o breadcrumb continua só
 * texto, como sempre foi.
 */
export async function Header({ title, icon: Icon, isAdmin }: { title: string; icon?: LucideIcon; isAdmin: boolean }) {
  // getCachedUser() (Incremento 1 de performance, 2026-08-14): mesma chamada
  // de sempre (auth.getUser()), memoizada por requisição — reusa o resultado
  // já obtido pelo guard em vez de refazer a chamada de rede.
  const {
    data: { user },
  } = await getCachedUser();

  let avatarUrl: string | null = null;
  let initial = "?";

  // getCachedUserProfile() (Fase 2 do diagnóstico P0 de performance,
  // 2026-08-23 — ver lib/supabase/request-auth-cache.ts): antes, esta query
  // vivia aqui mesmo, com seu próprio createClient() fora de qualquer cache
  // de requisição — 21% do tempo de /pricing e, em rotas com loading.tsx
  // (ex.: /catalogo), disparada DUAS vezes por request (uma pelo esqueleto,
  // outra pela página real). Agora é a MESMA promise memoizada que os guards
  // (requirePricingAdmin/requireCatalogoAdmin) já dispararam mais cedo, em
  // paralelo com as leituras específicas da página — aqui só se aguarda o
  // resultado, sem round-trip novo (nem na 1ª nem na 2ª renderização dentro
  // da mesma requisição).
  if (user) {
    const { profile, avatarUrl: url } = await getCachedUserProfile();
    if (profile) {
      initial = (profile.display_name || profile.username || "?").charAt(0).toUpperCase();
      avatarUrl = url;
    }
  }

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-border bg-surface px-4 print:hidden">
      <div className="flex shrink-0 items-center gap-2">
        <MobileNav isAdmin={isAdmin} />
        {Icon && <Icon className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden="true" />}
        <p className="text-sm font-medium text-muted-foreground">{title}</p>
      </div>
      {/* Pesquisa Global de Cartas (2026-08-17, ADR-030): disponível em todo
          header autenticado (não só /catalogo) — desktop inline no centro
          (não desloca título nem ações), mobile via botão compacto que abre
          overlay dedicado (ver GlobalSearch). */}
      {user && <GlobalSearch />}
      <div className="flex shrink-0 items-center gap-2">
        {user && <UserAvatarBadge avatarUrl={avatarUrl} initial={initial} />}
        <ThemeToggle />
      </div>
    </header>
  );
}
