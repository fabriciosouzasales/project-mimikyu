import { Gamepad2, Plus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento da tela Jogos — mesmo formato do skeleton de
 * Expansões, adaptado (indicadores + tabela em vez de galeria de cards).
 * Também serve de fronteira de Suspense exigida por `useSearchParams()`
 * em `CatalogoSearchBar`.
 */
export default function JogosLoading() {
  return (
    <AppShell title="Jogos" icon={Gamepad2}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Gamepad2 className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Jogos</PageTitle>
            </div>
            <PageDescription>Cadastro e edição de Jogos do catálogo.</PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="flex flex-wrap gap-3">
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
        </div>

        {/* "Novo Jogo" com espaçamento apertado (space-y-2) até o card —
            a busca agora mora dentro do próprio card da tabela, mesmo
            ajuste do componente real (`jogos-table.tsx`). */}
        <div className="space-y-2">
          <div className="flex justify-end">
            <Button type="button" size="sm" disabled>
              <Plus className="h-3.5 w-3.5" />
              Novo Jogo
            </Button>
          </div>

          <div className="overflow-hidden rounded-lg border border-border">
            <div className="border-b border-border p-4">
              <Skeleton className="h-9 w-full rounded-md" />
            </div>
            <Skeleton className="h-8 w-full rounded-none" />
            {Array.from({ length: 4 }).map((_, index) => (
              <div key={index} className="flex items-center gap-4 border-t border-border/60 px-4 py-3">
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-4 w-10" />
                <Skeleton className="h-4 w-20" />
                <Skeleton className="h-4 w-20" />
              </div>
            ))}
          </div>
        </div>
      </PageContainer>
    </AppShell>
  );
}
