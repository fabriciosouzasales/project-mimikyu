"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV_SECTIONS, findActiveSection } from "./nav-config";
import { SidebarFooter } from "./sidebar-footer";
import { BrandMark } from "@/components/brand-mark";
import { cn } from "@/lib/utils";

/**
 * Trilha primária — recolhida por padrão (só ícones), expande no hover/focus
 * (largura animada em CSS, sem JS, sem layout shift: um spacer reserva o
 * espaço recolhido e o painel real fica em `absolute` por cima, com sombra)
 * revelando o rótulo de cada item. Sem tooltip: o próprio hover-expand já
 * mostra o texto, então um tooltip ficaria duplicado.
 *
 * O clique continua abrindo o `SecondaryPanel` (coluna separada, ver
 * `sidebar.tsx`) — hover expande a trilha E clique abre o painel são dois
 * comportamentos independentes, ambos mantidos por decisão explícita.
 *
 * `group-focus-within` replica o hover para navegação só por teclado.
 */
export function PrimaryRail() {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);

  return (
    <div className="group relative z-20 h-full shrink-0">
      <div className="h-full w-16" aria-hidden="true" />

      <nav
        className={cn(
          "absolute inset-y-0 left-0 flex w-16 flex-col overflow-hidden border-r border-border bg-surface",
          "transition-[width] duration-200 ease-out group-hover:w-64 group-hover:shadow-panel",
          "group-focus-within:w-64 group-focus-within:shadow-panel",
        )}
        aria-label="Navegação principal"
      >
        <div className="flex h-14 shrink-0 items-center gap-2 overflow-hidden border-b border-border px-4">
          <BrandMark className="h-auto w-8" />
          <span className="truncate text-sm font-semibold">Project Mimikyu</span>
        </div>

        <div className="flex-1 space-y-1 overflow-y-auto overflow-x-hidden p-2">
          {NAV_SECTIONS.map((section) => {
            const Icon = section.icon;
            const isActive = activeSection.id === section.id;

            return (
              <Link
                key={section.id}
                href={section.href}
                aria-current={isActive ? "page" : undefined}
                className={cn(
                  "flex h-10 items-center gap-3 overflow-hidden whitespace-nowrap rounded-md px-3 text-sm transition-colors",
                  isActive
                    ? "bg-accent font-semibold text-foreground"
                    : "font-medium text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                )}
              >
                <Icon className="h-5 w-5 shrink-0" aria-hidden="true" />
                <span className="flex-1 truncate">{section.label}</span>
              </Link>
            );
          })}
        </div>

        <SidebarFooter />
      </nav>
    </div>
  );
}
