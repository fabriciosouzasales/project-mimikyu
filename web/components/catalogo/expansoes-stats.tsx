import { Boxes, Divide, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { ExpansaoRow } from "@/lib/catalogo/queries";

/**
 * Indicadores da tela Expansões — mesmo padrão introduzido em Jogos
 * (2026-07-31, pedido de Fabrício: "refinar a experiência visual da página
 * de Expansões... cards com indicadores relacionados às expansões, seguindo
 * o mesmo padrão"). Mesma analogia de métricas: entidade da tela (Expansões),
 * entidade filha (Card Sets, via `totalCardSets` já embutido em cada
 * `ExpansaoRow`) e a média entre as duas, truncada como em Jogos (não
 * arredondada). Ícones reaproveitados dos mesmos usados no menu lateral
 * para as entidades equivalentes (Expansões → `Layers`, Coleções → `Boxes`).
 */
export function ExpansoesStats({ expansoes }: { expansoes: ExpansaoRow[] }) {
  const totalExpansoes = expansoes.length;
  const totalCardSets = expansoes.reduce((sum, expansao) => sum + expansao.totalCardSets, 0);
  const mediaCardSetsPorExpansao = totalExpansoes > 0 ? Math.trunc(totalCardSets / totalExpansoes) : 0;

  return (
    <StatsRow>
      <StatCard label="Expansões" value={totalExpansoes} caption="expansões cadastradas" icon={Layers} />
      <StatCard label="Card Sets" value={totalCardSets} caption="card sets cadastrados" icon={Boxes} />
      <StatCard label="Média" value={mediaCardSetsPorExpansao} caption="card sets por expansão" icon={Divide} />
    </StatsRow>
  );
}
