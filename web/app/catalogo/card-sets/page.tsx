import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

export default async function CardSetsPage() {
  const { denied } = await requireCatalogoAdmin("Card Sets");
  if (denied) return denied;

  return <ComingSoonPage title="Card Sets" description="Listagem de Card Sets" />;
}
