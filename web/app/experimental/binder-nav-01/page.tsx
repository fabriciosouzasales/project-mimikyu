import type { Metadata } from "next";
import { BinderNavView } from "@/components/experimental/binder-nav-01/binder-nav-view";

export const metadata: Metadata = {
  title: "Binder-Nav-01 · Navegação operacional (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function BinderNav01ExperimentalPage() {
  return <BinderNavView />;
}
