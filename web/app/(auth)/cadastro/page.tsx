"use client";

import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { signup, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
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

const initialState: AuthActionState = { error: null };

type UsernameStatus = "idle" | "invalid" | "checking" | "available" | "unavailable" | "check-failed";

export default function SignupPage() {
  const [state, formAction, pending] = useActionState(signup, initialState);

  const [usernameRaw, setUsernameRaw] = useState("");
  const [usernameStatus, setUsernameStatus] = useState<UsernameStatus>("idle");
  const [displayName, setDisplayName] = useState("");

  const username = normalizeUsername(usernameRaw);

  // Verificação de disponibilidade é só uma antecipação de UX (debounce de
  // 400ms via username_available()) — não é a autoridade final. O banco
  // (UNIQUE constraint em user_profile.username) sempre revalida no cadastro
  // real, então uma condição de corrida aqui é esperada e inofensiva: o pior
  // caso é um erro de "nome já em uso" no submit, tratado normalmente.
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
      <Card>
        <CardHeader>
          <CardTitle>Confirme seu e-mail</CardTitle>
          <CardDescription>Falta pouco para começar.</CardDescription>
        </CardHeader>
        <CardContent>
          <Alert variant="success">
            Enviamos um link de confirmação para o e-mail informado. Abra sua caixa de entrada e
            clique no link para ativar sua conta.
          </Alert>
        </CardContent>
      </Card>
    );
  }

  const displayNameTrimmed = normalizeDisplayName(displayName);
  const displayNameHasContent = displayName.length > 0;
  const displayNameInvalid = displayNameHasContent && !isDisplayNameValid(displayName);

  return (
    <Card>
      <CardHeader>
        <CardTitle>Criar conta</CardTitle>
        <CardDescription>Junte-se à comunidade de colecionadores do Project Mimikyu.</CardDescription>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="space-y-4" noValidate>
          {state.error && <Alert variant="destructive">{state.error}</Alert>}

          <div className="space-y-2">
            <Label htmlFor="username">Nome de usuário</Label>
            <div className="relative">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">
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
                className="pl-7"
                value={usernameRaw}
                onChange={(event) => setUsernameRaw(event.target.value)}
                invalid={usernameStatus === "invalid" || usernameStatus === "unavailable"}
              />
            </div>
            <UsernameHint status={usernameStatus} />
          </div>

          <div className="space-y-2">
            <Label htmlFor="display_name">Nome de exibição</Label>
            <Input
              id="display_name"
              name="display_name"
              type="text"
              autoComplete="name"
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
                {displayNameTrimmed.length}/{DISPLAY_NAME_MAX_LENGTH} caracteres. Pode ser alterado depois.
              </p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="email">E-mail</Label>
            <Input id="email" name="email" type="email" autoComplete="email" required invalid={!!state.error} />
          </div>

          <div className="space-y-2">
            <Label htmlFor="password">Senha</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="new-password"
              minLength={6}
              required
              invalid={!!state.error}
            />
            <p className="text-xs text-muted-foreground">Mínimo de 6 caracteres.</p>
          </div>

          <Button type="submit" className="w-full" disabled={pending}>
            {pending ? "Criando conta…" : "Criar conta"}
          </Button>
        </form>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          Já tem conta?{" "}
          <Link href="/login" className="font-medium text-primary hover:underline">
            Entrar
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}

function UsernameHint({ status }: { status: UsernameStatus }) {
  switch (status) {
    case "invalid":
      return <p className="text-xs text-destructive">Use de 3 a 20 caracteres: letras minúsculas, números e _.</p>;
    case "checking":
      return <p className="text-xs text-muted-foreground">Verificando disponibilidade…</p>;
    case "available":
      return <p className="text-xs font-medium text-foreground">Disponível.</p>;
    case "unavailable":
      return <p className="text-xs text-destructive">Este nome de usuário já está em uso.</p>;
    case "check-failed":
      return <p className="text-xs text-muted-foreground">Não foi possível verificar agora. Você ainda pode tentar cadastrar.</p>;
    default:
      return <p className="text-xs text-muted-foreground">3 a 20 caracteres: letras minúsculas, números e _. Não poderá ser alterado depois.</p>;
  }
}
