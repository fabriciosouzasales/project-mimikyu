import { Plus, Tag } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/** Estado de carregamento da tela Raridades — mesmo formato do skeleton de Jogos. */
export default function RaridadesLoading() {
  return (
    <AppShell title="Raridades" icon={Tag}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <Tag className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Raridades</PageTitle>
            </div>
            <PageDescription>
              Raridades canônicas do catálogo e seus mapeamentos por fonte externa (TCGdex).
            </PageDescription>
          </PageHeading>
        </PageHeader>

        <Skeleton className="h-24 w-full rounded-lg" />

        <div className="space-y-2">
          <div className="flex justify-end">
            <Button type="button" size="sm" disabled>
              <Plus className="h-3.5 w-3.5" />
              Nova Raridade
            </Button>
          </div>

          <div className="overflow-hidden rounded-lg border border-border">
            <Skeleton className="h-8 w-full rounded-none" />
            {Array.from({ length: 6 }).map((_, index) => (
              <div key={index} className="flex items-center gap-4 border-t border-border/60 px-4 py-3">
                <Skeleton className="h-4 w-4" />
                <Skeleton className="h-4 w-32" />
                <Skeleton className="h-4 w-24" />
                <Skeleton className="h-4 w-40" />
                <Skeleton className="h-4 w-20" />
              </div>
            ))}
          </div>
        </div>
      </PageContainer>
    </AppShell>
  );
}
