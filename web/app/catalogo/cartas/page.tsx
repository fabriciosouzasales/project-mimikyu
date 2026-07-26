import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

export default async function CartasPage() {
  const { denied } = await requireCatalogoAdmin("Cartas");
  if (denied) return denied;

  return <ComingSoonPage title="Cartas" description="Busca e listagem de Cards" />;
}
