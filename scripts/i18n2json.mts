// GENERATES LaWallet/Resources/{en,es}.lproj/wallet.json from lawallet-nwc apps/web/lib/client/i18n.
// Run: npx tsx scripts/i18n2json.mts <lawallet-nwc>/apps/web/lib/client/i18n
// Functions become `{param}` templates (plural helpers yield their plural form; pick singular in Swift).
import { writeFileSync } from 'fs'
import { resolve } from 'path'
const root = resolve(process.argv[2])
const params = (fn: Function) =>
  (fn.toString().match(/^\s*(?:function\s*\w*)?\(?([^)=]*)\)?\s*=>/)?.[1] ?? '')
    .split(',').map(s => s.trim().split(/[:=\s]/)[0]).filter(Boolean)
function flatten(obj: any, prefix: string, acc: Record<string, string>) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k
    if (typeof v === 'string') acc[key] = v
    else if (typeof v === 'function') {
      const s = (v as any)(...params(v).map(p => `{${p}}`))
      if (typeof s === 'string') acc[key] = s
    } else if (v && typeof v === 'object') flatten(v, key, acc)
  }
  return acc
}
for (const loc of ['en', 'es']) {
  const mod = await import(`${root}/${loc}/index.ts`)
  const src = mod.default?.default ?? mod.default ?? mod
  const dict: Record<string, string> = {}
  for (const ns of Object.keys(src).sort()) flatten(src[ns], ns, dict)
  writeFileSync(resolve(import.meta.dirname, `../LaWallet/Resources/${loc}.lproj/wallet.json`), JSON.stringify(dict, null, 1) + '\n')
  console.log(loc, Object.keys(dict).length)
}
