import { AlertTriangle, Boxes, Gamepad2, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { CardSetOverviewRow, ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

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
 * Nenhuma consulta nova: `jogos`/`expansoes` já chegam de
 * `getGameOptions()`/`getExpansoes()` (mesmas chamadas que a página já fazia
 * para o filtro), e `cardSets` vem de `getCardSetsOverview()` — a mesma
 * função já usada pela tabela de Card Sets da Visão Geral, sem paginação,
 * então os totais aqui são sempre globais, independente do filtro/busca
 * ativo na galeria abaixo (mesmo raciocínio de `ExpansoesStats`).
 */
export function CardSetsStats({
  jogos,
  expansoes,
  cardSets,
}: {
  jogos: GameOption[];
  expansoes: ExpansaoRow[];
  cardSets: CardSetOverviewRow[];
}) {
  const totalJogos = jogos.length;
  const totalExpansoes = expansoes.length;
  const totalCardSets = cardSets.length;
  const cardSetsSemCartas = cardSets.filter((set) => set.cardsCatalogados === 0).length;

  return (
    <StatsRow>
      <StatCard label="Jogos" value={totalJogos} caption="jogos cadastrados" icon={Gamepad2} />
      <StatCard label="Expansões" value={totalExpansoes} caption="expansões cadastradas" icon={Layers} />
      <StatCard label="Coleções" value={totalCardSets} caption="coleções cadastradas" icon={Boxes} />
      <StatCard
        label="Sem Cartas"
        value={cardSetsSemCartas}
        caption="coleções sem cartas"
        icon={AlertTriangle}
        tone="danger"
      />
    </StatsRow>
  );
}
