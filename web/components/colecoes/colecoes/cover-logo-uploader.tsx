"use client";

import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useRef, useState } from "react";
import { Loader2, Pencil, Trash2 } from "lucide-react";
import { setCollectionCoverLogo } from "@/app/colecoes/colecoes/actions";
import { type CollectionFailure, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import { COVER_BUCKET, buildCoverPath, checkCoverFile } from "@/lib/colecoes/free-collection";
import { createClient } from "@/lib/supabase/client";
import styles from "./colecoes.module.css";

type State = { status: "idle" } | { status: "busy"; label: string } | { status: "error"; message: string } | { status: "done"; message: string };

/**
 * Capa da Coleção livre como gatilho da imagem da placa
 * (FREE-COLLECTION-COVER-LOGO-01; refinamento de Fabrício, 2026-10-18: a
 * troca acontece ao clicar na própria capa do fichário — sem botões soltos).
 *
 * O fichário (`children`, Server Component) continua clicável para abrir o
 * seletor de arquivo. No canto superior, dois botões pequenos e redondos
 * (ajuste de Fabrício, 2026-10-18 — sem rótulo sobre a capa): lápis
 * (trocar/escolher imagem) e, com imagem, lixeira (remover). Aparecem no
 * hover/foco; em telas de toque ficam sempre visíveis.
 *
 * Ordem segura, mesma do avatar do perfil:
 *   1. valida tipo e tamanho (PNG, JPEG ou WEBP até 1 MB — o bucket reconfere);
 *   2. envia o arquivo novo para `<dono>/<coleção>/<uuid>` no bucket privado;
 *   3. aponta a coleção para ele (5178 confere dono, pasta e arquivo);
 *      se falhar, apaga o arquivo recém-enviado e a capa atual continua;
 *   4. só então apaga o arquivo anterior (falha aqui = arquivo órfão, nunca capa quebrada).
 */
export function CoverLogoTrigger({
  collectionId,
  userId,
  hasLogo,
  children,
}: {
  collectionId: string;
  userId: string;
  hasLogo: boolean;
  children: ReactNode;
}) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [state, setState] = useState<State>({ status: "idle" });
  const busy = state.status === "busy";

  // A confirmação some sozinha; o erro fica até a próxima ação.
  useEffect(() => {
    if (state.status !== "done") return;
    const timer = window.setTimeout(() => setState({ status: "idle" }), 4000);
    return () => window.clearTimeout(timer);
  }, [state]);

  const upload = async (file: File) => {
    const check = checkCoverFile(file);
    if (check !== "ok") {
      setState({
        status: "error",
        message: check === "size" ? "A imagem passa de 1 MB. Escolha um arquivo menor." : "Envie uma imagem PNG, JPEG ou WEBP.",
      });
      return;
    }
    const path = buildCoverPath(userId, collectionId, file.type, crypto.randomUUID());
    if (!path) {
      setState({ status: "error", message: "Envie uma imagem PNG, JPEG ou WEBP." });
      return;
    }
    setState({ status: "busy", label: "Enviando imagem…" });
    const supabase = createClient();
    const sent = await supabase.storage.from(COVER_BUCKET).upload(path, file, { contentType: file.type, upsert: false });
    if (sent.error) {
      setState({ status: "error", message: "Não foi possível enviar a imagem. Nada mudou — tente de novo." });
      return;
    }
    const saved = await setCollectionCoverLogo({ collectionId, path }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (!saved.ok) {
      await supabase.storage.from(COVER_BUCKET).remove([path]);
      setState({ status: "error", message: coverFailureMessage(saved.reason) });
      return;
    }
    if (saved.previousPath) await supabase.storage.from(COVER_BUCKET).remove([saved.previousPath]);
    setState({ status: "done", message: "Capa atualizada." });
    router.refresh();
  };

  const clear = async () => {
    setState({ status: "busy", label: "Removendo imagem…" });
    const saved = await setCollectionCoverLogo({ collectionId, path: null }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (!saved.ok) {
      setState({ status: "error", message: coverFailureMessage(saved.reason) });
      return;
    }
    if (saved.previousPath) await createClient().storage.from(COVER_BUCKET).remove([saved.previousPath]);
    setState({ status: "done", message: "A capa voltou a mostrar o nome da coleção." });
    router.refresh();
  };

  return (
    <div className={styles.coverTrigger} data-busy={busy || undefined}>
      <button
        type="button"
        className={styles.coverTriggerButton}
        onClick={() => inputRef.current?.click()}
        disabled={busy}
        tabIndex={-1}
        aria-hidden="true"
      >
        {children}
      </button>
      <div className={styles.coverTriggerActions}>
        <button
          type="button"
          className={styles.coverTriggerAction}
          onClick={() => inputRef.current?.click()}
          disabled={busy}
          aria-label={hasLogo ? "Trocar a imagem da capa" : "Escolher uma imagem para a capa"}
          aria-describedby={state.status === "error" ? `${collectionId}-capa-status` : undefined}
          title={hasLogo ? "Trocar imagem" : "Escolher imagem"}
        >
          {busy ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin motion-reduce:animate-none" aria-hidden="true" />
          ) : (
            <Pencil className="h-3.5 w-3.5" aria-hidden="true" />
          )}
        </button>
        {hasLogo && !busy ? (
          <button
            type="button"
            className={`${styles.coverTriggerAction} ${styles.coverTriggerDanger}`}
            onClick={() => void clear()}
            aria-label="Remover a imagem da capa"
            title="Remover imagem"
          >
            <Trash2 className="h-3.5 w-3.5" aria-hidden="true" />
          </button>
        ) : null}
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        className="sr-only"
        tabIndex={-1}
        aria-hidden="true"
        onChange={(event) => {
          const file = event.target.files?.[0];
          event.target.value = "";
          if (file) void upload(file);
        }}
      />
      <p
        id={`${collectionId}-capa-status`}
        className={styles.coverTriggerStatus}
        data-tone={state.status === "error" ? "error" : undefined}
        role={state.status === "error" ? "alert" : "status"}
        aria-live="polite"
      >
        {state.status === "error" || state.status === "done" ? state.message : state.status === "busy" ? state.label : null}
      </p>
    </div>
  );
}

/** Erro da capa em linguagem da capa (o texto genérico fala de "receber cartas"). */
function coverFailureMessage(reason: CollectionFailure): string {
  if (reason === "not_found") return "Não foi possível alterar a capa desta coleção agora. Nada foi alterado.";
  return collectionFailureMessage(reason);
}
