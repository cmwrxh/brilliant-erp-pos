import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "Brilliant ERP | Business operations, clearly connected", description: "A modern ERP and point-of-sale workspace designed for Kenyan businesses." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
