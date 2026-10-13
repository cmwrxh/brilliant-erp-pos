import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "SafariPOS | Point of sale and inventory", description: "Point of sale, inventory, M-PESA and eTIMS workflows for Kenyan businesses." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const appVersion = process.env.NEXT_PUBLIC_APP_VERSION ?? "version-unset";
  return <html lang="en"><body>{children}<footer className="app-version-footer">SafariPOS · build {appVersion}</footer></body></html>;
}
