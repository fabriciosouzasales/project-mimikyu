import { Tag } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { RaridadesTable } from "@/components/catalogo/raridades-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import { getRaridades, getRevalidacaoPendenteResumo } from "@/lib/catalogo/queries";

/**
 * Tela /catalogo/raridades (task #336, ciclo de cadastro self-service de
 * Raridade — ver `docs/log.md` 2026-08-06/07 e ADR/modelo de dados,
 * pendentes na task #337).
 *
 * Substitui o antigo fluxo de editar `RARITY_NAME_ALIASES` no código-fonte
 * (aposentado nesta rodada) — cadastro de raridade e mapeamento de valores
 * externos agora são inteiramente feitos por aqui, sem deploy. "Revalidar
 * tudo" recalcula linhas de staging já existentes contra o mapeamento atual
 * (`revalidate-catalog-import-rows`), sem reimportar do zero.
 */
export default async function RaridadesPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Raridades", Tag);
  if (denied) return denied;

  const [raridades, pendente] = await Promise.all([
    getRaridades(supabase),
    getRevalidacaoPendenteResumo(supabase),
  ]);

  return (
    <AppShell title="Raridades" icon={Tag}>
      <PageContainer>
        <RaridadesTable raridades={raridades} pendente={pendente} />
      </PageContainer>
    </AppShell>
  );
}
