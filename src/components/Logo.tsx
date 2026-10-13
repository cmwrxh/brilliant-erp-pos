import Image from "next/image";
import Link from "next/link";

type LogoProps = { variant?: "sidebar" | "auth"; compact?: boolean };

export function Logo({ variant = "sidebar", compact = false }: LogoProps) {
  const className = variant === "auth" ? "auth-brand" : "brand";
  return (
    <Link className={className} href="/" aria-label="SafariPOS home">
      <Image
        className={variant === "auth" ? "safaripos-logo auth-logo-image" : "safaripos-logo sidebar-logo-image"}
        src="/logo-full.jfif"
        alt="SafariPOS"
        width={180}
        height={52}
        priority
        unoptimized
      />
      {compact ? <span className="sr-only">SafariPOS</span> : null}
    </Link>
  );
}
