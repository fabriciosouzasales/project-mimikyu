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

/** Área fixa embaixo da sidebar: perfil, configurações e logout. */
export function SidebarFooter() {
  return (
    <div className="space-y-1 border-t border-border p-2">
      {FOOTER_LINKS.map(({ href, label, icon: Icon }) => (
        <Link key={href} href={href} className={itemClass}>
          <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
          <span>{label}</span>
        </Link>
      ))}

      <form action={logout}>
        <button type="submit" className={cn(itemClass, "w-full text-left")}>
          <LogOut className="h-5 w-5 shrink-0" aria-hidden="true" />
          <span>Sair</span>
        </button>
      </form>
    </div>
  );
}
