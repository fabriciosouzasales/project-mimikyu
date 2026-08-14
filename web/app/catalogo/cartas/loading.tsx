import { CreditCard, FileUp, Plus, Search } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento da tela Cartas (Incremento 2 da frente de
 * performance, 2026-08-14) — `page.tsx` não renderiza `PageHeader` (fica
 * dentro de `CartasGallery`), então este fallback reproduz o mesmo cabeçalho
 * real (ícone/título/descrição idênticos, texto estático, não depende de
 * dado). Abaixo: `CartasStats` (4 StatCards), a mesma linha de ações
 * ("Nova Carta"/"Importar Cartas"), e o mesmo `Card` com busca + filtros no
 * topo e grid de cartas (`aspect-[5/7]`, mesma proporção de
 * `cartas-gallery.tsx`) — dimensões estáveis, sem CLS ao trocar para o
 * conteúdo real. Nenhuma query/autenticação/lógica de negócio entra aqui.
 */
export default function CartasLoading() {
  return (
    <AppShell title="Cartas" icon={CreditCard}>
      <PageContainer width="wide">
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <CreditCard className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Cartas</PageTitle>
            </div>
            <PageDescription>Explore as cartas catalogadas, Card Set por Card Set.</PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="flex flex-wrap gap-3">
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
        </div>

        <div className="space-y-2">
          <div className="flex justify-end gap-2">
            <Button type="button" size="sm" disabled>
              <Plus className="h-3.5 w-3.5" />
              Nova Carta
            </Button>
            <Button type="button" size="sm" disabled>
              <FileUp className="h-3.5 w-3.5" />
              Importar Cartas
            </Button>
          </div>

          <Card density="compact" className="overflow-hidden">
            <div className="space-y-3 border-b border-border p-4">
              <div className="flex items-center gap-2">
                <div className="relative min-w-0 flex-1">
                  <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <Input
                    disabled
                    placeholder="Buscar por nome ou número da carta…"
                    className="h-9 bg-surface-muted pl-9 text-xs"
                    aria-label="Buscar carta"
                  />
                </div>
                <Skeleton className="h-9 w-32 shrink-0 rounded-md" />
                <Skeleton className="h-9 w-32 shrink-0 rounded-md" />
                <Skeleton className="h-9 w-32 shrink-0 rounded-md" />
              </div>
            </div>

            <CardContent density="compact" className="pt-4">
              <div className="grid grid-cols-3 gap-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 xl:grid-cols-7">
                {Array.from({ length: 14 }).map((_, index) => (
                  <Skeleton key={index} className="aspect-[5/7] w-full rounded-lg" />
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </PageContainer>
    </AppShell>
  );
}
