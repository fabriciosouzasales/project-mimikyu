"use client";

import { useRouter } from "next/navigation";
import { useRef, useState, useTransition } from "react";
import { Loader2, Trash2 } from "lucide-react";
import { removeMyCopy } from "@/app/colecoes/acervo/actions";
import { Button } from "@/components/ui/button";
import { failureMessage } from "@/lib/colecoes/acervo-add";
import styles from "./acervo.module.css";

/**
 * Lixeira de um exemplar no detalhe da carta (INVENTORY-REMOVE-COPY-01).
 *
 * Correção de cadastro feito por engano: pede confirmação na própria linha
 * (sem modal sobre o painel), avisa que o registro é apagado e só aceita
 * exemplar fora de coleção — a regra é do banco (5165); aqui o botão só fica
 * indisponível com a explicação. Um envio por vez; repetir é seguro (a
 * função é idempotente). Ao remover o último exemplar do grupo, o painel
 * fecha, porque a carta deixa de estar no acervo.
 */
export function CopyRemoveButton({
  physicalCardId,
  copyNumber,
  inCollection,
  isLastCopy,
  closeHref,
  blocked = false,
}: {
  physicalCardId: string;
  copyNumber: number;
  inCollection: boolean;
  isLastCopy: boolean;
  closeHref: string;
  /** V1-16 FRONTEND-02: outra alteração dos exemplares em andamento — a lixeira espera (padrão: livre). */
  blocked?: boolean;
}) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inFlight = useRef(false);
  const [, startNavigation] = useTransition();

  if (inCollection) {
    return (
      <span className={styles.copyRemoveDisabled} title="Retire da coleção antes de remover">
        <Trash2 className="h-4 w-4" aria-hidden="true" />
        <span className="sr-only">Exemplar {copyNumber} está em uma coleção e não pode ser removido aqui</span>
      </span>
    );
  }

  async function remove() {
    if (inFlight.current) return;
    inFlight.current = true;
    setPending(true);
    setError(null);
    try {
      const response = await removeMyCopy(physicalCardId);
      if (!response.ok) {
        setError(failureMessage(response.reason));
        return;
      }
      // INCIDENT-01 E1: removeMyCopy chama `revalidatePath` — a resposta da ação já traz galeria,
      // números e detalhe atualizados; `router.refresh()` aqui era uma 2ª renderização inteira.
      // Último exemplar: a navegação de fechamento continua (muda a URL; não é refresh redundante).
      if (isLastCopy) startNavigation(() => router.replace(closeHref, { scroll: false }));
    } catch {
      setError(failureMessage("unavailable"));
    } finally {
      inFlight.current = false;
      setPending(false);
    }
  }

  if (!confirming) {
    return (
      <button
        type="button"
        className={styles.copyRemove}
        aria-disabled={blocked || undefined}
        onClick={() => {
          if (blocked) return;
          setConfirming(true);
        }}
        aria-label={`Remover exemplar ${copyNumber}`}
        title="Remover exemplar"
      >
        <Trash2 className="h-4 w-4" aria-hidden="true" />
      </button>
    );
  }

  return (
    <div className={styles.copyConfirm} role="group" aria-label={`Confirmar remoção do exemplar ${copyNumber}`}>
      <p className={styles.copyConfirmText}>
        Remover o Exemplar {copyNumber}? O registro é apagado — use só para corrigir um cadastro feito por engano.
      </p>
      <div aria-live="polite">{error ? <p className={styles.copyConfirmError}>{error}</p> : null}</div>
      <div className={styles.copyConfirmActions}>
        <Button variant="outline" size="sm" onClick={() => setConfirming(false)} disabled={pending} autoFocus>
          Cancelar
        </Button>
        <Button variant="destructive" size="sm" className={styles.copyConfirmRemove} onClick={() => void remove()} disabled={pending || blocked}>
          {pending ? <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" /> : null}
          {pending ? "Removendo…" : "Remover"}
        </Button>
      </div>
    </div>
  );
}
