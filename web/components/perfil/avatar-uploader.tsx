"use client";

import { useRef, useState } from "react";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

const MAX_AVATAR_BYTES = 2 * 1024 * 1024; // 2 MB — mesmo limite do bucket (ver Query 1040).
const EXTENSION_BY_MIME: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
};

type UploadState = "idle" | "uploading" | "success" | "error" | "session-expired";

export function AvatarUploader({
  userId,
  initialAvatarPath,
}: {
  userId: string;
  initialAvatarPath: string | null;
}) {
  const [avatarPath, setAvatarPath] = useState(initialAvatarPath);
  const [state, setState] = useState<UploadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const supabase = createClient();
  const avatarUrl = avatarPath
    ? supabase.storage.from("avatars").getPublicUrl(avatarPath).data.publicUrl
    : null;

  async function handleFileSelected(file: File) {
    setErrorMessage(null);

    // Sessão pode ter expirado entre o carregamento da página e a ação do
    // usuário — checagem explícita antes de qualquer chamada de Storage,
    // já que não existe guarda de rota global no projeto ainda.
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      setState("session-expired");
      return;
    }

    const extension = EXTENSION_BY_MIME[file.type];
    if (!extension) {
      setState("error");
      setErrorMessage("Formato não suportado. Envie uma imagem PNG, JPEG ou WEBP.");
      return;
    }
    if (file.size > MAX_AVATAR_BYTES) {
      setState("error");
      setErrorMessage("Imagem maior que 2 MB. Escolha um arquivo menor.");
      return;
    }

    setState("uploading");

    const previousPath = avatarPath;
    const newPath = `${userId}/${crypto.randomUUID()}.${extension}`;

    // 1) Envia o novo arquivo primeiro — nunca remove o avatar atual antes
    //    de garantir que o novo já está salvo (ver escopo do Incremento 1,
    //    ponto 6).
    const { error: uploadError } = await supabase.storage.from("avatars").upload(newPath, file, {
      contentType: file.type,
      upsert: false,
    });
    if (uploadError) {
      setState("error");
      setErrorMessage("Não foi possível enviar a imagem. Tente novamente.");
      return;
    }

    // 2) Só depois do upload confirmado, aponta o perfil para o novo caminho.
    const { error: updateError } = await supabase
      .from("user_profile")
      .update({ avatar_path: newPath })
      .eq("id", userId);

    if (updateError) {
      // Upload teve sucesso mas não conseguimos salvar o ponteiro — remove o
      // arquivo órfão e preserva o avatar anterior, que continua íntegro.
      await supabase.storage.from("avatars").remove([newPath]);
      setState("error");
      setErrorMessage("Não foi possível salvar o novo avatar. Tente novamente.");
      return;
    }

    setAvatarPath(newPath);
    setState("success");

    // 3) Só agora remove o arquivo anterior. Falha aqui é apenas um arquivo
    //    órfão no bucket — não afeta o avatar já atualizado com sucesso.
    if (previousPath) {
      await supabase.storage.from("avatars").remove([previousPath]);
    }
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-4">
        <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border border-border bg-surface-muted text-lg font-medium text-muted-foreground">
          {avatarUrl ? (
            // Avatar hospedado no Supabase Storage — sem config de
            // images.remotePatterns no projeto ainda, por isso <img> simples
            // em vez de next/image (ver decisão registrada para a Task 356).
            // eslint-disable-next-line @next/next/no-img-element
            <img src={avatarUrl} alt="Avatar" className="h-full w-full object-cover" />
          ) : (
            <span aria-hidden>?</span>
          )}
        </div>

        <div className="space-y-1">
          <input
            ref={inputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp"
            className="hidden"
            onChange={(event) => {
              const file = event.target.files?.[0];
              event.target.value = "";
              if (file) void handleFileSelected(file);
            }}
          />
          <Button
            type="button"
            variant="outline"
            size="sm"
            disabled={state === "uploading"}
            onClick={() => inputRef.current?.click()}
          >
            {state === "uploading" ? "Enviando…" : "Alterar avatar"}
          </Button>
          <p className="text-xs text-muted-foreground">PNG, JPEG ou WEBP, até 2 MB.</p>
        </div>
      </div>

      {state === "error" && errorMessage && <Alert variant="destructive">{errorMessage}</Alert>}
      {state === "session-expired" && (
        <Alert variant="destructive">
          Sua sessão expirou. Recarregue a página e faça login novamente antes de tentar de novo.
        </Alert>
      )}
      {state === "success" && <Alert variant="success">Avatar atualizado.</Alert>}
    </div>
  );
}
