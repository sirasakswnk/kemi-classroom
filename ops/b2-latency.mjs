#!/usr/bin/env node
// P0-01: วัดเวลาเชื่อมต่อไปยัง endpoint S3 ของ Backblaze B2 ทุกภูมิภาค
// เพื่อเลือกภูมิภาคก่อนสมัคร B2 (เลือกแล้วเปลี่ยนไม่ได้) — TECHNICAL_BUILD_PLAN ส่วน 1, SYSTEM_SPEC ส่วน 12
//
// วิธีใช้ (ไม่ต้องติดตั้งอะไรเพิ่ม ใช้ Node 24):
//   node ops/b2-latency.mjs                 วัด 5 รอบต่อ endpoint
//   node ops/b2-latency.mjs --rounds 10     กำหนดจำนวนรอบ
//   node ops/b2-latency.mjs --label school  ใส่ชื่อเครือข่ายในบรรทัดสรุป (เช่น school, mobile)
//
// รันที่ Wi-Fi โรงเรียน และเน็ตมือถือ (แชร์ฮอตสปอต) อย่างละหลายครั้งต่างเวลา
// แล้วคัดลอกบรรทัด "สรุป" ท้ายผลมาให้ Claude Code
//
// สคริปต์ไม่ส่งข้อมูลใด ๆ นอกจากคำขอ HEAD เปล่าไปที่ endpoint (ได้คำตอบ 4xx ตามปกติเพราะไม่มีสิทธิ์)

import https from 'node:https';
import { performance } from 'node:perf_hooks';

// endpoint S3 ตามเอกสาร B2 — บัญชีใหม่ได้ cluster ล่าสุดของภูมิภาคที่เลือก
// (US West = us-west-004, US East = us-east-005, EU Central = eu-central-003, CA East = ca-east-006)
// cluster เก่าของ US West ใส่ไว้เทียบเส้นทางเท่านั้น
const ENDPOINTS = [
  { region: 'US West', host: 's3.us-west-004.backblazeb2.com', current: true },
  { region: 'US East', host: 's3.us-east-005.backblazeb2.com', current: true },
  { region: 'EU Central', host: 's3.eu-central-003.backblazeb2.com', current: true },
  { region: 'CA East', host: 's3.ca-east-006.backblazeb2.com', current: true },
  { region: 'US West (เก่า)', host: 's3.us-west-002.backblazeb2.com', current: false },
  { region: 'US West (เก่า)', host: 's3.us-west-001.backblazeb2.com', current: false },
];

const TIMEOUT_MS = 10_000;

function parseArgs(argv) {
  const opts = { rounds: 5, label: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--rounds') opts.rounds = Math.max(1, Number.parseInt(argv[++i], 10) || 5);
    else if (argv[i] === '--label') opts.label = String(argv[++i] ?? '');
    else if (argv[i] === '--help' || argv[i] === '-h') {
      console.log('node ops/b2-latency.mjs [--rounds N] [--label NAME]');
      process.exit(0);
    }
  }
  return opts;
}

// หนึ่งรอบ: การเชื่อมต่อใหม่ทุกครั้ง (agent: false) วัดจากเริ่มคำขอ
function probe(host) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const t = { dns: NaN, tcp: NaN, tls: NaN, ttfb: NaN, status: 0, error: '' };
    const req = https.request({ host, method: 'HEAD', path: '/', agent: false, timeout: TIMEOUT_MS }, (res) => {
      t.ttfb = performance.now() - t0;
      t.status = res.statusCode ?? 0;
      res.resume();
      res.on('end', () => resolve(t));
    });
    req.on('socket', (socket) => {
      socket.once('lookup', () => (t.dns = performance.now() - t0));
      socket.once('connect', () => (t.tcp = performance.now() - t0));
      socket.once('secureConnect', () => (t.tls = performance.now() - t0));
    });
    req.on('timeout', () => req.destroy(new Error(`timeout ${TIMEOUT_MS} ms`)));
    req.on('error', (err) => {
      t.error = err.code ?? err.message;
      resolve(t);
    });
    req.end();
  });
}

function median(values) {
  const v = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (v.length === 0) return NaN;
  const mid = Math.floor(v.length / 2);
  return v.length % 2 ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

const ms = (x) => (Number.isFinite(x) ? String(Math.round(x)).padStart(6) : '     -');

async function main() {
  const { rounds, label } = parseArgs(process.argv.slice(2));
  console.log(`วัด ${ENDPOINTS.length} endpoint × ${rounds} รอบ (หน่วย ms, ยิ่งน้อยยิ่งดี)\n`);

  const results = [];
  for (const ep of ENDPOINTS) {
    const samples = [];
    for (let i = 0; i < rounds; i++) {
      if (process.stdout.isTTY) process.stdout.write(`\r${ep.host} รอบ ${i + 1}/${rounds} `.padEnd(60));
      samples.push(await probe(ep.host));
    }
    const ok = samples.filter((s) => !s.error);
    const errors = [...new Set(samples.filter((s) => s.error).map((s) => s.error))];
    results.push({
      ...ep,
      ok: ok.length,
      errors,
      tcp: median(ok.map((s) => s.tcp)),
      tls: median(ok.map((s) => s.tls)),
      ttfb: median(ok.map((s) => s.ttfb)),
      ttfbMin: Math.min(...ok.map((s) => s.ttfb)),
      ttfbMax: Math.max(...ok.map((s) => s.ttfb)),
    });
  }
  if (process.stdout.isTTY) process.stdout.write('\r'.padEnd(61) + '\r');

  // TCP connect ≈ เวลาไป-กลับ 1 รอบ; TLS = จนจับมือเสร็จ; ตอบแรก = จนได้ header คำตอบ (ใกล้เคียงเวลาเริ่มอัปโหลดจริง)
  console.log('ภูมิภาค            endpoint                            สำเร็จ   TCP    TLS  ตอบแรก  (ต่ำสุด–สูงสุด)');
  const ranked = [...results].sort((a, b) => (a.ttfb || Infinity) - (b.ttfb || Infinity));
  for (const r of ranked) {
    const range = r.ok ? `(${Math.round(r.ttfbMin)}–${Math.round(r.ttfbMax)})` : r.errors.join(', ');
    console.log(
      `${r.region.padEnd(18)} ${r.host.padEnd(35)} ${`${r.ok}/${rounds}`.padStart(5)} ${ms(r.tcp)} ${ms(r.tls)} ${ms(r.ttfb)}  ${range}`,
    );
  }

  const best = ranked.find((r) => r.current && r.ok > 0);
  console.log(
    best
      ? `\nภูมิภาคที่เปิดให้สมัครและเร็วสุดจากเครือข่ายนี้: ${best.region} (${best.host})`
      : '\nเชื่อมต่อ endpoint ไม่ได้เลย — ตรวจอินเทอร์เน็ตหรือไฟร์วอลล์ของเครือข่ายนี้',
  );

  const stamp = new Date().toLocaleString('sv-SE', { timeZone: 'Asia/Bangkok' });
  const summary = results
    .filter((r) => r.current)
    .map((r) => `${r.region}=${r.ok ? Math.round(r.ttfb) : 'ERR'}`)
    .join(' ');
  console.log(`สรุป [${label || 'ไม่ระบุเครือข่าย'} ${stamp}] ตอบแรก(ms มัธยฐาน ${rounds} รอบ): ${summary}`);
}

main();
