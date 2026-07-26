import { PrimaryRail } from "./primary-rail";
import { SecondaryPanel } from "./secondary-panel";

/**
 * Sidebar em duas colunas (modelo Supabase, decisão confirmada em
 * 2026-07-25 revertendo o modelo anterior de coluna única): trilha de
 * ícones fixa (`PrimaryRail`) + painel secundário (`SecondaryPanel`) que
 * aparece só quando a seção ativa tem submenu. Sem estado próprio — ambos
 * derivam a seção/submenu ativos da rota.
 */
export function Sidebar() {
  return (
    <div className="hidden shrink-0 md:flex">
      <PrimaryRail />
      <SecondaryPanel />
    </div>
  );
}
