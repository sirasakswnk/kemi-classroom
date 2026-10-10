// เรียก RPC ในนามผู้ใช้ (ส่ง JWT ของผู้ใช้ต่อให้ PostgREST) — สิทธิ์ตัดสินในฐานข้อมูลเสมอ ฟังก์ชันไม่ใช้ service role
export type RpcResult = { ok: true; data: unknown } | { ok: false; code: string }

const CODE = /^[a-z][a-z0-9_]{0,63}$/

export async function callRpc(options: {
  fetch: typeof fetch
  supabaseUrl: string
  /** apikey ที่หน้าเว็บส่งมา (publishable/anon) — ถ้าไม่มีใช้ค่าจาก env */
  apikey: string
  authorization: string
  fn: string
  args: Record<string, unknown>
}): Promise<RpcResult> {
  const response = await options.fetch(`${options.supabaseUrl}/rest/v1/rpc/${options.fn}`, {
    method: 'POST',
    headers: {
      apikey: options.apikey,
      Authorization: options.authorization,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify(options.args),
  })
  const text = await response.text()
  let body: unknown = null
  try {
    body = text ? JSON.parse(text) : null
  } catch {
    body = null
  }
  if (response.ok) return { ok: true, data: body }
  const err = (body ?? {}) as { code?: unknown; message?: unknown }
  if (err.code === 'P0001' && typeof err.message === 'string' && CODE.test(err.message)) {
    return { ok: false, code: err.message }
  }
  // JWT ไม่ถูกต้อง/หมดอายุ (PGRST30x) หรือ anon ไม่มีสิทธิ์เรียกฟังก์ชัน (42501)
  if (
    response.status === 401 ||
    err.code === '42501' ||
    (typeof err.code === 'string' && err.code.startsWith('PGRST30'))
  ) {
    return { ok: false, code: 'not_authenticated' }
  }
  console.error(
    `rpc ${options.fn} failed: ${response.status} ${typeof err.code === 'string' ? err.code : ''}`,
  )
  return { ok: false, code: 'internal_error' }
}
