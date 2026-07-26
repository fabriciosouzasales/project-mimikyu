import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

export default async function ExpansoesPage() {
  const { denied } = await requireCatalogoAdmin("Expansões");
  if (denied) return denied;

  return <ComingSoonPage title="Expansões" description="Listagem de expansões" />;
}
