import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

export default async function ImportacoesPage() {
  const { denied } = await requireCatalogoAdmin("Histórico de importações");
  if (denied) return denied;

  return <ComingSoonPage title="Histórico de importações" description="Runs de importação e falhas" />;
}
