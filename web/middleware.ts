import type { NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return updateSession(request);
}

export const config = {
  runtime: "nodejs",
  matcher: [
    /*
     * Roda em todas as rotas exceto assets estáticos e imagens —
     * mesmo padrão recomendado pela documentação do @supabase/ssr.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
