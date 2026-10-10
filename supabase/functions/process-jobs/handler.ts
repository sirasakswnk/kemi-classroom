// Edge Function `process-jobs` (TECHNICAL_DESIGN 9.1; TECHNICAL_BUILD_PLAN 5) — pg_cron ปลุกเมื่อมีงาน (0024_jobs_cron)
//   POST /process-jobs  header x-jobs-secret = รหัสลับใน Vault/secret JOBS_SECRET (เทียบแบบเวลาคงที่)
// ทำสองอย่างต่อรอบ ภายในเวลาไม่เกิน ~20 วินาที:
//   1. sweeper แถว copying ที่ค้าง: HEAD ไฟล์ปลายทาง (Class B นับแหล่ง complete) → มี = เข้าคิวลบ / ไม่มี = ลบแถว
//   2. ดึงงานทีละชุด (jobs_claim, SKIP LOCKED) — delete_asset: delete_asset_begin ตัดสิน (ธงสำรอง/ยังผูก/ไม่มีแล้ว)
//      → DeleteObject ระบุ versionId (Class A ไม่นับเพดาน) → 200/204/404 = delete_asset_finish · อื่น ๆ = jobs_fail
// ฐานข้อมูลตัดสินทุกอย่าง ฟังก์ชันเรียก B2 ตามที่ RPC บอกเท่านั้น; RPC ทั้งหมดเรียกด้วย service role
// ไม่มี CORS (เรียกจากฐานข้อมูล ไม่ใช่เบราว์เซอร์) และไม่ log key/รหัสลับ
import {
  b2ConfigFrom,
  deleteVersionRequest,
  headObjectRequest,
  isCapExceeded,
} from '../_shared/b2.ts'
import { serviceRpc, type Ctx, type Deps } from '../_shared/context.ts'

export type { Deps } from '../_shared/context.ts'

export const DEADLINE_MS = 20_000
export const CLAIM_SIZE = 10
export const COPYING_SIZE = 10

interface Job {
  id: number
  kind: string
  payload: Record<string, unknown>
  attempts: number
}

export interface Summary {
  copying: { checked: number; queued: number; removed: number; errors: number }
  jobs: { claimed: number; deleted: number; done: number; deferred: number; failed: number }
}

const reply = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  })

/** เทียบรหัสลับแบบเวลาคงที่: SHA-256 ทั้งสองฝั่งแล้ว XOR ทุกไบต์ (ความยาวไม่รั่วผ่านเวลา) */
export async function secretMatches(given: string, expected: string): Promise<boolean> {
  if (!expected) return false
  const enc = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(given)),
    crypto.subtle.digest('SHA-256', enc.encode(expected)),
  ])
  const x = new Uint8Array(a)
  const y = new Uint8Array(b)
  let diff = 0
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i]
  return diff === 0
}

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  return async (req) => {
    if (req.method !== 'POST' || !/\/process-jobs\/?$/.test(new URL(req.url).pathname)) {
      return reply({ error: 'not_found' }, 404)
    }
    const expected = deps.env('JOBS_SECRET')?.trim() ?? ''
    const supabaseUrl = deps.env('SUPABASE_URL')
    const serviceKey = deps.env('SUPABASE_SERVICE_ROLE_KEY')?.trim() || null
    let ctx: Ctx
    try {
      if (!expected) throw new Error('config_missing:JOBS_SECRET')
      if (!supabaseUrl) throw new Error('config_missing:SUPABASE_URL')
      if (!serviceKey) throw new Error('config_missing:SUPABASE_SERVICE_ROLE_KEY')
      ctx = {
        deps,
        cors: new Headers(),
        config: b2ConfigFrom(deps.env),
        supabaseUrl,
        apikey: serviceKey,
        authorization: `Bearer ${serviceKey}`,
        serviceKey,
      }
    } catch (e) {
      console.error(`process-jobs misconfigured: ${(e as Error).message}`)
      return reply({ error: 'internal_error' }, 500)
    }
    if (!(await secretMatches(req.headers.get('x-jobs-secret') ?? '', expected))) {
      return reply({ error: 'not_authenticated' }, 401)
    }
    await req.body?.cancel()
    const summary = await runOnce(ctx)
    return reply(summary, 200)
  }
}

