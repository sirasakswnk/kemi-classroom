// ตรวจ CSP ของ build จริงในเครื่อง: เสิร์ฟ web/dist พร้อม header ชุดเดียวกับ Cloudflare Pages (dist/_headers กฎ /*) + SPA fallback
// และเพิ่ม `report-uri /__csp-report` ให้ "เบราว์เซอร์ส่งรายงานการละเมิดมาที่เซิร์ฟเวอร์นี้เอง" — จับได้ทั้งช่วงโหลดหน้า คำขอจาก
// worker และการละเมิดที่เกิดก่อนที่ตัวฟังในหน้าจะติดตั้ง; ไม่พึ่งตัวอ่าน console ของเครื่องมือเบราว์เซอร์ (มองไม่เห็นข้อความ CSP — พบ 18 ต.ค. 2026)
//
// วิธีใช้ (ทุกงานที่แตะสคริปต์/worker/wasm/รูป/สไตล์/คำขอไปบริการภายนอก/การดาวน์โหลดแบบ blob):
//   npm --prefix web run build
//   node ops/csp-serve.mjs web/dist 5173            # พอร์ต 5173 = origin ที่ล็อกอิน kemi-dev ค้างไว้ได้ (หยุด dev server ก่อน)
//   ใช้งานตามปกติในเบราว์เซอร์ แล้วดู: curl http://localhost:5173/__csp-summary   → { count, violations: [...] }
//   ตรวจว่าตัวตรวจทำงานจริงก่อนเชื่อผล “ไม่พบ”: เปิดหน้าใดก็ได้แล้วรัน fetch('https://example.com/probe') ในคอนโซลหน้านั้น
//   → ต้องขึ้นเป็น connect-src ใน /__csp-summary (ตัวควบคุมบวก)
// ล็อกลงไฟล์: argv[4] (ค่าเริ่มต้น = temp/kemi-csp-violations.log) ไม่ลง repo
import { appendFileSync, existsSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { extname, join, normalize, resolve } from 'node:path'

const root = resolve(process.argv[2] ?? 'web/dist')
const port = Number(process.argv[3] ?? 5173)
const logFile = process.argv[4] ?? join(tmpdir(), 'kemi-csp-violations.log')
writeFileSync(logFile, '')

const headersFile = readFileSync(join(root, '_headers'), 'utf8')
const block = {}
let inStar = false
for (const line of headersFile.split('\n')) {
  if (/^\/\*\s*$/.test(line)) inStar = true
  else if (/^\S/.test(line) && !line.startsWith('#')) inStar = false
  else if (inStar && /^\s+\S/.test(line)) {
    const i = line.indexOf(':')
    block[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
}
if (!block['Content-Security-Policy'])
  throw new Error('ไม่พบ Content-Security-Policy ใน dist/_headers')
block['Content-Security-Policy'] += '; report-uri /__csp-report'

const violations = []
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json',
}

createServer((req, res) => {
  const url = new URL(req.url, 'http://x')
  if (req.method === 'POST' && url.pathname === '/__csp-report') {
    let body = ''
    req.on('data', (d) => (body += d))
    req.on('end', () => {
      try {
        const r = JSON.parse(body)['csp-report'] ?? JSON.parse(body)
        const v = {
          directive: r['effective-directive'] ?? r['violated-directive'],
          blocked: r['blocked-uri'],
          document: r['document-uri'],
          source: r['source-file'],
          line: r['line-number'],
        }
        violations.push(v)
        const text = `VIOLATION ${JSON.stringify(v)}`
        console.log(text)
        appendFileSync(logFile, `${text}\n`)
      } catch {
        console.log('report ที่อ่านไม่ได้:', body.slice(0, 200))
      }
      res.writeHead(204).end()
    })
    return
  }
  if (url.pathname === '/__csp-summary') {
    res.writeHead(200, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify({ count: violations.length, violations }, null, 1))
    return
  }
  let file = normalize(join(root, decodeURIComponent(url.pathname)))
  if (!file.startsWith(root)) file = join(root, 'index.html')
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(root, 'index.html')
  res.writeHead(200, {
    ...block,
    'Content-Type': types[extname(file)] ?? 'application/octet-stream',
  })
  res.end(readFileSync(file))
}).listen(port, '127.0.0.1', () => {
  console.log(
    `csp-serve: ${root} → http://localhost:${port} · รายงานลง ${logFile} · สรุป /__csp-summary`,
  )
})
