import { Trophy } from "lucide-react";
import { ComingSoonPage } from "@/components/coming-soon-page";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";

/**
 * Placeholder do hub `/pricing/relatorios` (Bloco 5, 2026-08-23) — nome e
 * escopo já aprovados por Fabrício ao fechar o backend deste bloco, sem tela
 * própria ainda.
 *
 * Impressão (requisito transversal, 2026-08-22): quando este relatório
 * ganhar tela funcional, aplicar o mesmo padrão já usado em "Preço por
 * Carta" e "Valor por Set" — `RelatorioPrintButton` no `PageHeader`
 * (`print:hidden`), dashboard interativo também `print:hidden`, e uma folha
 * `hidden print:block` (`RelatorioFolha`/`RelatorioCabecalho`/
 * `RelatorioRodape`, mesmos componentes do Catálogo Editorial) consumindo
 * exatamente os dados já filtrados em tela — nenhuma solução paralela.
 */
export default async function CartasMaisValiosasPage() {
  const { denied } = await requirePricingAdmin("Cartas Mais Valiosas", Trophy);
  if (denied) return denied;

  return (
    <ComingSoonPage
      title="Cartas Mais Valiosas"
      description="Ranking das Cartas de maior valor estimado, com filtro por Set ou coleção completa."
      icon={Trophy}
    />
  );
}
