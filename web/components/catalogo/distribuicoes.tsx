import type { DistribuicaoPorRaridade } from "@/lib/catalogo/queries";

/**
 * Distribuição de cartas por Raridade — deliberadamente não por Card
 * Category (evita expor a discrepância interna da categoria ENERGY) nem
 * redundante com a tabela de Card Sets. Paleta neutra (não monocromática
 * pura, ajuste pedido por Fabrício): trilho em `muted-foreground/12`,
 * preenchimento em `primary/35` — cor de destaque discreta o suficiente
 * para ler proporções sem competir com o conteúdo.
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
    <div className="space-y-2">
      {distribuicao.map((item) => (
        <div key={item.code} className="flex items-center gap-2.5">
          <span className="w-28 shrink-0 truncate text-xs text-muted-foreground" title={item.name}>
            {item.name}
          </span>
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-muted-foreground/10">
            <div
              className="h-full rounded-full bg-primary/40"
              style={{ width: `${maior > 0 ? (item.totalCards / maior) * 100 : 0}%` }}
            />
          </div>
          <span className="w-8 shrink-0 text-right text-xs tabular-nums text-foreground">{item.totalCards}</span>
        </div>
      ))}
    </div>
  );
}