export async function runOnce(ctx: Ctx): Promise<Summary> {
  const now = ctx.deps.now ?? (() => new Date())
  const started = now().getTime()
  const summary: Summary = {
    copying: { checked: 0, queued: 0, removed: 0, errors: 0 },
    jobs: { claimed: 0, deleted: 0, done: 0, deferred: 0, failed: 0 },
  }
  await sweepCopying(ctx, summary)
  while (now().getTime() - started < DEADLINE_MS) {
    const claimed = await serviceRpc(ctx, 'jobs_claim', { p_limit: CLAIM_SIZE })
    if (!claimed.ok || !Array.isArray(claimed.data) || claimed.data.length === 0) break
    for (const job of claimed.data as Job[]) {
      summary.jobs.claimed++
      if (job.kind === 'delete_asset') await deleteAsset(ctx, job, summary)
      else await failJob(ctx, job, 'unknown_kind', summary)
    }
  }
  return summary
}

async function failJob(ctx: Ctx, job: Job, error: string, summary: Summary) {
  const r = await serviceRpc(ctx, 'jobs_fail', { p_job_id: job.id, p_error: error })
  if (!r.ok) console.error(`process-jobs: fail not recorded for job ${job.id} (${r.code})`)
  summary.jobs.failed++
}

async function deleteAsset(ctx: Ctx, job: Job, summary: Summary) {
  const begin = await serviceRpc(ctx, 'delete_asset_begin', { p_job_id: job.id })
  if (!begin.ok) {
    console.error(`process-jobs: delete_asset_begin ${job.id} (${begin.code})`)
    return
  }
  const plan = begin.data as { action?: string; final_key?: string; version_id?: string }
  if (plan.action === 'defer') {
    summary.jobs.deferred++
    return
  }
  if (plan.action !== 'delete') {
    if (plan.action === 'done') summary.jobs.done++
    return
  }
  let status: number
  try {
    const res = await ctx.deps.fetch(
      await deleteVersionRequest(ctx.config, String(plan.final_key), String(plan.version_id)),
    )
    status = res.status
    await res.body?.cancel()
  } catch {
    await failJob(ctx, job, 'b2_network', summary)
    return
  }
  // 404 = ไม่มีเวอร์ชันนั้นแล้ว (ลบไปแล้วในรอบก่อน) — ถือว่าสำเร็จ (idempotent)
  if (status === 200 || status === 204 || status === 404) {
    const done = await serviceRpc(ctx, 'delete_asset_finish', { p_job_id: job.id })
    if (done.ok) summary.jobs.deleted++
    else console.error(`process-jobs: delete_asset_finish ${job.id} (${done.code})`)
    return
  }
  await failJob(ctx, job, `b2_${status}`, summary)
}

async function sweepCopying(ctx: Ctx, summary: Summary) {
  const list = await serviceRpc(ctx, 'copying_stale', { p_limit: COPYING_SIZE })
  if (!list.ok || !Array.isArray(list.data)) return
  for (const item of list.data as { asset_id: string; final_key: string }[]) {
    let res: Response
    try {
      res = await ctx.deps.fetch(await headObjectRequest(ctx.config, item.final_key))
    } catch {
      summary.copying.errors++
      continue
    }
    const body = res.status === 200 || res.status === 404 ? '' : await res.text().catch(() => '')
    if (res.status === 200 || res.status === 404) await res.body?.cancel()
    summary.copying.checked++
    const usage = await serviceRpc(ctx, 'record_b2_usage', {
      p_source: 'complete',
      p_requests: 1,
      p_bytes: 0,
    })
    if (!usage.ok) console.error(`process-jobs: usage not recorded (${usage.code})`)
    const version = res.status === 200 ? res.headers.get('x-amz-version-id') : null
    if ((res.status === 200 && version) || res.status === 404) {
      const r = await serviceRpc(ctx, 'sweep_copying_finish', {
        p_asset_id: item.asset_id,
        p_version_id: version,
      })
      if (r.ok && r.data === 'queued') summary.copying.queued++
      else if (r.ok && r.data === 'removed') summary.copying.removed++
      continue
    }
    summary.copying.errors++
    console.error(`process-jobs: head ${res.status}`)
    // ครบเพดานรายวันของ B2 — หยุด HEAD ที่เหลือ (รอบหน้าลองใหม่หลัง 07:00 น.)
    if (isCapExceeded(res.status, body)) return
  }
}
