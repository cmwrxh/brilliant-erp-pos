import Image from "next/image";
import Link from "next/link";

type LogoProps = { variant?: "sidebar" | "auth" };

export function Logo({ variant = "sidebar" }: LogoProps) {
  const className = variant === "auth" ? "auth-brand" : "brand";
  return (
    <Link className={className} href="/" aria-label="SafariPOS home">
      <Image
        className={variant === "auth" ? "safaripos-logo auth-logo-image" : "safaripos-logo sidebar-logo-image"}
        src="/static/logo-full.png"
        alt="SafariPOS"
        width={180}
        height={52}
        priority
        unoptimized
      />
      {variant === "sidebar" ? <Image className="safaripos-logo sidebar-icon-image" src="/icon-source.png" alt="" width={42} height={42} priority unoptimized /> : null}
    </Link>
  );
}
