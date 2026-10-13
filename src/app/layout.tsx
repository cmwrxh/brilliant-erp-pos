import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "SafariPOS | Point of sale and inventory", description: "Point of sale, inventory, M-PESA and eTIMS workflows for Kenyan businesses." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
