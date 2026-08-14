import { AlertTriangle, Boxes, Gamepad2, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { CardSetsStatsSummary, ExpansaoRow, GameOption } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Indicadores da tela Coleções (/catalogo/card-sets) — mesmo padrão
 * introduzido em Jogos e depois estendido a Expansões (2026-07-31, pedido de
 * Fabrício: "faça todos os ajustes necessários para manter o mesmo padrão da
 * página Expansões"): quatro cartões, Jogos → Expansões → Coleções → Sem
 * Cartas — mesma progressão "totais estruturais → pendência", agora um
 * nível abaixo (Expansões apontava Expansões-sem-Coleções; aqui é
 * Coleções-sem-Cartas). `tone="danger"` no último, mesmo critério de
 * "Pendências"/"Sem Coleções".
 *
 * `jogos`/`expansoes` já chegam de `getGameOptions()`/`getExpansoes()`
 * (mesmas chamadas que a página já fazia para o filtro); `stats` vem de
 * `summarizeCardSetCardCounts()` (2026-08-14, Incremento 5 — função pura,
 * substitui `getCardSetsStatsSummary()`, removida; antes dela era
 * `getCardSetsOverview()` inteira, só para ler dois números; ver
 * `card-sets/page.tsx`), sem paginação, então os totais aqui são sempre
 * globais, independente do filtro/busca ativo na galeria abaixo (mesmo
 * raciocínio de `ExpansoesStats`).
 */
export function CardSetsStats({
  jogos,
  expansoes,
  stats,
}: {
  jogos: GameOption[];
  expansoes: ExpansaoRow[];
  stats: CardSetsStatsSummary;
}) {
  const totalJogos = jogos.length;
  const totalExpansoes = expansoes.length;
  const totalCardSets = stats.totalCardSets;
  const cardSetsSemCartas = stats.cardSetsSemCartas;

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
        label="Sem Cartas"
        value={formatNumber(cardSetsSemCartas)}
        caption="coleções sem cartas"
        icon={AlertTriangle}
        tone="danger"
      />
    </StatsRow>
  );
}
