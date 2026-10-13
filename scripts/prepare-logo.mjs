import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const root = process.cwd();
const source = path.join(root, "design-assets", "logo-full.png");
const outputDir = path.join(root, "public", "static");
const pngPath = path.join(outputDir, "logo-full.png");
const webpPath = path.join(outputDir, "logo-full.webp");

await mkdir(outputDir, { recursive: true });
const sourceImage = sharp(source, { failOn: "error" });
const metadata = await sourceImage.metadata();
if (!metadata.width || !metadata.height) {
  throw new Error("SafariPOS logo source has no readable image dimensions.");
}

// Do not resize: both generated formats retain the source pixel dimensions.
await sharp(source).png().toFile(pngPath);
await sharp(source).webp({ quality: 90 }).toFile(webpPath);

console.log(
  `Prepared SafariPOS logo assets at ${metadata.width}x${metadata.height}: public/static/logo-full.png and public/static/logo-full.webp`
);
