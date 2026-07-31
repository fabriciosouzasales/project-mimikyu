"use client";

import { useActionState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import type { DeleteEntitiesActionState } from "@/lib/catalogo/admin-action-types";

const initialState: DeleteEntitiesActionState = { error: null };

/**
 * Confirmação inline de exclusão em massa — genérica sobre qualquer Server
 * Action que siga o contrato `DeleteEntitiesActionState`. Extraída do ciclo
 * de Game para reuso pelos ciclos de Expansion/Card Set.
 *
 * Ajuste de contraste no tema escuro (2026-07-31, pedido de Fabrício —
 * captura de tela da tela Coleções: "ajustar a cor da tarja vermelha ao
 * selecionar um card set para exclusão no modo escuro"): `--destructive` no
 * tema escuro é um vermelho muito escuro (20% de luminosidade, ver
 * `globals.css`) — a borda/fundo originais (`border-destructive/40
 * bg-destructive/5`) ficavam quase invisíveis sobre o fundo também escuro
 * do app, mesmo problema já diagnosticado e corrigido para o ícone de
 * `tone="danger"` em `StatCard`. Mesma técnica aqui: borda troca para
 * `destructive-foreground` (quase branco no tema escuro, 92% de
 * luminosidade) em opacidade baixa, e o fundo ganha mais opacidade (`/5` →
 * `/20`) só no tema escuro — no tema claro nada muda.
 */
export function ConfirmDeleteBar({
  items,
  action,
  nounSingular,
  nounPlural,
  onDone,
  onPartialSuccess,
  onCancel,
}: {
  items: { id: string; label: string }[];
  action: (state: DeleteEntitiesActionState, formData: FormData) => Promise<DeleteEntitiesActionState>;
  nounSingular: string;
  nounPlural: string;
  onDone: () => void;
  onPartialSuccess: () => void;
  onCancel: () => void;
}) {
  const [state, formAction, pending] = useActionState(action, initialState);

  useEffect(() => {
    if (!state.success) {
      return;
    }
    if (state.failures) {
      // Falha parcial: os itens que deram certo já foram removidos no banco
      // — a tabela precisa refletir isso, mas a barra permanece aberta
      // mostrando o motivo da falha nos itens restantes.
      onPartialSuccess();
      return;
    }
    onDone();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.success, state.failures]);

  return (
    <form
      action={formAction}
      className="space-y-3 rounded-md border border-destructive/40 bg-destructive/5 p-3 dark:border-destructive-foreground/25 dark:bg-destructive/20"
    >
      {items.map((item) => (
        <input key={item.id} type="hidden" name="ids" value={item.id} />
      ))}

      <p className="text-sm text-foreground">
        Confirma a exclusão de {items.length === 1 ? `1 ${nounSingular}` : `${items.length} ${nounPlural}`}?{" "}
        <span className="text-muted-foreground">Esta ação não pode ser desfeita.</span>
      </p>
      <ul className="list-inside list-disc text-xs text-muted-foreground">
        {items.map((item) => (
          <li key={item.id}>{item.label}</li>
        ))}
      </ul>

      {state.error && (
        <p className="text-xs text-destructive dark:text-destructive-foreground">{state.error}</p>
      )}

      {state.failures && state.failures.length > 0 && (
        <div className="space-y-1 rounded-md border border-destructive/30 bg-surface p-2 dark:border-destructive-foreground/25">
          <p className="text-xs font-medium text-destructive dark:text-destructive-foreground">
            Não foi possível excluir todos os itens:
          </p>
          {state.failures.map((failure) => {
            const item = items.find((i) => i.id === failure.id);
            return (
              <p key={failure.id} className="text-xs text-destructive dark:text-destructive-foreground">
                {item?.label ?? failure.id}: {failure.error}
              </p>
            );
          })}
        </div>
      )}

      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" size="sm" onClick={onCancel} disabled={pending}>
          Cancelar
        </Button>
        <Button type="submit" variant="destructive" size="sm" disabled={pending}>
          {pending ? "Excluindo…" : "Confirmar exclusão"}
        </Button>
      </div>
    </form>
  );
}
