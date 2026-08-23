import { RefreshCw } from "lucide-react";
import { Panel, PanelContent, PanelHeader, PanelTitle } from "@/components/catalogo/panel";
import { Badge } from "@/components/ui/badge";
import type { PricingAdminOverview } from "@/lib/pricing/queries";

function formatDateTime(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString("pt-BR", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

/**
 * Status do Dispatcher — bloco só-leitura (constraint explícita de
 * Fabrício: sem disparo manual nesta V1, sem mexer em cron nem recalcular
 * `next_due_at` em massa). Reusa `overview.dispatcher`/`overview.sets` já
 * buscados por `get_pricing_admin_overview()` (Bloco 1) — nenhuma RPC nova
 * só para este bloco.
 */
export function DispatcherStatusPanel({ overview }: { overview: PricingAdminOverview }) {
  const { dispatcher, sets } = overview;

  return (
    <Panel>
      <PanelHeader className="flex-row items-center justify-between">
        <PanelTitle>Dispatcher</PanelTitle>
        {dispatcher && (
          <Badge variant={dispatcher.active ? "primary" : "warning"}>
            {dispatcher.active ? "Ativo" : "Inativo"}
          </Badge>
        )}
      </PanelHeader>
      <PanelContent className="space-y-2">
        {dispatcher ? (
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">Agenda</span>
            <span className="font-medium text-foreground">{dispatcher.schedule}</span>
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">Nenhuma agenda configurada.</p>
        )}
        <div className="flex items-center justify-between text-xs">
          <span className="flex items-center gap-1 text-muted-foreground">
            <RefreshCw className="h-3 w-3" aria-hidden="true" />
            Próxima execução prevista
          </span>
          <span className="font-medium tabular-nums text-foreground">{formatDateTime(sets.next_due_at)}</span>
        </div>
        <p className="pt-1 text-[11px] text-muted-foreground">
          {sets.healthy} saudáveis · {sets.problem} com problema · {sets.paused} pausados de {sets.total} Sets
        </p>
        <p className="pt-1 text-[11px] text-muted-foreground">
          Disparo manual e recálculo em massa não estão disponíveis nesta tela — o dispatcher roda apenas pela
          agenda automática.
        </p>
      </PanelContent>
    </Panel>
  );
}
