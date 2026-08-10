import { AlertTriangle, Boxes, Gamepad2, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Indicadores da tela Expansões — ajuste 2026-07-31 (pedido de Fabrício:
 * "indicadores voltados para estrutura"), substituindo o trio original
 * (Expansões/Coleções/Média) por quatro cartões, nesta ordem: Jogos,
 * Expansões, Coleções (rótulo em UI para a entidade `card_set` — "não
 * esqueça de escrever Coleções onde temos dados dos Sets") e Sem Coleções
 * — uma pendência estrutural (Expansão cadastrada sem nenhuma Coleção
 * vinculada ainda), com `tone="danger"` no mesmo padrão de "Pendências" da
 * Visão Geral. Rótulo abreviado para "Sem Coleções" (2026-07-31, ajuste de
 * Fabrício — "Expansões sem Coleções" quebrava linha no cartão mesmo após
 * reduzir fonte/aumentar largura); a legenda abaixo do número mantém o
 * contexto por extenso ("expansões sem coleções"). Ícones reaproveitados
 * dos itens de menu equivalentes (Jogos → `Gamepad2`, Expansões → `Layers`,
 * Coleções → `Boxes`).
 */
export function ExpansoesStats({ expansoes, jogos }: { expansoes: ExpansaoRow[]; jogos: GameOption[] }) {
  const totalExpansoes = expansoes.length;
  const totalJogos = jogos.length;
  const totalCardSets = expansoes.reduce((sum, expansao) => sum + expansao.totalCardSets, 0);
  const expansoesSemSets = expansoes.filter((expansao) => expansao.totalCardSets === 0).length;

  return (
    <StatsRow>
      <StatCard label="Jogos" value={formatNumber(totalJogos)} caption="jogos cadastrados" icon={Gamepad2} />
      <StatCard
        label="Expansões"
        value={formatNumber(totalExpansoes)}
        caption="expansões cadastradas"
        icon={Layers}
      />
      <StatCard label="Coleções" value={formatNumber(totalCardSets)} caption="coleções cadastradas" icon={Boxes} />
      <StatCard
        label="Sem Coleções"
        value={formatNumber(expansoesSemSets)}
        caption="expansões sem coleções"
        icon={AlertTriangle}
        tone="danger"
      />
    </StatsRow>
  );
}
