import { AlertTriangle, CreditCard, Image, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { EstadoDoCatalogo as EstadoDoCatalogoData } from "@/lib/catalogo/queries";

/**
 * Indicadores da Visão Geral — migrados para o padrão introduzido em Jogos
 * (2026-07-31, aprovado por Fabrício). Substitui `EstadoDoCatalogo`, que
 * usava um grid de 4 divs com borda direto (sem `StatCard`/ícone) — ver
 * `estado-do-catalogo.tsx` (não removido, mesma prática de manter código
 * substituído sem uso até decisão explícita de limpeza).
 *
 * Ajuste do mesmo dia (pedido de Fabrício): sequência reordenada — Card
 * Sets, Cartas catalogadas, Cobertura de imagens, Pendências (era Card
 * Sets, Cobertura, Cartas, Pendências); Cobertura de imagens agora em %
 * (era "6/7"); Pendências ganha `tone="danger"` (ícone vermelho), única
 * exceção ao selo uniforme dos outros três cartões.
 */
export function VisaoGeralStats({ estado }: { estado: EstadoDoCatalogoData }) {
  const coberturaPendente = estado.cardSetsCatalogados - estado.cardSetsComImagensCompletas;
  const coberturaPercentual =
    estado.cardSetsCatalogados > 0
      ? Math.round((estado.cardSetsComImagensCompletas / estado.cardSetsCatalogados) * 100)
      : 0;

  return (
    <div className="space-y-2">
      <StatsRow>
        <StatCard
          label="Card Sets"
          value={estado.cardSetsCatalogados}
          caption="card sets catalogados"
          icon={Layers}
        />
        <StatCard
          label="Cartas catalogadas"
          value={estado.cartasCatalogadas}
          caption="cartas no catálogo"
          icon={CreditCard}
        />
        <StatCard
          label="Cobertura de imagens"
          value={`${coberturaPercentual}%`}
          caption="com imagens completas"
          icon={Image}
        />
        <StatCard
          label="Pendências"
          value={estado.execucoesComPendencia}
          caption="execuções de importação"
          icon={AlertTriangle}
          tone="danger"
        />
      </StatsRow>
      {coberturaPendente > 0 && (
        <p className="text-xs text-muted-foreground">
          {coberturaPendente} Card Set{coberturaPendente > 1 ? "s" : ""} com imagens pendentes
        </p>
      )}
    </div>
  );
}
