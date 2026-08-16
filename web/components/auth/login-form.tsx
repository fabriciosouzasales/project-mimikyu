"use client";

import Link from "next/link";
import { useActionState } from "react";
import { login, type AuthActionState } from "@/app/(auth)/actions";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import panelStyles from "@/components/auth/auth-panel.module.css";

const initialState: AuthActionState = { error: null };

const labelClassName = "text-[12.5px] font-medium tracking-[0.01em] text-[hsl(var(--auth-form-ink))]";
const inputClassName =
  "h-11 rounded-[var(--auth-radius-control)] border-[hsl(var(--auth-form-line))] bg-[hsl(var(--auth-form-surface))] " +
  "text-[hsl(var(--auth-form-ink))] shadow-[inset_0_1px_1px_hsl(var(--auth-form-ink)/0.02)] " +
  "placeholder:text-[hsl(var(--auth-form-ink-muted))] transition-colors " +
  "focus-visible:border-[hsl(var(--auth-accent))] focus-visible:ring-[3px] focus-visible:ring-[hsl(var(--auth-accent)/0.15)] focus-visible:ring-offset-0";

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
 */
export function LoginForm() {
  const [state, formAction, pending] = useActionState(login, initialState);

  return (
    <div>
      <div className="mb-7 space-y-1.5">
        <h2 className="text-[22px] font-semibold tracking-[-0.01em] text-[hsl(var(--auth-form-ink))]">Entrar</h2>
        <p className="text-[13px] leading-relaxed text-[hsl(var(--auth-form-ink-muted))]">
          Acesse sua conta do MMKyu TCG Collector.
        </p>
      </div>

      <form action={formAction} className="space-y-5" noValidate>
        {state.error && <Alert variant="destructive">{state.error}</Alert>}

        <div className="space-y-1.5">
          <Label htmlFor="email" className={labelClassName}>
            E-mail
          </Label>
          <Input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            invalid={!!state.error}
            className={inputClassName}
          />
        </div>

        <div className="space-y-1.5">
          <div className="flex items-center justify-between">
            <Label htmlFor="password" className={labelClassName}>
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
            className={inputClassName}
          />
        </div>

        <Button
          type="submit"
          disabled={pending}
          className={`${panelStyles.cta} h-[46px] w-full rounded-[var(--auth-radius-control)] border-transparent text-sm font-semibold`}
        >
          {pending ? "Entrando…" : "Entrar"}
        </Button>
      </form>

      <p className="mt-7 text-center text-[13px] text-[hsl(var(--auth-form-ink-muted))]">
        Não tem conta?{" "}
        <Link href="/cadastro" className="font-medium text-[hsl(var(--auth-accent-ink))] hover:underline">
          Criar conta
        </Link>
      </p>
    </div>
  );
}
