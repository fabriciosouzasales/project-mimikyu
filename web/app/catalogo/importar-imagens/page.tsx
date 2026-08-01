import { ImagePlus } from "lucide-react";
import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

/**
 * Placeholder do grupo "Operações" do menu do Catálogo (2026-08-01, ver
 * `nav-config.ts`) — substitui "Importação Manual"/"Via PDF"/"Via API"
 * (categorização por método, nunca implementada) por uma categorização
 * pelo que é importado: ingestão de imagens de Card (`card_asset`). Sem
 * tela própria ainda — item de menu não pode levar a 404 (bug já
 * reportado por Fabrício, 2026-07-25), mesmo padrão de todas as outras
 * rotas ainda não implementadas do módulo.
 */
export default async function ImportarImagensPage() {
  const { denied } = await requireCatalogoAdmin("Importar Imagens", ImagePlus);
  if (denied) return denied;

  return (
    <ComingSoonPage
      title="Importar Imagens"
      description="Ingestão de imagens de cartas (card_asset) no catálogo editorial."
      icon={ImagePlus}
    />
  );
}
