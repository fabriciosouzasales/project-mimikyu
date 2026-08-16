"use client";

import { useActionState } from "react";
import { updatePassword, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { AuthPanelHeading, AuthSubmitButton, authInputClassName, authLabelClassName } from "@/components/auth/auth-form-kit";

const initialState: AuthActionState = { error: null };

/**
 * Painel de Atualizar Senha — migrado de
 * `app/(auth)/atualizar-senha/page.tsx` (fechamento da Auth Experience V1,
 * 2026-08-16, ver docs/log.md), mesma linguagem visual do Login. Lógica
 * (`updatePassword`, pending/erro; guarda de sessão de recovery já feita na
 * página, ver `app/(auth)/atualizar-senha/page.tsx`) preservada byte a
 * byte — `app/(auth)/actions.ts` intocado. Sem link de rodapé, como na
 * versão anterior (não há para onde voltar nesse ponto do fluxo).
 */
export function UpdatePasswordForm() {
  const [state, formAction, pending] = useActionState(updatePassword, initialState);

  return (
    <div>
      <AuthPanelHeading
        title="Crie uma nova senha."
        description="Escolha uma nova senha para voltar a acessar sua coleção com segurança."
      />

      <form action={formAction} className="space-y-5" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}

        <div className="space-y-1.5">
          <Label htmlFor="password" className={authLabelClassName}>
            Nova senha
          </Label>
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="new-password"
            minLength={6}
            required
            invalid={!!state.error}
            className={authInputClassName}
          />
          <p className="text-xs text-[hsl(var(--auth-form-ink-muted))]">Mínimo de 6 caracteres.</p>
        </div>

        <AuthSubmitButton pending={pending} pendingLabel="Salvando…" label="Salvar nova senha" />
      </form>
    </div>
  );
}
