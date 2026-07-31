import { Plus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { PageActions, PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento da tela Catálogo — blocos no formato exato dos
 * cards da galeria, nunca spinner/barra de progresso (decisão da spec
 * aprovada). Também serve de fronteira de Suspense exigida por
 * `useSearchParams()` em `CatalogoSearchBar` — Next.js já envolve
 * automaticamente o conteúdo da rota nesta fronteira quando este arquivo
 * existe, sem precisar declarar um `<Suspense>` manual.
 */
export default function CatalogoLoading() {
  return (
    <AppShell title="Catálogo">
      <PageContainer width="wide">
        <PageHeader>
          <PageHeading>
            <PageTitle>Catálogo</PageTitle>
            <PageDescription>Explore os Card Sets catalogados, por Jogo ou por busca direta.</PageDescription>
          </PageHeading>
          <PageActions>
            <Button type="button" size="sm" disabled>
              <Plus className="h-3.5 w-3.5" />
              Novo
            </Button>
          </PageActions>
        </PageHeader>

        <div className="flex items-center gap-2">
          <Skeleton className="h-10 flex-1 rounded-md" />
          <Skeleton className="h-10 w-[9.5rem] shrink-0 rounded-md" />
        </div>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
          {Array.from({ length: 12 }).map((_, index) => (
            <div key={index} className="overflow-hidden rounded-lg border border-border">
              <Skeleton className="aspect-square w-full rounded-none" />
              <div className="space-y-1.5 p-3">
                <Skeleton className="h-3 w-16" />
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-3 w-1/2" />
              </div>
            </div>
          ))}
        </div>
      </PageContainer>
    </AppShell>
  );
}
