import { FileUp } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { ImportarCartasView } from "@/components/catalogo/importar-cartas-view";
import { PageContainer } from "@/components/ui/page";
import { getCardSetsForCartas } from "@/lib/catalogo/queries";

/**
 * Grupo "Operações" do menu do Catálogo (`nav-config.ts`) — substitui
 * "Importação Manual"/"Via PDF"/"Via API" (categorização por método, nunca
 * implementada) por uma categorização pelo que é importado:
 * cadastro/atualização de Cards em lote.
 *
 * Ganhou estrutura própria em 2026-08-01 (pedido de Fabrício: "vamos ter as
 * opções de importar cartas via pdf... ou importar via API (TCGDEX)"),
 * deixando de ser `ComingSoonPage` — ver `ImportarCartasView` para as duas
 * frentes (PDF/API), ainda sem lógica de importação real. `colecoesSemCartas`
 * reaproveita `getCardSetsForCartas()` (mesma consulta de `CartasStats`) só
 * para contextualizar o escopo da opção via API.
 */
export default async function ImportarCartasPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Importar Cartas", FileUp);
  if (denied) return denied;

  const cardSets = await getCardSetsForCartas(supabase);
  const colecoesSemCartas = cardSets.filter((cardSet) => cardSet.cardsCatalogados === 0).length;

  return (
    <AppShell title="Importar Cartas" icon={FileUp}>
      <PageContainer>
        <ImportarCartasView colecoesSemCartas={colecoesSemCartas} />
      </PageContainer>
    </AppShell>
  );
}
