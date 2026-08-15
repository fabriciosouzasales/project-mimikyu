import { BookOpen, ClipboardList, FileText, ImageOff, Layers, Layers3, PieChart, ShieldCheck } from "lucide-react";
import Link from "next/link";
import { AppShell } from "@/components/app-shell/app-shell";
import { Card, CardContent } from "@/components/ui/card";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";

/**
 * Hub da Central de Relatórios (/catalogo/relatorios) — última das 4 frentes
 * da Trilha 4 (Módulo Gerencial), V1 aprovada por Fabrício (2026-08-09).
 * 6 relatórios previstos em `ROADMAP.md`, todos imprimíveis (`@media
 * print`, ver `web/app/globals.css`), sem motor de PDF. Dos 6, só
 * "Checklist por Coleção" e "Resumo da Coleção" mostram o dado de UMA
 * Coleção por vez (pedem Coleção via `RelatorioColecaoSeletor` na própria
 * página do relatório) — os outros 4 já são tabelas cruzando todas as
 * Coleções, sem seletor.
 *
 * 7º relatório "Cobertura de Card Variant" (2026-08-14, ADR-028, Query 2135)
 * — fora da V1 original dos 6, adicionado como primeiro incremento técnico
 * do bloco Card Variant; mesmo padrão visual/estrutural dos demais
 * relatórios sem seletor.
 */
const RELATORIOS = [
  {
    href: "/catalogo/relatorios/checklist",
    icon: ClipboardList,
    title: "Checklist por Coleção",
    description: "Lista completa das Cartas de uma Coleção — número, nome, raridade e status de cadastro.",
  },
  {
    href: "/catalogo/relatorios/cartas-pendentes",
    icon: FileText,
    title: "Cartas pendentes por Coleção",
    description: "Coleções com Cartas ainda não cadastradas frente ao tamanho oficial do Set.",
  },
  {
    href: "/catalogo/relatorios/imagens-pendentes",
    icon: ImageOff,
    title: "Imagens pendentes por Coleção",
    description: "Coleções com Cartas cadastradas sem imagem canônica em nenhum idioma ativo.",
  },
  {
    href: "/catalogo/relatorios/qualidade",
    icon: ShieldCheck,
    title: "Qualidade do Catálogo",
    description: "Cadastro, imagem e cartas inativas — visão detalhada por Coleção, todas em uma tabela.",
  },
  {
    href: "/catalogo/relatorios/resumo",
    icon: Layers3,
    title: "Resumo da Coleção",
    description: "Ficha de uma Coleção: totais, cobertura por idioma e estado geral.",
  },
  {
    href: "/catalogo/relatorios/cobertura-geral",
    icon: PieChart,
    title: "Cobertura Geral",
    description: "Cobertura de imagem por Coleção e idioma, em uma única tabela.",
  },
  {
    href: "/catalogo/relatorios/cobertura-variantes",
    icon: Layers,
    title: "Cobertura de Card Variant",
    description: "Cards com pelo menos uma Card Variant cadastrada, por Coleção (ADR-028).",
  },
] as const;

export default async function RelatoriosPage() {
  const { denied } = await requireCatalogoAdmin("Catálogo editorial", BookOpen);
  if (denied) return denied;

  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <FileText className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Central de Relatórios</PageTitle>
            </div>
            <PageDescription>Relatórios imprimíveis sobre o estado do Catálogo Editorial.</PageDescription>
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
