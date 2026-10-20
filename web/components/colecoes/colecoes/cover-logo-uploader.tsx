"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { setCollectionCoverLogo } from "@/app/colecoes/colecoes/actions";
import { type CollectionFailure, collectionFailureMessage } from "@/lib/colecoes/colecoes";
import { COVER_BUCKET, buildCoverPath, checkCoverFile } from "@/lib/colecoes/free-collection";
import { createClient } from "@/lib/supabase/client";

export type CoverLogoState =
  | { status: "idle" }
  | { status: "busy"; label: string }
  | { status: "error"; message: string }
  | { status: "done"; message: string };

/**
 * Envio e remoção da imagem da capa do fichário (FREE-COLLECTION-COVER-LOGO-01).
 * UX-06: a ação mora em Ajustes → Identidade (`collection-identity-settings.tsx`);
 * a capa na página deixou de ser clicável.
 *
 * Ordem segura, mesma do avatar do perfil:
 *   1. valida tipo e tamanho (PNG, JPEG ou WEBP até 1 MB — o bucket reconfere);
 *   2. envia o arquivo novo para `<dono>/<coleção>/<uuid>` no bucket privado;
 *   3. aponta a coleção para ele (5178 confere dono, pasta e arquivo);
 *      se falhar, apaga o arquivo recém-enviado e a capa atual continua;
 *   4. só então apaga o arquivo anterior (falha aqui = arquivo órfão, nunca capa quebrada).
 */
export function useCoverLogo(collectionId: string, userId: string) {
  const router = useRouter();
  const [state, setState] = useState<CoverLogoState>({ status: "idle" });

  // A confirmação some sozinha; o erro fica até a próxima ação.
  useEffect(() => {
    if (state.status !== "done") return;
    const timer = window.setTimeout(() => setState({ status: "idle" }), 4000);
    return () => window.clearTimeout(timer);
  }, [state]);

  const upload = useCallback(
    async (file: File) => {
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
    },
    [collectionId, router, userId],
  );

  const clear = useCallback(async () => {
    setState({ status: "busy", label: "Removendo imagem…" });
    const saved = await setCollectionCoverLogo({ collectionId, path: null }).catch(() => ({ ok: false as const, reason: "unavailable" as const }));
    if (!saved.ok) {
      setState({ status: "error", message: coverFailureMessage(saved.reason) });
      return;
    }
    if (saved.previousPath) await createClient().storage.from(COVER_BUCKET).remove([saved.previousPath]);
    setState({ status: "done", message: "A capa voltou a mostrar o nome da coleção." });
    router.refresh();
  }, [collectionId, router]);

  return { state, upload, clear };
}

/** Erro da capa em linguagem da capa (o texto genérico fala de "receber cartas"). */
function coverFailureMessage(reason: CollectionFailure): string {
  if (reason === "not_found") return "Não foi possível alterar a capa desta coleção agora. Nada foi alterado.";
  return collectionFailureMessage(reason);
}
