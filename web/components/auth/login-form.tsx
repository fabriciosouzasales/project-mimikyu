"use client";

import Link from "next/link";
import { useActionState } from "react";
import { login, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  AuthFooterLink,
  AuthPanelHeading,
  AuthSubmitButton,
  authInputClassName,
  authLabelClassName,
} from "@/components/auth/auth-form-kit";

const initialState: AuthActionState = { error: null };

/**
 * Painel de Login — implementação real da direção "cartas reais" (protótipo
 * v4, aprovado 2026-08-15). Deliberadamente SEM chrome de card (sem borda,
 * sombra ou fundo próprio) — instrução #5 da rodada de polish final: o
 * painel deve estar "à altura do acabamento do hero" através da tipografia,
 * espaçamento e do CTA em si, não de decoração adicional (evita
 * glassmorphism, sombras exageradas, gradientes decorativos, "dourado em
 * tudo", glow, ou aparência de SaaS genérico) — o protótipo v4 não envolve
 * `.panel` em nenhum container visual próprio, só tipografia/inputs/CTA
 * direto sobre `--auth-form-surface`.
 *
 * Mesmo contrato de `useActionState(login)` e mesmos atributos de
 * acessibilidade/autofill (`autoComplete`, `required`, `aria-invalid` via
 * `invalid`) das rodadas anteriores — `app/(auth)/actions.ts` intocado.
 * `--auth-accent-ink` (não `--auth-accent`) nos links: correção de
 * contraste desta rodada, ver `auth-tokens.module.css`.
 *
 * Rodada de fechamento da Auth Experience V1 (2026-08-16, ver docs/log.md):
 * as peças reutilizáveis deste painel (heading, classes de label/input, CTA,
 * link de rodapé) foram extraídas para `auth-form-kit.tsx` — Cadastro,
 * Recuperar Senha e Atualizar Senha agora consomem exatamente as mesmas
 * peças, em vez de duplicar CSS/JSX. Este componente é a referência visual
 * original; a extração é mecânica — o markup/classes renderizados aqui não
 * mudaram em nenhum caractere.
 */
export function LoginForm() {
  const [state, formAction, pending] = useActionState(login, initialState);

  return (
    <div>
      <AuthPanelHeading title="Entrar" description="Acesse sua conta do MMKyu TCG Collector." />

      <form action={formAction} className="space-y-5" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}

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
          <div className="flex items-center justify-between">
            <Label htmlFor="password" className={authLabelClassName}>
              Senha
            </Label>
            <Link
              href="/recuperar-senha"
              className="text-[12.5px] text-[hsl(var(--auth-form-ink-muted))] transition-colors hover:text-[hsl(var(--auth-accent-ink))] hover:underline"
            >
              Esqueceu a senha?
            </Link>
          </div>
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            invalid={!!state.error}
            className={authInputClassName}
          />
        </div>

        <AuthSubmitButton pending={pending} pendingLabel="Entrando…" label="Entrar" />
      </form>

      <AuthFooterLink prompt="Não tem conta?" href="/cadastro" label="Criar conta" />
    </div>
  );
}
