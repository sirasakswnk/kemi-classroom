// ของที่ทุกเส้นทางของ Edge Function (uploads, files) ใช้ร่วมกัน
import type { B2Config } from './b2.ts'
import { callRpc, type RpcResult } from './rpc.ts'

export interface Deps {
  env: (name: string) => string | undefined
  /** ใช้ทั้งเรียก PostgREST และ B2 (Request ที่ลงลายเซ็นแล้ว) — เทสต์ส่งของจำลองแทน */
  fetch: typeof fetch
  now?: () => Date
}

export interface Ctx {
  deps: Deps
  cors: Headers
  config: B2Config
  supabaseUrl: string
  /** apikey + JWT ของผู้ใช้ — RPC ที่ตัดสินสิทธิ์ในฐานข้อมูล */
  apikey: string
  authorization: string
  /** กุญแจ service role — เฉพาะเส้นทางที่ต้องเขียนข้อมูลที่ระบบเชื่อ (complete, files/sign) */
  serviceKey: string | null
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_BODY_BYTES = 16384

export const isUuid = (v: unknown): v is string => typeof v === 'string' && UUID.test(v)

/** อ่าน JSON ของคำขอ (≤ 16 KB) — อ่านไม่ได้คืน undefined */
export async function readJson(req: Request): Promise<unknown> {
  const text = await req.text()
  if (text.length > MAX_BODY_BYTES) return undefined
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

/** RPC ในนามผู้ใช้ */
export function userRpc(ctx: Ctx, fn: string, args: Record<string, unknown>): Promise<RpcResult> {
  return callRpc({
    fetch: ctx.deps.fetch,
    supabaseUrl: ctx.supabaseUrl,
    apikey: ctx.apikey,
    authorization: ctx.authorization,
    fn,
    args,
  })
}

/** RPC ที่ GRANT ให้ service_role เท่านั้น — สิทธิ์ล้มแปลว่าตั้งค่าผิด จึงตอบ internal_error ไม่ใช่ not_authenticated */
export async function serviceRpc(
  ctx: Ctx,
  fn: string,
  args: Record<string, unknown>,
): Promise<RpcResult> {
  if (!ctx.serviceKey) return { ok: false, code: 'internal_error' }
  const result = await callRpc({
    fetch: ctx.deps.fetch,
    supabaseUrl: ctx.supabaseUrl,
    apikey: ctx.serviceKey,
    authorization: `Bearer ${ctx.serviceKey}`,
    fn,
    args,
  })
  if (!result.ok && result.code === 'not_authenticated') {
    console.error(`service rpc ${fn}: service key rejected`)
    return { ok: false, code: 'internal_error' }
  }
  return result
}
