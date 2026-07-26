import { notFound } from "next/navigation";
import { Construction } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { Panel, PanelContent, PanelDescription, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { SetTypeTag } from "@/components/catalogo/set-type-tag";
import { StateBadge } from "@/components/catalogo/state-badge";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { getCardSetByCode } from "@/lib/catalogo/queries";

/**
 * Detalhe mínimo de um Card Set — destino real da tabela navegável da
 * Visão Geral. O design completo desta tela (galeria de cartas, edição de
 * logo via admin_set_card_set_logo(), histórico de importações do Set) é
 * um incremento futuro; por ora mostra a mesma base de dados já resumida
 * na tabela, sem duplicar o resumo geral.
 */
export default async function CardSetDetailPage({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const { denied, supabase } = await requireCatalogoAdmin(code);
  if (denied) return denied;

  const cardSet = await getCardSetByCode(supabase, code);
  if (!cardSet) {
    notFound();
  }

  return (
    <AppShell title={cardSet.name}>
      <div className="mx-auto max-w-2xl space-y-4">
        <div className="flex items-center gap-2">
          <h1 className="font-heading text-xl font-medium text-foreground">{cardSet.name}</h1>
          <SetTypeTag setType={cardSet.setType} />
        </div>
        <p className="-mt-3 text-xs text-muted-foreground">{cardSet.code}</p>

        <Panel>
          <PanelHeader>
            <PanelTitle>Estado do Set</PanelTitle>
          </PanelHeader>
          <PanelContent className="grid grid-cols-3 gap-4 text-sm">
            <div>
              <p className="text-[11px] text-muted-foreground">Cartas catalogadas</p>
              <p className="mt-0.5 text-foreground">
                {cardSet.cardsCatalogados}/{cardSet.totalSetSize}
              </p>
            </div>
            <div>
              <p className="text-[11px] text-muted-foreground">Imagens</p>
              <p className="mt-0.5">
                {cardSet.temImagensCompletas ? (
                  <StateBadge tone="success">Completas</StateBadge>
                ) : (
                  <StateBadge tone="warning">Pendente</StateBadge>
                )}
              </p>
            </div>
            <div>
              <p className="text-[11px] text-muted-foreground">Logo</p>
              <p className="mt-0.5 text-foreground">{cardSet.temLogo ? "Cadastrada" : "—"}</p>
            </div>
          </PanelContent>
        </Panel>

        <Panel>
          <PanelContent className="flex flex-col items-center gap-2 py-10 pt-10 text-center">
            <Construction className="h-4 w-4 text-muted-foreground" strokeWidth={1.5} />
            <p className="text-sm text-foreground">Detalhe completo em construção</p>
            <p className="max-w-xs text-xs text-muted-foreground">
              Galeria de cartas, edição de logo e histórico de importações deste Set chegam em um incremento futuro.
            </p>
          </PanelContent>
        </Panel>
      </div>
    </AppShell>
  );
}
