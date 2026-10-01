// App icon and launch screen (#21): draws the shield mark and the wordmark with the app's own fonts and colours, then
// writes the PNGs Capacitor and Xcode read. Original art, full-bleed (iOS rounds the corners itself), no alpha channel.
//   web/assets/icon.png                       1024×1024
//   web/assets/splash.png, splash-dark.png    2732×2732, the wordmark centred (phones crop the sides)
//   web/ios/App/App/Assets.xcassets/…         the same files in the catalog's names
// Usage: node scripts/app-art.mjs   (run from the repo root; needs web/node_modules for the Oswald font)
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = fileURLToPath(new URL('..', import.meta.url))
const font = (w) => 'data:font/woff2;base64,' + fs.readFileSync(path.join(ROOT, `web/node_modules/@fontsource/oswald/files/oswald-latin-${w}-normal.woff2`)).toString('base64')
const css = `
  @font-face { font-family: Oswald; font-weight: 700; src: url(${font(700)}) format('woff2'); }
  @font-face { font-family: Oswald; font-weight: 500; src: url(${font(500)}) format('woff2'); }
  html, body { margin: 0; background: #121216; }
  .icon { width: 1024px; height: 1024px; position: relative; overflow: hidden; font-family: Oswald;
    background: radial-gradient(90% 55% at 50% -8%, rgba(227,179,65,.22), transparent 62%), linear-gradient(#2a2a32, #0b0b0d); }
  .icon svg { position: absolute; inset: 0; }
  .splash { width: 2732px; height: 2732px; display: flex; flex-direction: column; align-items: center; justify-content: center;
    background: radial-gradient(ellipse at 50% 30%, rgba(227,179,65,.14), transparent 50%), radial-gradient(ellipse at top, #24242c, #09090b 62%); }
  .wordmark { font-family: Oswald; font-weight: 700; font-size: 168px; line-height: 1; letter-spacing: 12px; text-transform: uppercase;
    background: linear-gradient(#ffffff, #d6d6de 45%, #8a8a98 52%, #c9c9d2); -webkit-background-clip: text; background-clip: text; color: transparent;
    filter: drop-shadow(0 8px 0 #000) drop-shadow(0 0 72px rgba(227,179,65,.18)); }
  .rule { height: 8px; width: 760px; margin: 36px auto 0; background: linear-gradient(90deg, transparent, #e3b341, transparent); box-shadow: 0 0 40px rgba(227,179,65,.6); }
  .tag { margin-top: 36px; color: #b3a37a; font-family: Oswald; font-weight: 500; font-size: 44px; letter-spacing: 8px; text-transform: uppercase; }
`
// The shield from web/public/icon.svg, scaled to fill the icon; the monogram is set in the display face.
const icon = `<div class="icon"><svg viewBox="0 0 512 512">
  <defs>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6d77a"/><stop offset=".55" stop-color="#e3b341"/><stop offset="1" stop-color="#9c7424"/></linearGradient>
    <linearGradient id="face" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b1b21"/><stop offset="1" stop-color="#0c0c0f"/></linearGradient>
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="9" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <g filter="url(#glow)" opacity=".55"><path d="M256 62 L420 130 V258 C420 356 348 424 256 458 C164 424 92 356 92 258 V130 Z" fill="none" stroke="#e3b341" stroke-width="10" stroke-linejoin="round"/></g>
  <path d="M256 62 L420 130 V258 C420 356 348 424 256 458 C164 424 92 356 92 258 V130 Z" fill="url(#face)" stroke="url(#gold)" stroke-width="16" stroke-linejoin="round"/>
  <path d="M256 92 L392 150 V256 C392 338 332 394 256 424 C180 394 120 338 120 256 V150 Z" fill="none" stroke="rgba(246,215,122,.22)" stroke-width="3" stroke-linejoin="round"/>
  <text x="256" y="318" text-anchor="middle" font-family="Oswald" font-weight="700" font-size="190" letter-spacing="-4" fill="url(#gold)" style="paint-order: stroke; stroke: #000; stroke-width: 6">CW</text>
</svg></div>`
const splash = `<div class="splash"><div class="wordmark">Cartel Wars</div><div class="rule"></div><div class="tag">Produce. Move product. Hold the block.</div></div>`

const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' })
const shots = [
  { html: icon, w: 1024, out: ['web/assets/icon.png', 'web/ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png'] },
  { html: splash, w: 2732, out: ['web/assets/splash.png', 'web/assets/splash-dark.png',
    ...['1x', '2x', '3x'].flatMap(s => [`web/ios/App/App/Assets.xcassets/Splash.imageset/Default@${s}~universal~anyany.png`, `web/ios/App/App/Assets.xcassets/Splash.imageset/Default@${s}~universal~anyany-dark.png`])] },
]
for (const s of shots) {
  const p = await b.newPage({ viewport: { width: s.w, height: s.w }, deviceScaleFactor: 1 })
  await p.setContent(`<!doctype html><style>${css}</style>${s.html}`)
  await p.evaluate(() => document.fonts.ready)
  const png = await p.screenshot({ type: 'png', omitBackground: false })
  for (const f of s.out) fs.writeFileSync(path.join(ROOT, f), png)
  console.log(`${s.w}×${s.w} → ${s.out.join(', ')}`)
}
await b.close()
