"use client";

import { useActionState, useState } from "react";
import { updateDisplayName, type ProfileActionState } from "@/app/perfil/actions";
import { AvatarUploader } from "@/components/perfil/avatar-uploader";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { SettingsRow } from "@/components/ui/settings-row";
import { SettingsSection } from "@/components/ui/settings-section";
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
    <div className="space-y-0">
      <SettingsSection title="Foto do perfil" description="Aparece no seu perfil e no cabeçalho do app.">
        <AvatarUploader userId={userId} initialAvatarPath={initialAvatarPath} />
      </SettingsSection>

      <SettingsSection title="Identidade" description="Informações que identificam sua conta.">
        <SettingsRow label="Nome de usuário" description="Não pode ser alterado depois de criado.">
          <div className="flex items-center gap-2">
            <div className="flex-1 rounded-md border border-input bg-surface-muted px-3 py-1.5 text-sm text-muted-foreground">
              @{username}
            </div>
            <Badge variant="warning">Fixo</Badge>
          </div>
        </SettingsRow>

        <SettingsRow label="Nome de exibição" description="Como seu nome aparece para outras pessoas.">
          <form action={formAction} className="space-y-2" noValidate>
            {state.error && <Alert variant="destructive">{state.error}</Alert>}
            {state.success && <Alert variant="success">Nome de exibição atualizado.</Alert>}

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

            <div className="flex items-center justify-between">
              {displayNameInvalid ? (
                <p className="text-xs text-destructive">Informe de 1 a 60 caracteres.</p>
              ) : (
                <p className="text-xs text-muted-foreground">
                  {normalizeDisplayName(displayName).length}/{DISPLAY_NAME_MAX_LENGTH} caracteres
                </p>
              )}

              <Button type="submit" size="sm" disabled={pending || displayNameInvalid || displayName.length === 0}>
                {pending ? "Salvando…" : "Salvar"}
              </Button>
            </div>
          </form>
        </SettingsRow>
      </SettingsSection>
    </div>
  );
}
