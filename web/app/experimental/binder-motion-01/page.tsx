import type { Metadata } from "next";
import { BinderMotionView } from "@/components/experimental/binder-motion-01/binder-motion-view";

export const metadata: Metadata = {
  title: "Binder-Motion-01 (spike experimental) — Mimikyu",
  robots: { index: false, follow: false },
};

export default function BinderMotionExperimentalPage() {
  return <BinderMotionView />;
}
