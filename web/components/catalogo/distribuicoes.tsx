import type { DistribuicaoPorRaridade } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Distribuição de cartas por Raridade — deliberadamente não por Card
 * Category (evita expor a discrepância interna da categoria ENERGY) nem
 * redundante com a tabela de Card Sets.
 *
 * Barras horizontais (2026-07-31, pedido de Fabrício: a versão em colunas
 * verticais com rótulo abreviado "ainda incomoda", pediu para avaliar e
 * melhorar — "legenda ou rótulos completos, já que aparentemente temos
 * espaço"). Decisão: nome completo por extenso, sem abreviação nem legenda
 * à parte — com 10 raridades de comprimento bem desigual ("Comum" vs.
 * "Ilustração rara especial") e o card já ocupando a largura inteira da
 * página (reorganização anterior tirou a coluna lateral estreita), colunas
 * verticais forçariam rótulo girado ou sigla; uma legenda ao lado só
 * adiciona um segundo lugar pra olhar em vez de ler o nome direto na
 * linha. Barra colorida (#C98350, mesma referência visual de antes) sobre
 * trilho neutro, nome à esquerda e contagem à direita — mesmo padrão que
 * `card_set`/`card` já usam noutras listas do módulo, só sem tabela.
 */
export function Distribuicoes({ distribuicao }: { distribuicao: DistribuicaoPorRaridade[] }) {
  if (distribuicao.length === 0) {
    return (
      <div className="flex flex-col items-center gap-1 py-8 text-center">
        <p className="text-sm text-foreground">Sem dados de distribuição</p>
        <p className="text-xs text-muted-foreground">Aparece assim que houver cartas catalogadas.</p>
      </div>
    );
  }

  const maior = Math.max(...distribuicao.map((item) => item.totalCards));

  return (
    <div className="space-y-2.5">
      {distribuicao.map((item) => (
        <div key={item.code} className="flex items-center gap-3">
          <span className="w-44 shrink-0 truncate text-xs text-muted-foreground sm:w-52" title={item.name}>
            {item.name}
          </span>
          <div className="h-2 flex-1 overflow-hidden rounded-full bg-muted-foreground/10">
            <div
              className="h-full rounded-full bg-[#C98350]"
              style={{ width: `${maior > 0 ? (item.totalCards / maior) * 100 : 0}%` }}
            />
          </div>
          <span className="w-10 shrink-0 text-right text-xs font-medium tabular-nums text-foreground">
            {formatNumber(item.totalCards)}
          </span>
        </div>
      ))}
    </div>
  );
}
