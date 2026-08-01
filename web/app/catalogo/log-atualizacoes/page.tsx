import { ScrollText } from "lucide-react";
import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

/**
 * Placeholder do grupo "Gerencial" do menu do Catálogo (2026-08-01, ver
 * `nav-config.ts`) — trilha de auditoria de escrita administrativa
 * (`catalog_admin_action_log`, ADR-023), distinta do "Histórico de
 * Importações" (execuções do pipeline de imagens, `asset_import_run`) já
 * existente no mesmo bloco. Sem tela própria ainda — item de menu não
 * pode levar a 404 (bug já reportado por Fabrício, 2026-07-25), mesmo
 * padrão de todas as outras rotas ainda não implementadas do módulo.
 */
export default async function LogAtualizacoesPage() {
  const { denied } = await requireCatalogoAdmin("Log de Atualizações", ScrollText);
  if (denied) return denied;

  return (
    <ComingSoonPage
      title="Log de Atualizações"
      description="Trilha de auditoria das escritas administrativas do catálogo editorial (catalog_admin_action_log)."
      icon={ScrollText}
    />
  );
}
