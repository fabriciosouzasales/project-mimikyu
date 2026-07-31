import { Layers, Plus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento da tela de Expansões — mesmo formato exato do
 * skeleton da tela Catálogo (`/catalogo/card-sets/loading.tsx`), atualizado
 * em 2026-07-31 pra acompanhar o redesenho de `expansoes-gallery.tsx`:
 * ícone antes do título, skeletons dos 4 cards de indicador (Jogos/
 * Expansões/Coleções/Sem Coleções), botão "Nova expansão" fora do
 * cabeçalho (acima da busca, mesmo lugar da tela real), busca/filtro e
 * grid de cards dentro do mesmo `Card` branco (mesma rodada: busca deixou
 * de flutuar solta). Também serve de fronteira de Suspense exigida por
 * `useSearchParams()` em `CatalogoSearchBar`.
 */
export default function ExpansoesLoading() {
  return (
    <AppShell title="Expansões" icon={Layers}>
      <PageContainer width="wide">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Expansões</PageTitle>
            </div>
            <PageDescription>Explore as Expansões catalogadas, por Jogo ou por busca direta.</PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="flex flex-wrap gap-3">
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
        </div>

        <div className="space-y-2">
          <div className="flex justify-end">
            <Button type="button" size="sm" disabled>
              <Plus className="h-3.5 w-3.5" />
              Nova expansão
            </Button>
          </div>

          <Card density="compact" className="overflow-hidden">
            <div className="flex items-center gap-2 border-b border-border p-4">
              <Skeleton className="h-9 flex-1 rounded-md" />
              <Skeleton className="h-9 w-[9.5rem] shrink-0 rounded-md" />
            </div>

            <CardContent density="compact" className="pt-4">
              <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
                {Array.from({ length: 12 }).map((_, index) => (
                  <div key={index} className="overflow-hidden rounded-lg border border-border">
                    <Skeleton className="h-28 w-full rounded-none" />
                    <div className="space-y-1.5 p-3">
                      <Skeleton className="h-3 w-16" />
                      <Skeleton className="h-4 w-3/4" />
                      <Skeleton className="h-3 w-1/2" />
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </PageContainer>
    </AppShell>
  );
}
