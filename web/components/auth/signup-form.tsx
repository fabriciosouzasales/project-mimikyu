"use client";

import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { signup, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import {
  DISPLAY_NAME_MAX_LENGTH,
  isDisplayNameValid,
  isUsernameFormatValid,
  normalizeDisplayName,
  normalizeUsername,
} from "@/lib/username";
import {
  AuthFooterLink,
  AuthPanelHeading,
  AuthSubmitButton,
  authInputClassName,
  authLabelClassName,
} from "@/components/auth/auth-form-kit";

const initialState: AuthActionState = { error: null };

type UsernameStatus = "idle" | "invalid" | "checking" | "available" | "unavailable" | "check-failed";

/**
 * Painel de Cadastro — migrado de `app/(auth)/cadastro/page.tsx` para cá
 * (fechamento da Auth Experience V1, 2026-08-16, ver docs/log.md), agora
 * usando a mesma linguagem visual do Login (`auth-form-kit.tsx`, sem chrome
 * de Card) em vez do Card administrativo antigo. Toda a lógica funcional é
 * idêntica byte a byte à versão anterior: debounce de 400ms para
 * `username_available` (UX-only, o UNIQUE constraint em
 * `user_profile.username` sempre revalida no submit real), contador de
 * caracteres do nome de exibição, validações de formato, estado de
 * sucesso pós-cadastro. `app/(auth)/actions.ts` intocado.
 *
 * Estado de sucesso também usa `AuthPanelHeading` (não mais `Card`) —
 * mantém a copy original ("Confirme seu e-mail" / "Falta pouco para
 * começar.") já aprovada, só a casca visual mudou.
 */
export function SignupForm() {
  const [state, formAction, pending] = useActionState(signup, initialState);

  const [usernameRaw, setUsernameRaw] = useState("");
  const [usernameStatus, setUsernameStatus] = useState<UsernameStatus>("idle");
  const [displayName, setDisplayName] = useState("");

  const username = normalizeUsername(usernameRaw);

  useEffect(() => {
    if (!usernameRaw) {
      setUsernameStatus("idle");
      return;
    }
    if (!isUsernameFormatValid(username)) {
      setUsernameStatus("invalid");
      return;
    }

    setUsernameStatus("checking");
    const supabase = createClient();
    const timeout = setTimeout(async () => {
      const { data, error } = await supabase.rpc("username_available", { p_username: username });
      if (error) {
        setUsernameStatus("check-failed");
        return;
      }
      setUsernameStatus(data ? "available" : "unavailable");
    }, 400);

    return () => clearTimeout(timeout);
  }, [username, usernameRaw]);

  if (state.success) {
    return (
      <div>
        <AuthPanelHeading title="Confirme seu e-mail" description="Falta pouco para começar." />
        <Alert variant="success">
          Enviamos um link de confirmação para o e-mail informado. Abra sua caixa de entrada e clique no link
          para ativar sua conta.
        </Alert>
      </div>
    );
  }

  const displayNameTrimmed = normalizeDisplayName(displayName);
  const displayNameHasContent = displayName.length > 0;
  const displayNameInvalid = displayNameHasContent && !isDisplayNameValid(displayName);

  return (
    <div>
      <AuthPanelHeading title="Criar conta" description="Comece agora a organizar sua coleção do seu jeito." />

      <form action={formAction} className="space-y-5" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}

        <div className="space-y-1.5">
          <Label htmlFor="username" className={authLabelClassName}>
            Nome de usuário
          </Label>
          <div className="relative">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-[hsl(var(--auth-form-ink-muted))]">
              @
            </span>
            <Input
              id="username"
              name="username"
              type="text"
              autoComplete="off"
              autoCapitalize="off"
              spellCheck={false}
              required
              className={`${authInputClassName} pl-7`}
              value={usernameRaw}
              onChange={(event) => setUsernameRaw(event.target.value)}
              invalid={usernameStatus === "invalid" || usernameStatus === "unavailable"}
            />
          </div>
          <UsernameHint status={usernameStatus} />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="display_name" className={authLabelClassName}>
            Nome de exibição
          </Label>
          <Input
            id="display_name"
            name="display_name"
            type="text"
            autoComplete="name"
            maxLength={DISPLAY_NAME_MAX_LENGTH}
            required
            className={authInputClassName}
            value={displayName}
            onChange={(event) => setDisplayName(event.target.value)}
            invalid={displayNameInvalid}
          />
          {displayNameInvalid ? (
            <p className="text-xs text-destructive">Informe de 1 a 60 caracteres.</p>
          ) : (
            <p className="text-xs text-[hsl(var(--auth-form-ink-muted))]">
              {displayNameTrimmed.length}/{DISPLAY_NAME_MAX_LENGTH} caracteres. Pode ser alterado depois.
            </p>
          )}
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="email" className={authLabelClassName}>
            E-mail
          </Label>
          <Input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            invalid={!!state.error}
            className={authInputClassName}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="password" className={authLabelClassName}>
            Senha
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

        <AuthSubmitButton pending={pending} pendingLabel="Criando conta…" label="Criar conta" />
      </form>

      <AuthFooterLink prompt="Já tem conta?" href="/login" label="Entrar" />
    </div>
  );
}

function UsernameHint({ status }: { status: UsernameStatus }) {
  switch (status) {
    case "invalid":
      return <p className="text-xs text-destructive">Use de 3 a 20 caracteres: letras minúsculas, números e _.</p>;
    case "checking":
      return <p className="text-xs text-[hsl(var(--auth-form-ink-muted))]">Verificando disponibilidade…</p>;
    case "available":
      return <p className="text-xs font-medium text-[hsl(var(--auth-form-ink))]">Disponível.</p>;
    case "unavailable":
      return <p className="text-xs text-destructive">Este nome de usuário já está em uso.</p>;
    case "check-failed":
      return (
        <p className="text-xs text-[hsl(var(--auth-form-ink-muted))]">
          Não foi possível verificar agora. Você ainda pode tentar cadastrar.
        </p>
      );
    default:
      return (
        <p className="text-xs text-[hsl(var(--auth-form-ink-muted))]">
          3 a 20 caracteres: letras minúsculas, números e _. Não poderá ser alterado depois.
        </p>
      );
  }
}
