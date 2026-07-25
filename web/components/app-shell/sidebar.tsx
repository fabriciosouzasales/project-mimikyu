"use client";

import { NAV_SECTIONS } from "./nav-config";
import { SidebarSection } from "./sidebar-section";
import { SidebarFooter } from "./sidebar-footer";

/**
 * Sidebar de coluna única — recolhida por padrão (só ícones), expande no
 * hover (largura animada em CSS, sem JS, sem layout shift — spacer reserva
 * o espaço recolhido e o painel real fica em `absolute` por cima) e abre
 * submenu por clique (ver `SidebarSection`, que deriva o estado da rota).
 *
 * `group-focus-within` replica o mesmo comportamento pra navegação só por
 * teclado, já que `hover` sozinho não serve pra esse público.
 *
 * "use client": `NAV_SECTIONS` carrega ícones do lucide-react (referências
 * de componente/função). Se este componente ficasse Server e passasse
 * `section` como prop para `SidebarSection` (Client), o React tentaria
 * serializar o ícone na fronteira servidor→cliente e quebraria ("Only
 * plain objects can be passed..."). Como este componente não tem nenhuma
 * lógica exclusiva de servidor, virar Client remove a fronteira.
 */
export function Sidebar() {
  return (
    <div className="group relative z-20 hidden shrink-0 md:block">
      <div className="h-full w-16" aria-hidden="true" />

      <div
        className={
          "absolute inset-y-0 left-0 flex w-16 flex-col overflow-hidden border-r border-border bg-surface " +
          "transition-[width] duration-200 ease-out group-hover:w-64 group-hover:shadow-panel " +
          "group-focus-within:w-64 group-focus-within:shadow-panel"
        }
      >
        <div className="flex h-14 shrink-0 items-center gap-2 border-b border-border px-4">
          <div className="h-6 w-6 shrink-0 rounded-md bg-primary" aria-hidden="true" />
          <span className="truncate text-sm font-semibold">Project Mimikyu</span>
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto overflow-x-hidden p-2" aria-label="Navegação principal">
          {NAV_SECTIONS.map((section) => (
            <SidebarSection key={section.id} section={section} />
          ))}
        </nav>

        <SidebarFooter />
      </div>
    </div>
  );
}
