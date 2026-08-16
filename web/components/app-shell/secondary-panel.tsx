"use client";

import { Fragment } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { findActiveSection, getVisibleNavSections } from "./nav-config";
import { cn } from "@/lib/utils";

/**
 * Painel secundário — coluna separada da trilha de ícones, mostrada apenas
 * quando a seção ativa tem `children` (ex.: "Visão geral" não tem, então o
 * painel some e o conteúdo ocupa o espaço). Largura anima via CSS
 * (transition-[width]), sem JS e sem estado próprio: tudo deriva de
 * `findActiveSection(pathname)`, mesma regra de "reseta e é recalculado
 * pela rota" já definida para a trilha primária.
 *
 * 2026-07-26 — agrupamento por seção (título maiúsculo + divisória antes do
 * primeiro item de cada grupo), modelo do sidebar de Database do Supabase
 * (referência de Fabrício). Controlado inteiramente por `child.section` em
 * `nav-config.ts`: itens sem essa propriedade (ex.: "Usuários") continuam
 * sem título/divisória — só o Catálogo usa isso hoje.
 *
 * 2026-07-31 — `child.icon` opcional (pedido de Fabrício: ícone antes do
 * título nos itens de Operações): só renderiza quando o item declara um
 * ícone em `nav-config.ts`; os demais itens continuam exatamente como
 * antes, sem espaço reservado para ícone.
 *
 * `app-nav-panel` (2026-08-16, ver `app/globals.css` e `primary-rail.tsx`
 * para o racional completo do mecanismo de escopo) — mesmo princípio da
 * rail primária: sobrescreve LOCALMENTE `--surface`/`--border`/`--foreground`/
 * `--muted-foreground`/etc. para os valores escuros da navegação, um degrau
 * de luminosidade sutilmente diferente de `.app-nav-rail`, para as duas
 * colunas continuarem distinguíveis entre si. Promovido de prova visual
 * isolada (`preview`/`onyx-preview.module.css`) para baseline permanente —
 * a prop `preview` e o CSS Module condicional foram removidos.
 *
 * Correção de contraste (Rodada 3 da prova, mantida): o `<span>` do título
 * do submenu ("Catálogo editorial") precisa de `text-foreground` explícito
 * — sem classe de cor própria, ele herdava a cor já computada no `<body>`
 * em vez de reavaliar `--foreground` dentro do escopo `.app-nav-panel`.
 */
export function SecondaryPanel({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);
  const isVisible = getVisibleNavSections(isAdmin).some((section) => section.id === activeSection.id);
  const hasChildren = isVisible && !!activeSection.children?.length;

  return (
    <div
      className={cn(
        "app-nav-panel h-full shrink-0 overflow-hidden border-r border-border bg-surface transition-[width] duration-200 ease-out",
        hasChildren ? "w-56" : "w-0",
      )}
    >
      {hasChildren && (
        <div className="flex h-full w-56 flex-col">
          <div className="flex h-14 shrink-0 items-center border-b border-border px-4">
            <span className="truncate text-sm font-semibold text-foreground">{activeSection.label}</span>
          </div>

          <nav
            className="flex-1 space-y-0.5 overflow-y-auto p-2"
            aria-label={`Submenu de ${activeSection.label}`}
          >
            {activeSection.children!.map((child, index) => {
              const previous = activeSection.children![index - 1];
              const isNewSection = !!child.section && child.section !== previous?.section;
              const isChildActive = pathname === child.href;
              const ChildIcon = child.icon;
              return (
                <Fragment key={child.href}>
                  {isNewSection && (
                    <div
                      className={cn(
                        "px-3 pb-1 text-[11px] font-medium uppercase tracking-wide text-muted-foreground",
                        index === 0 ? "pt-2" : "mt-2 border-t border-border pt-3",
                      )}
                    >
                      {child.section}
                    </div>
                  )}
                  <Link
                    href={child.href}
                    aria-current={isChildActive ? "page" : undefined}
                    className={cn(
                      "flex items-center gap-2 rounded-md px-3 py-1.5 text-[13px] leading-tight transition-colors",
                      isChildActive
                        ? "bg-nav-panel-active-surface font-semibold text-nav-active-ink"
                        : "text-muted-foreground hover:bg-surface-muted hover:text-foreground",
                      "border-l-2 pl-2.5 transition-colors duration-200",
                      isChildActive ? "border-nav-gold" : "border-transparent",
                    )}
                  >
                    {ChildIcon && <ChildIcon className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />}
                    {child.label}
                  </Link>
                </Fragment>
              );
            })}
          </nav>
        </div>
      )}
    </div>
  );
}
