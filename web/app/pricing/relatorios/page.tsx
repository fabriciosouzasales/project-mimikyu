import {
  CreditCard,
  FileText,
  GitCompare,
  History,
  Package,
  SlidersHorizontal,
  TrendingUp,
  Trophy,
} from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { Card, CardContent } from "@/components/ui/card";
import { requirePricingAdmin } from "@/components/pricing/pricing-guard";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";

/**
 * Hub da Central de Relatórios de Pricing (Bloco 5, migration 3943,
 * 2026-08-23) — mesmo padrão visual/estrutural do hub do Catálogo Editorial
 * (`/catalogo/relatorios/page.tsx`): grid de cards clicáveis, sem seletor
 * nesta camada. Diferente do Catálogo, aqui nem todos os 7 relatórios têm
 * tela funcional ainda — "Preço por Carta" e "Valor por Set" consomem as
 * duas RPCs já aplicadas (`admin_get_pricing_report_card`/
 * `admin_get_pricing_report_set`); os outros 5 (nomes já aprovados por
 * Fabrício ao fechar o backend deste bloco) apontam para
 * `ComingSoonPage` próprias — mesma disciplina de "nenhum link leva a 404"
 * já aplicada ao resto do app, mesmo sendo um tile de hub e não um item de
 * menu.
 *
 * Impressão (requisito transversal, 2026-08-22): todo relatório desta
 * Central — atual ou futuro — deve ter opção de impressão seguindo
 * exatamente o padrão do Catálogo Editorial (`RelatorioFolha`/
 * `RelatorioCabecalho`/`RelatorioRodape`/`RelatorioPrintButton`,
 * `window.print()`, `@media print` de `globals.css`). Já aplicado a "Preço
 * por Carta" e "Valor por Set" (ver `PrecoPorCartaPrintFolha`/
 * `ValorPorSetPrintFolha`); o mesmo padrão está documentado no JSDoc de
 * cada um dos 5 placeholders (`ComingSoonPage`) restantes, para ser aplicado
 * quando ganharem tela funcional — nenhuma solução paralela de impressão.
 */
const RELATORIOS = [
  {
    href: "/pricing/relatorios/preco-por-carta",
    icon: CreditCard,
    title: "Preço por Carta",
    description: "Preço atual por fonte/variante e série temporal de uma Carta específica.",
  },
  {
    href: "/pricing/relatorios/valor-por-set",
    icon: Package,
    title: "Valor por Set",
    description: "Valor estimado coberto e cobertura de preço das Cartas ativas de um Set.",
  },
  {
    href: "/pricing/relatorios/preco-por-condicao",
    icon: SlidersHorizontal,
    title: "Preço por Condição",
    description: "Comparativo de preço entre as condições de uma mesma Carta.",
  },
  {
    href: "/pricing/relatorios/historico-precos",
    icon: History,
    title: "Histórico de Preços",
    description: "Evolução de preço agregada por Set ou por fonte ao longo do tempo.",
  },
  {
    href: "/pricing/relatorios/comparativo-fontes",
    icon: GitCompare,
    title: "Comparativo de Fontes",
    description: "Divergência de preço entre fontes homologadas para a mesma Carta.",
  },
  {
    href: "/pricing/relatorios/cartas-mais-valiosas",
    icon: Trophy,
    title: "Cartas Mais Valiosas",
    description: "Ranking das Cartas de maior valor estimado, com filtro por Set ou coleção completa.",
  },
  {
    href: "/pricing/relatorios/tendencias",
    icon: TrendingUp,
    title: "Tendências",
    description: "Cartas em maior alta ou queda de preço no período recente.",
  },
] as const;

export default async function PricingRelatoriosPage() {
  const { denied } = await requirePricingAdmin("Central de Relatórios", FileText);
  if (denied) return denied;

  return (
    <AppShell title="Central de Relatórios" icon={FileText}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Central de Relatórios</PageTitle>
            </div>
            <PageDescription>Relatórios analíticos sobre preço e cobertura de mercado das Cartas.</PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {RELATORIOS.map(({ href, icon: Icon, title, description }) => (
            <Link key={href} href={href}>
              <Card density="compact" className="h-full transition-colors hover:border-primary/40 hover:bg-surface-muted/40">
                <CardContent density="compact" className="space-y-2 pt-4">
                  <Icon className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
                  <p className="text-sm font-medium text-foreground">{title}</p>
                  <p className="text-xs text-muted-foreground">{description}</p>
                </CardContent>
              </Card>
            </Link>
          ))}
        </div>
      </PageContainer>
    </AppShell>
  );
}
