import Link from "next/link";
import { FileText, Globe, type LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { cn } from "@/lib/utils";

/**
 * Estrutura visual da página "Importar Cartas" — primeiro passo do subciclo
 * de importação em lote de Card (2026-08-01, pedido de Fabrício, sequência
 * ao botão "Importar Cartas" da tela Cartas). Duas frentes, cada uma ainda
 * "em construção" (mesmo tom do `ComingSoonPage`, sem lógica de importação
 * real nesta rodada):
 *
 * 1. "Importar via PDF" — leitura da lista de verificação oficial (checklist
 *    impresso/PDF usado para conferência física da coleção). O modelo de
 *    referência ainda não foi anexado por Fabrício nesta rodada — o
 *    detalhamento do fluxo (upload, parsing, mapeamento de campos) fica
 *    para quando o anexo chegar.
 * 2. "Importar via API (TCGDex)" — cadastro automático a partir da API
 *    pública TCGDex, restrito a Coleções que ainda não têm nenhuma carta
 *    catalogada (pedido explícito: "para as coleções que ainda estão sem
 *    cartas cadastradas"). `colecoesSemCartas` (resolvido em `page.tsx` via
 *    `getCardSetsForCartas()`, mesmo dado usado por `CartasStats`) só
 *    contextualiza o escopo — nenhuma Coleção é listada nominalmente ainda.
 *
 * A frente PDF continua sem rota de destino real (mesmo princípio do
 * `ComingSoonPage`: item de menu/ação nunca leva a 404, mas também não
 * finge ter uma tela pronta). A frente TCGdex deixou de ser um cartão
 * estático em 2026-08-01 (Ciclo 2, Sprint 2a, ADR-024): agora linka para
 * `/catalogo/importar-cartas/tcgdex`, o fluxo real de importação.
 */
export function ImportarCartasView({ colecoesSemCartas }: { colecoesSemCartas: number }) {
  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Importar Cartas</PageTitle>
          <PageDescription>Cadastro e atualização de Cards em lote no catálogo editorial.</PageDescription>
        </PageHeading>
      </PageHeader>

      <div className="grid gap-4 sm:grid-cols-2">
        <ImportOptionCard
          icon={FileText}
          title="Importar via PDF"
          description="Cadastra cartas a partir da lista de verificação oficial (checklist em PDF) da Coleção."
        />
        <ImportOptionCard
          icon={Globe}
          title="Importar via API (TCGDex)"
          description="Cadastra cartas automaticamente via TCGDex, para Coleções que ainda não têm nenhuma carta catalogada."
          href="/catalogo/importar-cartas/tcgdex"
          caption={
            colecoesSemCartas > 0
              ? `${colecoesSemCartas} Coleç${colecoesSemCartas === 1 ? "ão" : "ões"} sem cartas hoje`
              : "Nenhuma Coleção sem cartas no momento"
          }
        />
      </div>
    </div>
  );
}

function ImportOptionCard({
  icon: Icon,
  title,
  description,
  caption,
  href,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
  caption?: string;
  href?: string;
}) {
  const content = (
    <Card className={cn("flex flex-col", href && "transition-colors hover:border-[#A39475]/60")}>
      <CardHeader className="flex-row items-start justify-between gap-3 space-y-0">
        <span
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[#F7F5ED] text-[#2C2C2A]"
          aria-hidden="true"
        >
          <Icon className="h-4 w-4" />
        </span>
        {!href && <Badge variant="outline">Em construção</Badge>}
      </CardHeader>
      <CardContent className="flex flex-1 flex-col gap-1.5">
        <p className="text-sm font-semibold text-foreground">{title}</p>
        <p className="text-sm text-muted-foreground">{description}</p>
        {caption && <p className="mt-auto pt-2 text-xs text-muted-foreground">{caption}</p>}
      </CardContent>
    </Card>
  );

  if (!href) return content;

  return (
    <Link href={href} className="block">
      {content}
    </Link>
  );
}
