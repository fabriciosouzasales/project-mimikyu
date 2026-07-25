import { headers } from "next/headers";

/** Resolve a origem pública do app para montar links de e-mail (confirmação/recuperação). */
export async function getSiteUrl() {
  const headerList = await headers();
  const origin = headerList.get("origin");
  if (origin) return origin;
  return process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";
}
