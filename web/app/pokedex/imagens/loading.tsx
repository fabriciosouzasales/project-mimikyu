import { Images } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Card } from "@/components/ui/card";
import { PageContainer } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/** Carregamento de Pokédex → Imagens — mesma geometria da página real (indicadores, filtros, tabela). */
export default function PokedexImagensLoading() {
  return (
    <AppShell title="Imagens" icon={Images}>
      <PageContainer width="wide" aria-busy="true" aria-label="Carregando imagens das espécies">
        <div className="space-y-1.5">
          <Skeleton className="h-6 w-56" />
          <Skeleton className="h-4 w-96 max-w-full" />
        </div>
        <div className="flex flex-wrap gap-3">
          {Array.from({ length: 3 }).map((_, index) => (
            <Skeleton key={index} className="h-[74px] w-full rounded-lg sm:w-56" />
          ))}
        </div>
        <Card className="overflow-hidden">
          <div className="flex flex-col gap-3 border-b border-border p-3 lg:flex-row lg:justify-between">
            <div className="flex gap-1.5">
              {Array.from({ length: 4 }).map((_, index) => (
                <Skeleton key={index} className="h-8 w-24 rounded-full" />
              ))}
            </div>
            <Skeleton className="h-9 w-full lg:w-80" />
          </div>
          <div className="divide-y divide-border/60">
            {Array.from({ length: 10 }).map((_, index) => (
              <div key={index} className="flex items-center gap-4 px-3 py-2">
                <Skeleton className="h-10 w-10 rounded-md" />
                <Skeleton className="h-4 w-10" />
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-16 rounded-full" />
                <Skeleton className="ml-auto h-[26px] w-28" />
              </div>
            ))}
          </div>
        </Card>
      </PageContainer>
    </AppShell>
  );
}
