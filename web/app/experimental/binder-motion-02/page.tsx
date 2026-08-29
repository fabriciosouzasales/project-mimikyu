import type { Metadata } from "next";
import { BinderMotionView } from "@/components/experimental/binder-motion-02/binder-motion-view";

export const metadata: Metadata = {
  title: "Binder-Motion-02 · Page Turn (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function BinderMotion02ExperimentalPage() {
  return <BinderMotionView />;
}
