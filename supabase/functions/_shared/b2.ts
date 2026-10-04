// ลงลายเซ็น S3 ของ Backblaze B2 — TECHNICAL_DESIGN 9 และ 9.2, TECHNICAL_BUILD_PLAN 5
// ใช้ได้ทั้ง Deno (Edge Function, import map ใน deno.json) และ Node (unit test, ops/b2/proof.mjs)
// ไม่อ่าน env และไม่เรียกเครือข่ายเอง: ผู้เรียกส่งค่าตั้งเข้ามา (b2ConfigFrom) แล้วได้ URL กลับไป
import { AwsV4Signer } from 'aws4fetch'

export interface B2Config {
  keyId: string
  appKey: string
  bucket: string
  /** origin ของ S3 endpoint เช่น https://s3.eu-central-003.backblazeb2.com */
  endpoint: string
  region: string
}

/** ลิงก์เขียนอายุประมาณ 5 นาที (9 ข้อ 1) */
export const PUT_EXPIRES_SECONDS = 300
/** ลิงก์อ่านอายุประมาณ 10 นาที (9 ข้อเสนอ, ใช้กับ files/sign) */
export const GET_EXPIRES_SECONDS = 600
/** ขอให้เบราว์เซอร์แคชไฟล์ตลอดอายุลิงก์ (9.3 ข้อ 3) — ไม่มีช่องว่างเพื่อให้ query สั้นและอ่านง่าย */
export const GET_CACHE_CONTROL = 'private,max-age=600'

const ENDPOINT_HOST = /^s3\.([a-z0-9-]+)\.backblazeb2\.com$/
const BUCKET_NAME = /^[a-z0-9-]{6,63}$/
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
const STAGING_KEY = new RegExp(`^staging/(${UUID})/${UUID}$`)
const FINAL_KEY = /^files\/[A-Za-z0-9/_.-]+$/

/** ภูมิภาคจากชื่อ endpoint ของ B2 (s3.<region>.backblazeb2.com) */
export function regionOf(endpoint: string): string {
  const host = new URL(endpoint.includes('://') ? endpoint : `https://${endpoint}`).host
  const match = ENDPOINT_HOST.exec(host)
  if (!match) throw new Error('b2_endpoint_invalid')
  return match[1]
}

/**
 * ค่าตั้งจากตัวแปร (B2_KEY_ID, B2_APP_KEY, B2_BUCKET, B2_ENDPOINT) — ขาดตัวใดหรือรูปแบบผิดให้ล้มทันที
 * ข้อความ error บอกแค่ชื่อตัวแปร ไม่บอกค่า
 */
export function b2ConfigFrom(get: (name: string) => string | undefined): B2Config {
  const value = (name: string): string => {
    const v = get(name)?.trim()
    if (!v) throw new Error(`b2_config_missing:${name}`)
    return v
  }
  const raw = value('B2_ENDPOINT')
  const endpoint = new URL(raw.includes('://') ? raw : `https://${raw}`)
  if (endpoint.protocol !== 'https:') throw new Error('b2_endpoint_invalid')
  const bucket = value('B2_BUCKET')
  if (!BUCKET_NAME.test(bucket)) throw new Error('b2_bucket_invalid')
  return {
    keyId: value('B2_KEY_ID'),
    appKey: value('B2_APP_KEY'),
    bucket,
    endpoint: endpoint.origin,
    region: regionOf(endpoint.origin),
  }
}

/** URL แบบ path-style: <endpoint>/<bucket>/<key> (key ของระบบเป็น ASCII ล้วน) */
export function objectUrl(config: B2Config, key: string): URL {
  return new URL(`${config.endpoint}/${config.bucket}/${key}`)
}

/** ไฟล์พักของ batch: staging/{batch_id}/{uuid} — สร้างที่ฐานข้อมูล (create_upload_batch) ที่นี่แค่ตรวจ */
export function isStagingKeyOf(key: string, batchId: string): boolean {
  const match = STAGING_KEY.exec(key)
  return match !== null && match[1] === batchId.toLowerCase()
}

/**
 * ลงลายเซ็นแบบ query (presigned URL) — แยกไว้ให้ทดสอบกับตัวอย่างของ AWS ได้
 * headers ที่ส่งเข้ามาถูกลงลายเซ็นทุกตัว (allHeaders) ผู้ใช้ลิงก์ต้องส่ง header ค่าเดียวกันเป๊ะ
 * query ใช้ %20 แทน + เพื่อให้ตรงกับรูปแบบที่ฝั่ง S3 ใช้คำนวณลายเซ็น
 */
