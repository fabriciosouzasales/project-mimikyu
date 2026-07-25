"use client";

import { usePathname } from "next/navigation";
import { findActiveSection } from "./nav-config";
import { PrimaryRail } from "./primary-rail";
import { SecondaryPanel } from "./secondary-panel";

/**
 * Navegação de dois níveis (pedido explícito de Fabrício, no mesmo padrão do
 * Supabase Dashboard): trilha de ícones fixa + submenu contextual da seção ativa.
 * Substitui a versão anterior (sidebar única que expandia ao hover).
 */
export function Sidebar() {
  const pathname = usePathname();
  const activeSection = findActiveSection(pathname);

  return (
    <div className="hidden shrink-0 md:flex">
      <PrimaryRail activeSection={activeSection} />
      <SecondaryPanel section={activeSection} />
    </div>
  );
}
