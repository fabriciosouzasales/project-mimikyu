import { FileText } from "lucide-react";
import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

/**
 * Placeholder do grupo "Operação" do menu do Catálogo (2026-07-31, ver
 * `nav-config.ts`) — sem tela própria ainda, só o link precisava existir
 * para o menu não levar a um 404.
 */
export default async function ImportacaoPdfPage() {
  const { denied } = await requireCatalogoAdmin("Importação Via PDF", FileText);
  if (denied) return denied;

  return (
    <ComingSoonPage
      title="Importação Via PDF"
      description="Importação de cartas a partir de arquivos PDF."
      icon={FileText}
    />
  );
}
