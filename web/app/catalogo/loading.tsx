import { BookOpen, LayoutDashboard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageSection, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento da Visão Geral (Incremento 2 da frente de
 * performance, 2026-08-14) — mesmo formato já usado em `jogos`/`expansoes`/
 * `card-sets`/`raridades` (`AppShell` + cabeçalho real + blocos `Skeleton`
 * nas mesmas dimensões do conteúdo final de `page.tsx`/`visao-geral-stats.tsx`/
 * `card-sets-table.tsx`/`atividade-recente.tsx`). Só o layout/estrutura é
 * reproduzido — nenhuma query, autenticação ou lógica de negócio entra aqui.
 * Next.js envolve automaticamente o conteúdo da rota numa fronteira de
 * Suspense por causa deste arquivo, sem precisar de `<Suspense>` manual.
 */
export default function CatalogoVisaoGeralLoading() {
  return (
    <AppShell title="Catálogo editorial" icon={BookOpen}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <LayoutDashboard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Visão Geral</PageTitle>
            </div>
            <PageDescription>Indicadores gerais e navegação rápida para as Coleções do catálogo.</PageDescription>
          </PageHeading>
        </PageHeader>

        {/* VisaoGeralStats: StatsRow de 4 StatCards + painel "Cobertura por idioma" (max-w-md). */}
        <div className="space-y-3">
          <div className="flex flex-wrap gap-3">
            <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
            <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
            <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
            <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          </div>
          <Skeleton className="h-32 w-full max-w-md rounded-lg" />
        </div>

        <PageSection title="Coleções" description="Clique em uma Coleção para ver o detalhe.">
          <div className="overflow-hidden rounded-lg border border-border">
            <div className="border-b border-border p-4">
              <Skeleton className="h-9 w-full rounded-md" />
            </div>
            <Skeleton className="h-8 w-full rounded-none" />
            {Array.from({ length: 5 }).map((_, index) => (
              <div key={index} className="flex items-center gap-4 border-t border-border/60 px-4 py-3">
                <Skeleton className="h-10 w-16 rounded-md" />
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-4 w-16" />
              </div>
            ))}
          </div>
        </PageSection>

        <PageSection title="Atividade recente" description="Últimas execuções de importação — Cartas e Imagens.">
          <div className="overflow-hidden rounded-lg border border-border">
            <Skeleton className="h-8 w-full rounded-none" />
            {Array.from({ length: 5 }).map((_, index) => (
              <div key={index} className="flex items-center gap-4 border-t border-border/60 px-4 py-3">
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-4 w-20" />
                <Skeleton className="h-4 w-20" />
                <Skeleton className="h-4 w-20" />
              </div>
            ))}
          </div>
        </PageSection>
      </PageContainer>
    </AppShell>
  );
}
