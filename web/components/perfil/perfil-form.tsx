"use client";

import { useActionState, useState } from "react";
import { updateDisplayName, type ProfileActionState } from "@/app/perfil/actions";
import { AvatarUploader } from "@/components/perfil/avatar-uploader";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { DISPLAY_NAME_MAX_LENGTH, isDisplayNameValid, normalizeDisplayName } from "@/lib/username";

const initialState: ProfileActionState = { error: null };

export function PerfilForm({
  userId,
  username,
  initialDisplayName,
  initialAvatarPath,
}: {
  userId: string;
  username: string;
  initialDisplayName: string;
  initialAvatarPath: string | null;
}) {
  const [state, formAction, pending] = useActionState(updateDisplayName, initialState);
  const [displayName, setDisplayName] = useState(initialDisplayName);

  const displayNameInvalid = displayName.length > 0 && !isDisplayNameValid(displayName);

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <Label>Avatar</Label>
        <AvatarUploader userId={userId} initialAvatarPath={initialAvatarPath} />
      </div>

      <div className="space-y-2">
        <Label>Nome de usuário</Label>
        <p className="text-sm text-foreground">@{username}</p>
        <p className="text-xs text-muted-foreground">
          Não pode ser alterado. Se precisar de uma correção, entre em contato com o suporte.
        </p>
      </div>

      <form action={formAction} className="space-y-2" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}
        {state.success && <Alert variant="success">Nome de exibição atualizado.</Alert>}

        <Label htmlFor="display_name">Nome de exibição</Label>
        <Input
          id="display_name"
          name="display_name"
          type="text"
          maxLength={DISPLAY_NAME_MAX_LENGTH}
          required
          value={displayName}
          onChange={(event) => setDisplayName(event.target.value)}
          invalid={displayNameInvalid}
        />
        {displayNameInvalid ? (
          <p className="text-xs text-destructive">Informe de 1 a 60 caracteres.</p>
        ) : (
          <p className="text-xs text-muted-foreground">
            {normalizeDisplayName(displayName).length}/{DISPLAY_NAME_MAX_LENGTH} caracteres.
          </p>
        )}

        <Button type="submit" disabled={pending || displayNameInvalid || displayName.length === 0}>
          {pending ? "Salvando…" : "Salvar"}
        </Button>
      </form>
    </div>
  );
}
