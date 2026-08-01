import { AlertTriangle, CreditCard, Image, ImageOff, Shuffle } from "lucide-react";
import { StatCard, StatsRow } from "@/components/catalogo/stat-card";
import type { CartasCatalogoStats, CatalogoCardSetRow } from "@/lib/catalogo/queries";

/**
 * Indicadores da tela Cartas — substitui a barra "Recentes" (3 chips de
 * Card Set + seletor "outra coleção") removida em 2026-07-31. Primeira
 * versão trazia Cartas/Coleções/Média/Sem Cartas (mesmo padrão de
 * `CardSetsStats`); Fabrício pediu, na mesma rodada, uma lista fechada
 * diferente de 5 indicadores — substituída aqui:
 * 1. Quantidade de cartas.
 * 2. Quantidade de variações cadastradas (`card_variant`, Query 160 — ex.:
 *    STANDARD, REVERSE_HOLO por Card).
 * 3. Quantidade de imagens em nossa base (`card_asset`, Query 180 — todo
 *    ativo digital registrado, não só CARD_FRONT).
 * 4. Quantidade de coleções sem cartas.
 * 5. Quantidade de cartas sem imagens.
 *
 * "Cartas" e "Coleções sem Cartas" são deriváveis de `cardSets`
 * (`cardsCatalogados`), sem consulta nova — mesmo cálculo já usado na
 * versão anterior. Os outros três vêm de `getCartasCatalogoStats()`
 * (`queries.ts`), buscada uma vez em `page.tsx`. "Sem Cartas" e "Sem
 * Imagens" levam `tone="danger"` — os dois são indicadores de pendência
 * (dado que falta), mesmo critério já usado em "Sem Cartas" de
 * `CardSetsStats`.
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
      <StatCard label="Cartas" value={totalCartas} caption="cartas catalogadas" icon={CreditCard} />
      <StatCard label="Variações" value={stats.totalVariacoes} caption="variações cadastradas" icon={Shuffle} />
      <StatCard label="Imagens" value={stats.totalImagens} caption="imagens em nossa base" icon={Image} />
      <StatCard
        label="Sem Cartas"
        value={colecoesSemCartas}
        caption="coleções sem cartas"
        icon={AlertTriangle}
        tone="danger"
      />
      <StatCard
        label="Sem Imagens"
        value={stats.cardsSemImagem}
        caption="cartas sem imagens"
        icon={ImageOff}
        tone="danger"
      />
    </StatsRow>
  );
}
