import { ImagePlus } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { PageContainer, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { Skeleton } from "@/components/ui/skeleton";

/**
 * Estado de carregamento de Importar Imagens (Incremento 2 da frente de
 * performance, 2026-08-14) — `page.tsx` não renderiza `PageHeader` (fica
 * dentro de `ImportarImagensView`), então este fallback reproduz o mesmo
 * cabeçalho real (ícone/título/descrição idênticos, texto estático). Abaixo:
 * `StatsRow` de 2 indicadores e o mesmo `Card` único (combobox de Coleção +
 * toggles Fonte/Idioma + botão "Importar Imagens", todos reais e
 * desabilitados) — mesma estrutura de `importar-imagens-view.tsx`. A área de
 * progresso/picker manual abaixo do `Card` só existe depois de uma ação do
 * usuário (nunca no carregamento inicial), então não faz parte deste
 * fallback. Nenhuma query/autenticação/lógica de negócio entra aqui.
 */
export default function ImportarImagensLoading() {
  return (
    <AppShell title="Importar Imagens" icon={ImagePlus}>
      <PageContainer>
        <PageHeader>
          <PageHeading>
            <div className="flex items-center gap-2">
              <ImagePlus className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
              <PageTitle>Importar Imagens</PageTitle>
            </div>
            <PageDescription>Retomada da ingestão de imagens de cartas (card_asset) já cadastradas.</PageDescription>
          </PageHeading>
        </PageHeader>

        <div className="flex flex-wrap gap-3">
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
          <Skeleton className="h-[72px] w-full rounded-lg sm:w-56" />
        </div>

        <Card>
          <CardContent className="space-y-4 pt-6">
            <div className="space-y-1">
              <Skeleton className="h-2.5 w-64 rounded" />
              <div className="flex flex-wrap items-stretch gap-2">
                <Skeleton className="h-9 min-w-[240px] max-w-[500px] flex-1 rounded-md" />
                <Skeleton className="h-9 w-20 shrink-0 rounded-md" />
                <Skeleton className="h-9 w-24 shrink-0 rounded-md" />
                <Button type="button" className="h-9 shrink-0" disabled>
                  Importar Imagens
                </Button>
              </div>
            </div>

            <div className="border-t border-border pt-4">
              <Skeleton className="h-4 w-72 rounded" />
            </div>
          </CardContent>
        </Card>
      </PageContainer>
    </AppShell>
  );
}
