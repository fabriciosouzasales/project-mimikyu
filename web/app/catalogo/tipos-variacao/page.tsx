import { Sparkles } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { TiposVariacaoTable } from "@/components/catalogo/tipos-variacao-table";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import { getCardVariantTypesAdmin } from "@/lib/catalogo/queries";

/**
 * Tela /catalogo/tipos-variacao (Incremento 2, ADR-028 — Governança da
 * Taxonomia de Card Variant Type). Mesmo padrão de /catalogo/raridades:
 * cadastro/edição self-service via Dialog, nenhuma escrita direta na
 * tabela — sempre pelas RPCs admin_create_card_variant_type()/
 * admin_update_card_variant_type()/admin_deactivate_card_variant_type()/
 * admin_reactivate_card_variant_type() (Queries 2154-2157).
 *
 * `getCardVariantTypesAdmin` traz TODOS os tipos (ativos e inativos) — a
 * administração precisa ver e poder reativar um tipo inativo, diferente do
 * seletor de novos mappings (`getCardVariantTypesForJob`), que filtra só
 * ativos.
 */
export default async function TiposVariacaoPage() {
  const { denied, supabase } = await requireCatalogoAdmin("Tipos de Variação", Sparkles);
  if (denied) return denied;

  const tiposVariacao = await getCardVariantTypesAdmin(supabase);

  return (
    <AppShell title="Tipos de Variação" icon={Sparkles}>
      <PageContainer>
        <TiposVariacaoTable tiposVariacao={tiposVariacao} />
      </PageContainer>
    </AppShell>
  );
}
