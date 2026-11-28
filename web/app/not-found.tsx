import Link from "next/link";
import { BrandLogo } from "@/components/brand-logo";
import { Button } from "@/components/ui/button";

/**
 * 404 do app (V1-13 · E4, I3): substitui a página padrão do Next (em inglês, sem identidade).
 * Mensagem neutra de propósito: coleção inexistente, privada, convite pendente ou recusado
 * são indistinguíveis (V1-12) — nada é revelado sobre o que existe.
 *
 * Reteste E4: a logo completa centralizada é a âncora da página (escolha do proprietário);
 * título equilibrado em duas linhas e botões do Design System.
 */
export default function NotFound() {
  return (
    <main className="flex min-h-dvh bg-background px-6 py-16">
      <div className="m-auto flex w-full max-w-[460px] flex-col items-center text-center">
        <Link
          href="/"
          aria-label="MMKYU — início"
          className="rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-4 focus-visible:ring-offset-background"
        >
          <BrandLogo className="h-12 w-auto sm:h-14" />
        </Link>

        <span className="mt-14 h-0.5 w-10 rounded-full bg-primary" aria-hidden="true" />
        <p className="mt-3 text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">Página não encontrada</p>

        <h1 className="mt-3 text-balance font-heading text-[26px] font-semibold leading-[1.2] tracking-[-0.015em] text-foreground sm:text-[30px]">
          Esta página se escondeu de nós
        </h1>
        <p className="mt-3 max-w-[40ch] text-pretty text-[15px] leading-[1.6] text-muted-foreground">
          O endereço pode estar errado, ou o conteúdo não está disponível para a sua conta.
        </p>

        <div className="mt-8 flex w-full flex-col gap-3 sm:w-auto sm:flex-row-reverse">
          <Button asChild size="lg">
            <Link href="/colecoes">Ir para Minhas coleções</Link>
          </Button>
          <Button asChild variant="outline" size="lg">
            <Link href="/">Voltar ao início</Link>
          </Button>
        </div>
      </div>
    </main>
  );
}
