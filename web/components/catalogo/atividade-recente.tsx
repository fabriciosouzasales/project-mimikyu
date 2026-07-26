import { StateBadge } from "@/components/catalogo/state-badge";
import type { StateTone } from "@/components/catalogo/state-badge";
import type { AtividadeRecenteItem } from "@/lib/catalogo/queries";

const STATUS_LABEL: Record<string, { texto: string; tone: StateTone }> = {
  COMPLETED: { texto: "Concluída", tone: "success" },
  COMPLETED_WITH_ERRORS: { texto: "Com falhas", tone: "warning" },
  FAILED: { texto: "Falhou", tone: "danger" },
  RUNNING: { texto: "Em andamento", tone: "muted" },
  PENDING: { texto: "Pendente", tone: "muted" },
  CANCELLED: { texto: "Cancelada", tone: "muted" },
};

function descreverExecucao(item: AtividadeRecenteItem): string {
  const alvo = item.cardSetName ? `${item.cardSetName} (${item.cardSetCode})` : "um Card Set";
  const idioma = item.languageCode ? ` em ${item.languageCode}` : "";

  if (item.status === "COMPLETED") {
    return `Importação de ${alvo}${idioma} concluída — ${item.successCount} carta${item.successCount === 1 ? "" : "s"}.`;
  }
  if (item.status === "COMPLETED_WITH_ERRORS" || item.status === "FAILED") {
    return `Importação de ${alvo}${idioma} com pendências — ${item.failedCount}/${item.requestedCount} sem imagem.`;
  }
  return `Importação de ${alvo}${idioma} — ${item.requestedCount} carta${item.requestedCount === 1 ? "" : "s"} solicitada${item.requestedCount === 1 ? "" : "s"}.`;
}

/**
 * Feed traduzido para linguagem natural — a informação continua sendo
 * administrativa: renderizado só dentro da guarda de admin de /catalogo
 * (ADR-022), nunca fica público. Status por `StateBadge` — discreta, mas
 * mantida como pílula colorida (ajuste de Fabrício: estados importantes
 * continuam com badge, não viram só um ponto).
 */
export function AtividadeRecente({ atividades }: { atividades: AtividadeRecenteItem[] }) {
  if (atividades.length === 0) {
    return (
      <div className="flex flex-col items-center gap-1 py-8 text-center">
        <p className="text-sm text-foreground">Nenhuma atividade registrada</p>
        <p className="text-xs text-muted-foreground">Importações de imagens aparecem aqui conforme rodam.</p>
      </div>
    );
  }

  return (
    <ul className="divide-y divide-border/60">
      {atividades.map((item) => {
        const status = STATUS_LABEL[item.status] ?? { texto: item.status, tone: "muted" as const };
        return (
          <li key={item.id} className="flex items-start justify-between gap-3 py-2 text-sm first:pt-0 last:pb-0">
            <div className="min-w-0">
              <p className="text-foreground">{descreverExecucao(item)}</p>
              <p className="mt-0.5 text-[11px] text-muted-foreground">
                {new Date(item.createdAt).toLocaleString("pt-BR")}
              </p>
            </div>
            <div className="shrink-0 pt-0.5">
              <StateBadge tone={status.tone}>{status.texto}</StateBadge>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
