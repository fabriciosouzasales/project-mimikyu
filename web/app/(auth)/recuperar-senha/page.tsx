"use client";

import Link from "next/link";
import { useActionState } from "react";
import { requestPasswordReset, type AuthActionState } from "@/app/(auth)/actions";
import { LegacyAuthShell } from "@/components/auth/legacy-auth-shell";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const initialState: AuthActionState = { error: null };

export default function ResetPasswordPage() {
  const [state, formAction, pending] = useActionState(requestPasswordReset, initialState);

  return (
    <LegacyAuthShell>
      <Card>
        <CardHeader>
          <CardTitle>Recuperar senha</CardTitle>
          <CardDescription>Enviaremos um link para redefinir sua senha.</CardDescription>
        </CardHeader>
        <CardContent>
          {state.success ? (
            <Alert variant="success">
              Se existir uma conta com este e-mail, um link de redefinição foi enviado.
            </Alert>
          ) : (
            <form action={formAction} className="space-y-4" noValidate>
              {state.error && <Alert variant="destructive">{state.error}</Alert>}

              <div className="space-y-2">
                <Label htmlFor="email">E-mail</Label>
                <Input id="email" name="email" type="email" autoComplete="email" required invalid={!!state.error} />
              </div>

              <Button type="submit" className="w-full" disabled={pending}>
                {pending ? "Enviando…" : "Enviar link"}
              </Button>
            </form>
          )}

          <p className="mt-6 text-center text-sm text-muted-foreground">
            <Link href="/login" className="font-medium text-primary hover:underline">
              Voltar para o login
            </Link>
          </p>
        </CardContent>
      </Card>
    </LegacyAuthShell>
  );
}
