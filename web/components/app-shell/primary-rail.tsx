"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { findActiveSection, getVisibleNavSections } from "./nav-config";
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
 *
 * `app-nav-rail` (2026-08-16, ver `app/globals.css`) — a navegação é uma
 * âncora fixa da identidade MMKYU, escura nos dois temas, promovida de uma
 * prova visual isolada ("onyx-preview", só em Catálogo Editorial > Visão
 * Geral, 3 rodadas) para BASELINE de todas as páginas internas. A classe
 * sobrescreve LOCALMENTE `--surface`/`--surface-muted`/`--border`/`--input`/
 * `--foreground`/`--muted-foreground` — as mesmas classes Tailwind de
 * sempre (`bg-surface`, `text-muted-foreground`, `border-border`...) usadas
 * aqui E em qualquer componente filho (`SidebarFooter`) resolvem
 * automaticamente para os valores escuros da navegação, sem precisar de
 * nenhuma edição própria nesses componentes. O mecanismo por CSS Module
 * (`preview`/`onyx-preview.module.css`) da prova foi removido — não é mais
 * condicional, é permanente. `BrandMark` usa `variant="dark"` fixo (não mais
 * `"auto"`/condicional) — a navegação é sempre escura, então a logo sempre
 * precisa da arte clara, independente do tema do site.
 *
 * `--nav-gold`/`--nav-active-surface`/`--nav-active-ink` continuam tokens
 * PRÓPRIOS (não reaproveitam `--accent`/`--primary`/`--foreground`) — ver
 * `app/globals.css` para o racional.
 *
 * Largura compacta (`w-14` recolhida, `w-56` expandida) e centralização
 * rigorosa dos ícones no estado recolhido (rótulo com `w-0`/`flex-none` em
 * vez de `flex-1` com opacidade zero, que ainda ocupava espaço de layout e
 * descentralizava o ícone) — ajustes validados na prova, agora permanentes
 * e sem condicional.
 */
export function PrimaryRail({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);
  const sections = getVisibleNavSections(isAdmin);

  return (
    <div className="group relative z-20 h-full shrink-0">
      <div className="h-full w-14" aria-hidden="true" />

      <nav
        className={cn(
          "app-nav-rail absolute inset-y-0 left-0 flex w-14 flex-col overflow-hidden border-r border-border bg-surface",
          "transition-[width] duration-200 ease-out group-hover:w-56 group-hover:shadow-panel",
          "group-focus-within:w-56 group-focus-within:shadow-panel",
        )}
        aria-label="Navegação principal"
      >
        <div className="flex h-14 shrink-0 items-center gap-2 overflow-hidden border-b border-border px-4">
          <BrandMark className="h-auto w-8 shrink-0" variant="dark" />
          <span
            className={cn(
              "truncate text-sm font-semibold text-foreground opacity-0 transition-opacity duration-200",
              "group-hover:opacity-100 group-focus-within:opacity-100",
            )}
          >
            MMKyu TCG Collector
          </span>
        </div>

        <div className="flex-1 space-y-0.5 overflow-y-auto overflow-x-hidden p-2">
          {sections.map((section) => {
            const Icon = section.icon;
            const isActive = activeSection.id === section.id;

            return (
              <Link
                key={section.id}
                href={section.href}
                aria-current={isActive ? "page" : undefined}
                className={cn(
                  "flex h-8 items-center overflow-hidden whitespace-nowrap rounded-md px-2.5 text-[13px] leading-tight transition-colors",
                  "justify-center gap-0 group-hover:justify-start group-hover:gap-2 group-focus-within:justify-start group-focus-within:gap-2",
                  isActive
                    ? "bg-nav-active-surface font-semibold text-nav-active-ink"
                    : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                  "border-l-2 border-transparent pl-2 transition-colors duration-200",
                  isActive && "group-hover:border-nav-gold group-focus-within:border-nav-gold",
                )}
              >
                <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
                <span
                  className={cn(
                    "w-0 flex-none truncate opacity-0 transition-opacity duration-200",
                    "group-hover:w-auto group-hover:flex-1 group-hover:opacity-100",
                    "group-focus-within:w-auto group-focus-within:flex-1 group-focus-within:opacity-100",
                  )}
                >
                  {section.label}
                </span>
              </Link>
            );
          })}
        </div>

        <SidebarFooter />
      </nav>
    </div>
  );
}
