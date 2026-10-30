"use client";

import { useEffect, useRef, useState } from "react";
import { Check, Share2 } from "lucide-react";
import { publicBinderHref } from "@/lib/colecoes/sharing";
import styles from "./public-binder.module.css";

/**
 * Compartilhar o link da vitrine pública (V1.0 PUBLIC SHOWCASE &
 * ACQUISITION-01). Só o link canônico `/fichario/[id]` — nenhum dado novo,
 * nenhuma permissão nova (a página já é pública por link).
 *
 * Folha de compartilhamento nativa do dispositivo (Web Share API) quando
 * existir; senão, copia o link (mesmo `navigator.clipboard` do painel
 * "Compartilhar" do titular). Cancelar a folha nativa não é erro. O resultado
 * é anunciado (`aria-live`) e some sozinho.
 */
export function PublicBinderShare({ collectionId, title }: { collectionId: string; title: string }) {
  const [status, setStatus] = useState<"idle" | "copied" | "error">("idle");
  const timer = useRef<number | null>(null);

  useEffect(() => () => {
    if (timer.current) window.clearTimeout(timer.current);
  }, []);

  const flash = (next: "copied" | "error") => {
    setStatus(next);
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setStatus("idle"), 2400);
  };

  const share = async () => {
    const url = `${window.location.origin}${publicBinderHref(collectionId)}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: `${title} · MMKYU Collector`, url });
        return;
      } catch (error) {
        // Cancelado pelo usuário: nada a fazer. Outras falhas caem para copiar.
        if (error instanceof DOMException && error.name === "AbortError") return;
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      flash("copied");
    } catch {
      flash("error");
    }
  };

  return (
    <span className={styles.shareWrap}>
      <button
        type="button"
        className={styles.shareButton}
        onClick={() => void share()}
        aria-label={status === "copied" ? "Link copiado" : "Compartilhar este fichário"}
      >
        {status === "copied" ? <Check className="h-4 w-4" aria-hidden="true" /> : <Share2 className="h-4 w-4" aria-hidden="true" />}
        <span className={styles.shareLabel}>{status === "copied" ? "Link copiado" : "Compartilhar"}</span>
      </button>
      <span className="sr-only" role="status" aria-live="polite">
        {status === "copied" ? "Link do fichário copiado." : status === "error" ? "Não foi possível copiar o link. Copie o endereço da página." : ""}
      </span>
    </span>
  );
}
