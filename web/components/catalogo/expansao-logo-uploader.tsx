"use client";

import { Trash2 } from "lucide-react";
import { useRef, useState } from "react";
import { setExpansionLogo } from "@/app/catalogo/expansoes/actions";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/client";

const BUCKET = "expansion-logo";
const MAX_LOGO_BYTES = 5 * 1024 * 1024; // 5 MB — mais generoso que o avatar (2 MB, Query 1040), arte de Expansão tende a ter resolução maior.
const EXTENSION_BY_MIME: Record<string, string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
};

type UploadState = "idle" | "uploading" | "success" | "error" | "session-expired";

/**
 * Upload da logo de uma Expansão — adaptado de `AvatarUploader`
 * (`components/perfil/avatar-uploader.tsx`), com duas diferenças
 * estruturais impostas pelo bucket `expansion-logo` ser privado e
 * admin-only (Queries 2045-2047, ADR-022, mesmo padrão de
 * `card_set.logo_storage_path`):
 *
 * 1. Leitura via `createSignedUrl` (URL expira, gerada por requisição) em
 *    vez de `getPublicUrl` — mesma decisão já tomada para a logo de Card
 *    Set e para o card da galeria de Expansões (`ExpansaoGalleryCard`).
 * 2. O ponteiro (`expansion.logo_storage_path`) não é gravado por
 *    `.update()` direto do cliente — não existe política de RLS de UPDATE
 *    em `expansion` para isso. A gravação passa pela Server Action
 *    `setExpansionLogo()`, que chama `admin_set_expansion_logo()`
 *    (`SECURITY DEFINER`). O arquivo em si continua subindo direto do
 *    cliente para o Storage (sujeito às políticas de `storage.objects`,
 *    Query 2047) — só o ponteiro no banco passa pelo servidor.
 */
export function ExpansaoLogoUploader({
  expansionId,
  initialLogoPath,
  initialLogoUrl,
  onChanged,
}: {
  expansionId: string;
  initialLogoPath: string | null;
  initialLogoUrl: string | null;
  /** Chamado após upload ou remoção bem-sucedidos, para o chamador atualizar a lista por trás do Dialog (`router.refresh()`). */
  onChanged: () => void;
}) {
  const [logoPath, setLogoPath] = useState(initialLogoPath);
  const [logoUrl, setLogoUrl] = useState(initialLogoUrl);
  const [state, setState] = useState<UploadState>("idle");
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const supabase = createClient();

  async function handleFileSelected(file: File) {
    setErrorMessage(null);

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
    if (file.size > MAX_LOGO_BYTES) {
      setState("error");
      setErrorMessage("Imagem maior que 5 MB. Escolha um arquivo menor.");
      return;
    }

    setState("uploading");

    const previousPath = logoPath;
    const newPath = `${expansionId}/${crypto.randomUUID()}.${extension}`;

    // 1) Envia o novo arquivo primeiro — nunca remove a logo atual antes de
    //    garantir que a nova já está salva (mesma ordem do AvatarUploader).
    const { error: uploadError } = await supabase.storage.from(BUCKET).upload(newPath, file, {
      contentType: file.type,
      upsert: false,
    });
    if (uploadError) {
      setState("error");
      setErrorMessage("Não foi possível enviar a imagem. Tente novamente.");
      return;
    }

    // 2) Só depois do upload confirmado, grava o ponteiro via Server Action
    //    (admin_set_expansion_logo() — não é um .update() direto, ver nota
    //    da função acima).
    const { error: pointerError } = await setExpansionLogo(expansionId, newPath);
    if (pointerError) {
      // Upload teve sucesso mas não conseguimos salvar o ponteiro — remove
      // o arquivo órfão e preserva a logo anterior, que continua íntegra.
      await supabase.storage.from(BUCKET).remove([newPath]);
      setState("error");
      setErrorMessage(pointerError);
      return;
    }

    const { data: signed } = await supabase.storage.from(BUCKET).createSignedUrl(newPath, 60 * 60);
    setLogoPath(newPath);
    setLogoUrl(signed?.signedUrl ?? null);
    setState("success");
    onChanged();

    // 3) Só agora remove a logo anterior. Falha aqui é apenas um arquivo
    //    órfão no bucket — não afeta a logo já atualizada com sucesso.
    if (previousPath) {
      await supabase.storage.from(BUCKET).remove([previousPath]);
    }
  }

  async function handleRemove() {
    if (!logoPath) return;
    setErrorMessage(null);
    setState("uploading");

    const pathToRemove = logoPath;
    const { error: pointerError } = await setExpansionLogo(expansionId, null);
    if (pointerError) {
      setState("error");
      setErrorMessage(pointerError);
      return;
    }

    setLogoPath(null);
    setLogoUrl(null);
    setState("success");
    onChanged();
    await supabase.storage.from(BUCKET).remove([pathToRemove]);
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3">
        <div className="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-md border border-border bg-surface-muted">
          {logoUrl ? (
            // Mesmo motivo do AvatarUploader/CardSetGalleryCard: URL assinada
            // expira e é gerada por requisição, next/image exigiria domínio
            // remoto para algo nem estável.
            // eslint-disable-next-line @next/next/no-img-element
            <img src={logoUrl} alt="" className="h-full w-full object-contain p-1.5" />
          ) : (
            <span className="text-[10px] text-muted-foreground">Sem logo</span>
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
          <div className="flex gap-2">
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={state === "uploading"}
              onClick={() => inputRef.current?.click()}
            >
              {state === "uploading" ? "Enviando…" : logoUrl ? "Trocar logo" : "Enviar logo"}
            </Button>
            {logoUrl && (
              <Button
                type="button"
                variant="ghost"
                size="icon-sm"
                aria-label="Remover logo"
                className="text-destructive hover:bg-destructive/10 hover:text-destructive dark:text-destructive-foreground dark:hover:text-destructive-foreground"
                disabled={state === "uploading"}
                onClick={() => void handleRemove()}
              >
                <Trash2 className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
          <p className="text-[9px] text-muted-foreground">PNG, JPEG ou WEBP, até 5 MB.</p>
        </div>
      </div>

      {state === "error" && errorMessage && <Alert variant="destructive">{errorMessage}</Alert>}
      {state === "session-expired" && (
        <Alert variant="destructive">
          Sua sessão expirou. Recarregue a página e faça login novamente antes de tentar de novo.
        </Alert>
      )}
      {state === "success" && <Alert variant="success">Logo atualizada.</Alert>}
    </div>
  );
}
