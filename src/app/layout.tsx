import type { Metadata } from "next";
import "./globals.css";
import "./version.css";

export const metadata: Metadata = {
  title: "SafariPOS | Point of sale and inventory",
  description: "Point of sale, inventory, M-PESA and eTIMS workflows for Kenyan businesses.",
  applicationName: "SafariPOS",
  themeColor: "#111A20",
  icons: {
    icon: [{ url: "/icon-source.png", type: "image/png" }],
    apple: [{ url: "/icon-source.png", type: "image/png" }],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const appVersion = process.env.NEXT_PUBLIC_APP_VERSION ?? "version-unset";
  return <html lang="en"><body>{children}<footer className="app-version-footer">SafariPOS · build {appVersion}</footer></body></html>;
}
