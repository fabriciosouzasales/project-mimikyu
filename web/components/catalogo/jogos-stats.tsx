import { Divide, Gamepad2, Layers } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { JogoRow } from "@/lib/catalogo/queries";

/**
 * Indicadores da tela Jogos — exibidos antes da tabela (pedido de
 * Fabrício, 2026-07-31, a partir de referência visual de um Dashboard com
 * cartões de indicador). Primeira aplicação desse padrão no módulo; depois
 * de validada, será estendida às telas de Expansão e Card Set.
 *
 * Ajuste fino (mesmo dia): título curto em maiúsculo (via CSS, texto já
 * curto o bastante para não parecer gritado), segunda legenda abaixo do
 * número explicando o que ele significa, e um terceiro indicador —
 * "Média" de Expansões por Jogo, truncado (não arredondado) quando não for
 * inteiro, conforme pedido.
 *
 * Números calculados a partir do próprio `jogos` já buscado por
 * `getJogos()` — nenhuma query nova. "Expansões" soma `totalExpansoes` de
 * cada Jogo, contagem que já vem por junção (`expansion(count)`) — ver
 * comentário em `getJogos` sobre por que a lista não traz contagens em
 * cascata além desse nível (ex.: Card Sets).
 */
export function JogosStats({ jogos }: { jogos: JogoRow[] }) {
  const totalJogos = jogos.length;
  const totalExpansoes = jogos.reduce((sum, jogo) => sum + jogo.totalExpansoes, 0);
  const mediaExpansoesPorJogo = totalJogos > 0 ? Math.trunc(totalExpansoes / totalJogos) : 0;

  return (
    <StatsRow>
      <StatCard label="Jogos" value={totalJogos} caption="jogos cadastrados" icon={Gamepad2} />
      <StatCard label="Expansões" value={totalExpansoes} caption="expansões cadastradas" icon={Layers} />
      <StatCard label="Média" value={mediaExpansoesPorJogo} caption="expansões por jogo" icon={Divide} />
    </StatsRow>
  );
}
