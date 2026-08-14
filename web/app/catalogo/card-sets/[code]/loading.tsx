import { Boxes, CreditCard } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento do hub de Card Set (Incremento 2 da frente de
 * performance, 2026-08-14) — este `page.tsx` não usa `PageContainer` (só
 * `<div className="mx-auto max-w-6xl space-y-4">`, ver comentário lá),
 * reproduzido aqui exatamente igual. `AppShell` não recebe `title` real
 * (o nome do Card Set só é conhecido depois da query) — mesma solução já
 * usada em `catalogo-guard.tsx` para a tela de "Acesso restrito": título
 * genérico ("Coleção") só para o breadcrumb do cabeçalho não ficar vazio
 * durante o carregamento.
 *
 * Estrutura reproduzida: cabeçalho (logo `h-20 w-32` + 3 linhas de texto),
 * Panel "Estado do Set" (4 blocos de métrica + Cobertura por idioma), linha
 * de ações (5 botões reais, desabilitados) e Panel "Cartas da Coleção" com
 * grid de cartas (`aspect-[5/7]`, mesma proporção de `card-set-cartas-grid.tsx`).
 * Nenhuma query/autenticação/lógica de negócio entra aqui.
 */
export default function CardSetDetailLoading() {
  return (
    <AppShell title="Coleção" icon={Boxes}>
      <div className="mx-auto max-w-6xl space-y-4">
        <div className="flex items-center gap-4">
          <Skeleton className="h-20 w-32 shrink-0 rounded-md" />
          <div className="space-y-1.5">
            <Skeleton className="h-5 w-56 rounded-md" />
            <Skeleton className="h-3 w-40 rounded-md" />
            <Skeleton className="h-3 w-28 rounded-md" />
          </div>
        </div>

        <Panel>
          <PanelHeader>
            <PanelTitle>Estado do Set</PanelTitle>
          </PanelHeader>
          <PanelContent className="flex flex-wrap items-start gap-x-8 gap-y-4">
            <div className="space-y-1.5">
              <Skeleton className="h-2.5 w-20 rounded" />
              <Skeleton className="h-4 w-24 rounded" />
            </div>
            <div className="space-y-1.5">
              <Skeleton className="h-2.5 w-24 rounded" />
              <Skeleton className="h-4 w-20 rounded" />
            </div>
            <div className="space-y-1.5">
              <Skeleton className="h-2.5 w-16 rounded" />
              <Skeleton className="h-4 w-20 rounded" />
            </div>
            <div className="space-y-1.5">
              <Skeleton className="h-2.5 w-24 rounded" />
              <Skeleton className="h-4 w-16 rounded" />
            </div>
            <div className="min-w-0">
              <Skeleton className="h-2.5 w-32 rounded" />
              <div className="mt-1.5 flex flex-wrap gap-x-6 gap-y-3">
                <Skeleton className="h-10 w-full rounded-md sm:w-56" />
                <Skeleton className="h-10 w-full rounded-md sm:w-56" />
              </div>
            </div>
          </PanelContent>
        </Panel>

        <div className="space-y-2">
          <div className="flex flex-wrap justify-end gap-2">
            <Button type="button" size="sm" disabled>
              Importar Cartas
            </Button>
            <Button type="button" size="sm" variant="outline" disabled>
              Importar Imagens
            </Button>
            <Button type="button" size="sm" variant="outline" disabled>
              Histórico de Importações
            </Button>
            <Button type="button" size="sm" variant="outline" disabled>
              Checklist
            </Button>
            <Button type="button" size="sm" variant="outline" disabled>
              Resumo
            </Button>
          </div>

          <Panel>
            <PanelHeader>
              <div className="flex items-center gap-1.5">
                <CreditCard className="h-3.5 w-3.5 text-muted-foreground" aria-hidden="true" />
                <PanelTitle>Cartas da Coleção</PanelTitle>
              </div>
            </PanelHeader>
            <PanelContent>
              <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8">
                {Array.from({ length: 16 }).map((_, index) => (
                  <Skeleton key={index} className="aspect-[5/7] w-full rounded-lg" />
                ))}
              </div>
            </PanelContent>
          </Panel>
        </div>
      </div>
    </AppShell>
  );
}
