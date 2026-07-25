"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";
import { BookOpen, ChevronsLeft, ChevronsRight, LayoutDashboard, Users } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/", label: "Visão geral", icon: LayoutDashboard },
  { href: "/usuarios", label: "Usuários", icon: Users },
  { href: "/catalogo", label: "Catálogo editorial", icon: BookOpen },
] as const;

/**
 * Sidebar recolhível/expandida, inspirada no dashboard do Supabase.
 * Estado de colapso é puramente visual nesta fundação (Etapa 0) — não persiste
 * ainda entre sessões; isso pode evoluir depois sem custo arquitetural.
 */
export function Sidebar() {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(false);

  return (
    <aside
      className={cn(
        "hidden shrink-0 flex-col border-r border-border bg-surface transition-[width] duration-200 md:flex",
        collapsed ? "w-[64px]" : "w-[220px]",
      )}
    >
      <div className="flex h-14 items-center gap-2 border-b border-border px-4">
        <div className="h-6 w-6 shrink-0 rounded-md bg-primary" aria-hidden="true" />
        {!collapsed && <span className="truncate text-sm font-semibold">Project Mimikyu</span>}
      </div>

      <nav className="flex-1 space-y-1 p-2" aria-label="Navegação principal">
        {NAV_ITEMS.map((item) => {
          const Icon = item.icon;
          const active = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                active
                  ? "bg-primary/10 text-primary"
                  : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
              )}
            >
              <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
              {!collapsed && <span className="truncate">{item.label}</span>}
            </Link>
          );
        })}
      </nav>

      <button
        type="button"
        onClick={() => setCollapsed((v) => !v)}
        aria-label={collapsed ? "Expandir menu lateral" : "Recolher menu lateral"}
        className="flex items-center gap-2 border-t border-border px-4 py-3 text-sm text-muted-foreground hover:bg-surface-muted hover:text-foreground"
      >
        {collapsed ? <ChevronsRight className="h-4 w-4" /> : <ChevronsLeft className="h-4 w-4" />}
        {!collapsed && <span>Recolher</span>}
      </button>
    </aside>
  );
}