export async function presignUrl(options: {
  config: Pick<B2Config, 'keyId' | 'appKey' | 'region'>
  method: 'GET' | 'PUT' | 'HEAD'
  url: URL
  headers?: Record<string, string>
  expiresSeconds: number
  now?: Date
}): Promise<string> {
  const { config, method, headers = {}, expiresSeconds, now } = options
  if (!Number.isInteger(expiresSeconds) || expiresSeconds < 1 || expiresSeconds > 604800) {
    throw new Error('b2_expires_invalid')
  }
  const url = new URL(options.url)
  url.searchParams.set('X-Amz-Expires', String(expiresSeconds))
  const signer = new AwsV4Signer({
    method,
    url: url.toString(),
    headers,
    accessKeyId: config.keyId,
    secretAccessKey: config.appKey,
    service: 's3',
    region: config.region,
    signQuery: true,
    allHeaders: true,
    datetime: now ? now.toISOString().replace(/[:-]|\.\d{3}/g, '') : undefined,
  })
  const signed = (await signer.sign()).url
  return `${signed.origin}${signed.pathname}${signed.search.replace(/\+/g, '%20')}`
}

/** ลิงก์อัปโหลดไฟล์พัก: ลงลายเซ็นชนิดและขนาดที่ประกาศไว้ — ไฟล์จริงไม่ตรง B2 ต้องปฏิเสธ (พิสูจน์ใน ops/b2/proof.mjs) */
export async function presignPut(
  config: B2Config,
  file: { key: string; contentType: string; sizeBytes: number },
  now?: Date,
): Promise<string> {
  if (!STAGING_KEY.test(file.key)) throw new Error('b2_key_not_staging')
  if (!Number.isSafeInteger(file.sizeBytes) || file.sizeBytes < 1) throw new Error('b2_size_invalid')
  return presignUrl({
    config,
    method: 'PUT',
    url: objectUrl(config, file.key),
    headers: { 'content-type': file.contentType, 'content-length': String(file.sizeBytes) },
    expiresSeconds: PUT_EXPIRES_SECONDS,
    now,
  })
}

/**
 * Content-Disposition ที่มีชื่อไฟล์ภาษาไทย (RFC 6266 + RFC 8187): filename= สำรองเป็น ASCII, filename*= เป็น UTF-8
 */
export function contentDisposition(kind: 'inline' | 'attachment', fileName: string): string {
  const fallback = fileName.replace(/[^\x20-\x7e]|["\\]/g, '_')
  const encoded = encodeURIComponent(fileName).replace(
    /['()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  )
  return `${kind}; filename="${fallback}"; filename*=UTF-8''${encoded}`
}

/** ลิงก์เปิดดู/ดาวน์โหลด: อ้าง version ที่บันทึกไว้เสมอ และกำหนดชนิด/ชื่อ/แคชในคำตอบ */
export async function presignGet(
  config: B2Config,
  file: {
    key: string
    versionId?: string
    contentType?: string
    disposition?: string
    cacheControl?: string
  },
  options: { expiresSeconds?: number; now?: Date } = {},
): Promise<string> {
  if (!FINAL_KEY.test(file.key) && !STAGING_KEY.test(file.key)) throw new Error('b2_key_invalid')
  const url = objectUrl(config, file.key)
  if (file.versionId) url.searchParams.set('versionId', file.versionId)
  if (file.cacheControl) url.searchParams.set('response-cache-control', file.cacheControl)
  if (file.contentType) url.searchParams.set('response-content-type', file.contentType)
  if (file.disposition) url.searchParams.set('response-content-disposition', file.disposition)
  return presignUrl({
    config,
    method: 'GET',
    url,
    expiresSeconds: options.expiresSeconds ?? GET_EXPIRES_SECONDS,
    now: options.now,
  })
}

/**
 * B2 ปฏิเสธเพราะเกินเพดานรายวัน/พื้นที่ (Caps & Alerts): HTTP 403, Code AccessDenied
 * ข้อความลงท้าย "cap exceeded" เช่น "Cannot download file, download bandwidth or transaction (Class B) cap exceeded."
 * (TECHNICAL_DESIGN 9.3 ข้อ 5–6; ห้ามทดสอบด้วยการใช้จนเกินจริง)
 */
export function isCapExceeded(status: number, body: string): boolean {
  return status === 403 && /cap exceeded/i.test(body)
}
