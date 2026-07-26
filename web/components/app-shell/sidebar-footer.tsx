import Link from "next/link";
import { CircleUserRound, LogOut, Settings } from "lucide-react";
import { logout } from "@/app/(auth)/actions";
import { cn } from "@/lib/utils";

const FOOTER_LINKS = [
  { href: "/perfil", label: "Meu perfil", icon: CircleUserRound },
  { href: "/configuracoes", label: "Configurações", icon: Settings },
] as const;

const itemClass =
  "flex h-10 items-center gap-3 overflow-hidden whitespace-nowrap rounded-md px-3 text-sm font-medium text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground";

/**
 * Área fixa embaixo da trilha primária: perfil, configurações e logout.
 * O rótulo é revelado pelo hover-expand da própria trilha (ver
 * `PrimaryRail`), sem tooltip.
 */
export function SidebarFooter() {
  return (
    <div className="w-full space-y-1 overflow-hidden border-t border-border p-2">
      {FOOTER_LINKS.map(({ href, label, icon: Icon }) => (
        <Link key={href} href={href} className={itemClass}>
          <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
          <span className="flex-1 truncate">{label}</span>
        </Link>
      ))}

      <form action={logout}>
        <button type="submit" className={cn(itemClass, "w-full text-left")}>
          <LogOut className="h-5 w-5 shrink-0" aria-hidden="true" />
          <span className="flex-1 truncate">Sair</span>
        </button>
      </form>
    </div>
  );
}
