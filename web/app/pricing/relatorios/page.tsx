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
import { StateBadge } from "@/components/catalogo/state-badge";
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
 *
 * v2 (2026-08-23, diagnóstico estrutural de UX/UI aprovado por Fabrício):
 * antes os 7 relatórios apareciam num único grid com peso visual idêntico —
 * nenhuma diferença entre os 2 relatórios funcionais e os 5 ainda em
 * desenvolvimento, o que fazia a Central parecer "grade de cards" incompleta
 * em vez de hub analítico. Passa a existir uma separação estática em duas
 * seções (`RELATORIOS_DISPONIVEIS`/`RELATORIOS_FUTUROS`) — puramente
 * composicional, os mesmos 7 objetos de sempre, sem nenhum dado novo e sem
 * nenhum fetch adicional nesta página (continua sendo uma constante em
 * memória, igual à v1). Os futuros recebem badge "Em breve", opacidade
 * reduzida e perdem o `hover` de convite a clique dos funcionais (sem
 * `<Link>` em volta — não há tela real por trás ainda).
 */
const RELATORIOS_DISPONIVEIS = [
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
] as const;

const RELATORIOS_FUTUROS = [
  {
    icon: SlidersHorizontal,
    title: "Preço por Condição",
    description: "Comparativo de preço entre as condições de uma mesma Carta.",
  },
  {
    icon: History,
    title: "Histórico de Preços",
    description: "Evolução de preço agregada por Set ou por fonte ao longo do tempo.",
  },
  {
    icon: GitCompare,
    title: "Comparativo de Fontes",
    description: "Divergência de preço entre fontes homologadas para a mesma Carta.",
  },
  {
    icon: Trophy,
    title: "Cartas Mais Valiosas",
    description: "Ranking das Cartas de maior valor estimado, com filtro por Set ou coleção completa.",
  },
  {
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

        <div className="space-y-6">
          <section className="space-y-3">
            <h2 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Relatórios Disponíveis
            </h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {RELATORIOS_DISPONIVEIS.map(({ href, icon: Icon, title, description }) => (
                <Link key={href} href={href}>
                  <Card
                    density="compact"
                    className="h-full border-border/80 transition-colors hover:border-primary/40 hover:bg-surface-muted/40"
                  >
                    <CardContent density="compact" className="space-y-2 pt-4">
                      <Icon className="h-6 w-6 text-primary-ink" aria-hidden="true" />
                      <p className="text-sm font-semibold text-foreground">{title}</p>
                      <p className="text-xs text-muted-foreground">{description}</p>
                    </CardContent>
                  </Card>
                </Link>
              ))}
            </div>
          </section>

          <section className="space-y-3">
            <h2 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Em Desenvolvimento</h2>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {RELATORIOS_FUTUROS.map(({ icon: Icon, title, description }) => (
                <Card
                  key={title}
                  density="compact"
                  className="h-full cursor-default opacity-60 grayscale-[35%]"
                  aria-disabled="true"
                >
                  <CardContent density="compact" className="space-y-2 pt-4">
                    <div className="flex items-center justify-between gap-2">
                      <Icon className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
                      <StateBadge tone="muted">Em breve</StateBadge>
                    </div>
                    <p className="text-sm font-medium text-foreground">{title}</p>
                    <p className="text-xs text-muted-foreground">{description}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        </div>
      </PageContainer>
    </AppShell>
  );
}
