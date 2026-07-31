import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

/**
 * Placeholder do grupo "Operação" do menu do Catálogo (2026-07-31, ver
 * `nav-config.ts`) — sem tela própria ainda, só o link precisava existir
 * para o menu não levar a um 404. Guarda de admin roda antes do
 * `ComingSoonPage` (mesmo padrão de todas as outras rotas do módulo,
 * ADR-022) — a diferença de /configuracoes é que aquela rota não é
 * restrita a administradores.
 */
export default async function ImportacaoManualPage() {
  const { denied } = await requireCatalogoAdmin("Importação Manual");
  if (denied) return denied;

  return (
    <ComingSoonPage
      title="Importação Manual"
      description="Registro manual de execuções de importação de imagens de cartas."
    />
  );
}
