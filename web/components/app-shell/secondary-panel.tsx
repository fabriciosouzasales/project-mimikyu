"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { findActiveSection } from "./nav-config";
import { cn } from "@/lib/utils";

/**
 * Painel secundário — coluna separada da trilha de ícones, mostrada apenas
 * quando a seção ativa tem `children` (ex.: "Visão geral" não tem, então o
 * painel some e o conteúdo ocupa o espaço). Largura anima via CSS
 * (transition-[width]), sem JS e sem estado próprio: tudo deriva de
 * `findActiveSection(pathname)`, mesma regra de "reseta e é recalculado
 * pela rota" já definida para a trilha primária.
 */
export function SecondaryPanel() {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);
  const hasChildren = !!activeSection.children?.length;

  return (
    <div
      className={cn(
        "h-full shrink-0 overflow-hidden border-r border-border bg-surface transition-[width] duration-200 ease-out",
        hasChildren ? "w-56" : "w-0",
      )}
    >
      {hasChildren && (
        <div className="flex h-full w-56 flex-col">
          <div className="flex h-14 shrink-0 items-center border-b border-border px-4">
            <span className="truncate text-sm font-semibold">{activeSection.label}</span>
          </div>

          <nav
            className="flex-1 space-y-0.5 overflow-y-auto p-2"
            aria-label={`Submenu de ${activeSection.label}`}
          >
            {activeSection.children!.map((child) => {
              const isChildActive = pathname === child.href;
              return (
                <Link
                  key={child.href}
                  href={child.href}
                  aria-current={isChildActive ? "page" : undefined}
                  className={cn(
                    "flex items-center rounded-md px-3 py-2 text-sm transition-colors",
                    isChildActive
                      ? "bg-accent font-semibold text-foreground"
                      : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                  )}
                >
                  {child.label}
                </Link>
              );
            })}
          </nav>
        </div>
      )}
    </div>
  );
}
