import { ComingSoonPage } from "@/components/coming-soon-page";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";

export default async function JogosPage() {
  const { denied } = await requireCatalogoAdmin("Jogos");
  if (denied) return denied;

  return <ComingSoonPage title="Jogos" description="Listagem de jogos do catálogo" />;
}
