import { AlertTriangle, CreditCard, Image, ImageOff } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { CartasCatalogoStats, CatalogoCardSetRow } from "@/lib/catalogo/queries";
import { formatNumber } from "@/lib/utils";

/**
 * Indicadores da tela Cartas — substitui a barra "Recentes" (3 chips de
 * Card Set + seletor "outra coleção") removida em 2026-07-31. Primeira
 * versão trazia Cartas/Coleções/Média/Sem Cartas (mesmo padrão de
 * `CardSetsStats`); Fabrício pediu, na mesma rodada, uma lista fechada
 * diferente de 5 indicadores, reduzida a 4 em 2026-08-01 (ver nota abaixo):
 * 1. Quantidade de cartas.
 * 2. Quantidade de imagens em nossa base (`card_asset`, Query 180 — todo
 *    ativo digital registrado, não só CARD_FRONT).
 * 3. Quantidade de coleções sem cartas.
 * 4. Quantidade de cartas sem imagens.
 *
 * "Cartas" e "Coleções sem Cartas" são deriváveis de `cardSets`
 * (`cardsCatalogados`), sem consulta nova — mesmo cálculo já usado na
 * versão anterior. Os outros dois vêm de `getCartasCatalogoStats()`
 * (`queries.ts`), buscada uma vez em `page.tsx`. "Sem Cartas" e "Sem
 * Imagens" levam `tone="danger"` — os dois são indicadores de pendência
 * (dado que falta), mesmo critério já usado em "Sem Cartas" de
 * `CardSetsStats`.
 *
 * "Variações" removido em 2026-08-01 (pedido de Fabrício: "após a inserção
 * do botão 'Importar Cartas' a harmonia visual da página foi impactada...
 * remova o indicador VARIAÇÕES") — só o cartão saiu; `stats.totalVariacoes`
 * continua calculado em `getCartasCatalogoStats()` (`queries.ts`), sem uso
 * nesta tela por ora, caso volte a ser útil em outro lugar.
 */
export function CartasStats({
  cardSets,
  stats,
}: {
  cardSets: CatalogoCardSetRow[];
  stats: CartasCatalogoStats;
}) {
  const totalCartas = cardSets.reduce((sum, cardSet) => sum + cardSet.cardsCatalogados, 0);
  const colecoesSemCartas = cardSets.filter((cardSet) => cardSet.cardsCatalogados === 0).length;

  return (
    <StatsRow>
      <StatCard label="Cartas" value={formatNumber(totalCartas)} caption="cartas catalogadas" icon={CreditCard} />
      <StatCard
        label="Imagens"
        value={formatNumber(stats.totalImagens)}
        caption="imagens em nossa base"
        icon={Image}
      />
      <StatCard
        label="Sem Cartas"
        value={formatNumber(colecoesSemCartas)}
        caption="coleções sem cartas"
        icon={AlertTriangle}
        tone="danger"
      />
      <StatCard
        label="Sem Imagens"
        value={formatNumber(stats.cardsSemImagem)}
        caption="cartas sem imagens"
        icon={ImageOff}
        tone="danger"
      />
    </StatsRow>
  );
}
