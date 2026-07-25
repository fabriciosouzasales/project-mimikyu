"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { BookOpen, LayoutDashboard, Users } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/", label: "Visão geral", icon: LayoutDashboard },
  { href: "/usuarios", label: "Usuários", icon: Users },
  { href: "/catalogo", label: "Catálogo editorial", icon: BookOpen },
] as const;

/**
 * Sidebar recolhida por padrão (só ícones) e expandida ao passar o mouse —
 * pedido explícito de Fabrício, substituindo o botão manual de recolher.
 *
 * Implementação puramente via CSS (`group-hover`), sem estado em React:
 * um spacer reserva a largura recolhida no layout em flex, e o painel real
 * fica posicionado em `absolute`, expandindo por cima do conteúdo ao hover
 * — assim o conteúdo principal nunca "pula" quando a sidebar expande.
 *
 * `group-focus-within` garante o mesmo comportamento pra quem navega só
 * pelo teclado (Tab), já que `hover` sozinho não serve pra esse público.
 */
export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside className="group relative z-20 hidden shrink-0 md:block">
      {/* Spacer: reserva o espaço recolhido (64px) no layout flex */}
      <div className="h-full w-16" aria-hidden="true" />

      {/*
        Classes de largura escritas por extenso (não interpoladas) de propósito:
        o Tailwind escaneia o código-fonte em busca de nomes de classe literais —
        uma classe montada via template string (ex.: `group-hover:${var}`) não é
        reconhecida e a regra correspondente nunca seria gerada.
      */}
      <div
        className={cn(
          "absolute inset-y-0 left-0 flex w-16 flex-col overflow-hidden border-r border-border bg-surface transition-[width] duration-200 ease-out",
          "group-hover:w-[220px] group-hover:shadow-panel",
          "group-focus-within:w-[220px] group-focus-within:shadow-panel",
        )}
      >
        <div className="flex h-14 shrink-0 items-center gap-2 border-b border-border px-4">
          <div className="h-6 w-6 shrink-0 rounded-md bg-primary" aria-hidden="true" />
          <span className="truncate text-sm font-semibold">Project Mimikyu</span>
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
                <span className="truncate">{item.label}</span>
              </Link>
            );
          })}
        </nav>
      </div>
    </aside>
  );
}
