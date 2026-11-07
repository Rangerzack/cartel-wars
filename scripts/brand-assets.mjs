// The app icon and the splash, drawn from the design tokens (Border Night) so a palette change can regenerate them:
//   web/public/icon.svg (favicon, rounded), icon-192.png, icon-512.png (home-screen icons, rounded with transparent
//   corners), web/assets/icon.png and the iOS AppIcon (1024, full bleed: iOS masks its own corners), and the splash
//   (2732², light and dark the same: the wordmark on the ground) for web/assets and the iOS Splash set.
// The splash has no grain (a 2732² grain is 4 MB of PNG; the gradient alone is a few hundred KB). The lettering is Oswald outlined to paths (scripts/brand-paths.json, from scripts/brand-paths.py), so the files need no font.
// Usage: node scripts/brand-assets.mjs   (from the repo root or scripts/)
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const web = path.join(here, '..', 'web')
const P = JSON.parse(fs.readFileSync(path.join(here, 'brand-paths.json'), 'utf8'))

const T = {
  bgHi: '#18231f', bg: '#0a1214', well: '#0f1816',
  goldHi: '#ffc46b', gold: '#f2a33a', goldMid: '#e08f2a', goldLo: '#b86e14', goldInk: '#1f1200',
  bone: '#f2e8d5', ash: '#b5ab97',
}

/** The icon at 512 units. `rounded` draws the squircle with transparent corners; iOS wants full bleed. */
function iconSvg(rounded) {
  const r = rounded ? 112 : 0
  const cw = P.cw   // { d, w, cap } at 200 px
  const x = (512 - cw.w) / 2, y = 256 + cw.cap / 2 + 6
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${T.bgHi}"/><stop offset="1" stop-color="${T.bg}"/></linearGradient>
    <radialGradient id="light" cx="50%" cy="-10%" r="75%"><stop offset="0" stop-color="${T.gold}" stop-opacity=".28"/><stop offset="1" stop-color="${T.gold}" stop-opacity="0"/></radialGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${T.goldHi}"/><stop offset=".55" stop-color="${T.goldMid}"/><stop offset="1" stop-color="${T.goldLo}"/></linearGradient>
    <linearGradient id="goldText" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${T.goldHi}"/><stop offset=".5" stop-color="${T.gold}"/><stop offset="1" stop-color="${T.goldLo}"/></linearGradient>
    <pattern id="grain" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(135)"><rect width="6" height="6" fill="none"/><rect width="2" height="6" fill="#fff" fill-opacity=".018"/></pattern>
    <clipPath id="clip"><rect width="512" height="512" rx="${r}"/></clipPath>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="6" stdDeviation="8" flood-color="#000" flood-opacity=".55"/></filter>
  </defs>
  <g clip-path="url(#clip)">
    <rect width="512" height="512" fill="url(#bg)"/>
    <rect width="512" height="512" fill="url(#grain)"/>
    <rect width="512" height="512" fill="url(#light)"/>
  </g>
  <path d="M256 88 L396 148 V256 C396 342 332 400 256 428 C180 400 116 342 116 256 V148 Z" fill="${T.well}" stroke="url(#gold)" stroke-width="14" stroke-linejoin="round" filter="url(#shadow)"/>
  <path d="M256 112 L374 162 V256 C374 328 320 378 256 403 C192 378 138 328 138 256 V162 Z" fill="none" stroke="#fff" stroke-opacity=".06" stroke-width="3" stroke-linejoin="round"/>
  <g transform="translate(${x.toFixed(1)} ${(y + 4).toFixed(1)})"><path d="${cw.d}" fill="#000" fill-opacity=".45"/></g>
  <g transform="translate(${x.toFixed(1)} ${y.toFixed(1)})"><path d="${cw.d}" fill="url(#goldText)"/></g>
</svg>`
}

/** The splash at 2732 units: the wordmark with its amber rule and the tagline, centred on the ground. */
function splashSvg() {
  const t = P.title, g = P.tag   // at 120 px / 26 px
  const s = 2.4, ts = 2.6
  const tx = (2732 - t.w * s) / 2, ty = 1366 + (t.cap * s) / 2 - 40
  const gx = (2732 - g.w * ts) / 2, gy = ty + 170
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2732 2732">
  <defs>
    <radialGradient id="light" cx="50%" cy="38%" r="60%"><stop offset="0" stop-color="${T.gold}" stop-opacity=".16"/><stop offset="1" stop-color="${T.gold}" stop-opacity="0"/></radialGradient>
    <linearGradient id="silver" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".45" stop-color="#e6ded0"/><stop offset=".52" stop-color="#9a9385"/><stop offset="1" stop-color="#d8d0c0"/></linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${T.goldLo}"/><stop offset=".5" stop-color="${T.goldHi}"/><stop offset="1" stop-color="${T.goldLo}"/></linearGradient>
  </defs>
  <rect width="2732" height="2732" fill="${T.bg}"/>
  <rect width="2732" height="2732" fill="url(#light)"/>
  <g transform="translate(${tx.toFixed(1)} ${(ty + 8).toFixed(1)}) scale(${s})"><path d="${t.d}" fill="#000" fill-opacity=".6"/></g>
  <g transform="translate(${tx.toFixed(1)} ${ty.toFixed(1)}) scale(${s})"><path d="${t.d}" fill="url(#silver)"/></g>
  <rect x="${(1366 - 200).toFixed(0)}" y="${(ty + 56).toFixed(0)}" width="400" height="8" rx="4" fill="url(#gold)"/>
  <g transform="translate(${gx.toFixed(1)} ${gy.toFixed(1)}) scale(${ts})"><path d="${g.d}" fill="${T.gold}" fill-opacity=".9"/></g>
</svg>`
}

const outs = {
  'public/icon.svg': iconSvg(true),
}
for (const [f, svg] of Object.entries(outs)) fs.writeFileSync(path.join(web, f), svg)

const browser = await chromium.launch()
async function render(svg, size, file, transparent) {
  const p = await browser.newPage({ viewport: { width: size, height: size }, deviceScaleFactor: 1 })
  await p.setContent(`<body style="margin:0;background:${transparent ? 'transparent' : T.bg}">${svg.replace('<svg ', `<svg width="${size}" height="${size}" style="display:block" `)}</body>`)
  await p.screenshot({ path: path.join(web, file), omitBackground: !!transparent })
  await p.close()
}
await render(iconSvg(true), 512, 'public/icon-512.png', true)
await render(iconSvg(true), 192, 'public/icon-192.png', true)
await render(iconSvg(false), 1024, 'assets/icon.png')
await render(iconSvg(false), 1024, 'ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png')
const splash = splashSvg()
await render(splash, 2732, 'assets/splash.png')
await render(splash, 2732, 'assets/splash-dark.png')
for (const scale of ['1x', '2x', '3x']) for (const dark of ['', '-dark']) {
  await render(splash, 2732, `ios/App/App/Assets.xcassets/Splash.imageset/Default@${scale}~universal~anyany${dark}.png`)
}
await browser.close()
console.log('brand assets written')
