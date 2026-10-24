// ลงลายเซ็น S3 ของ Backblaze B2 — TECHNICAL_DESIGN 9 และ 9.2, TECHNICAL_BUILD_PLAN 5
// ใช้ได้ทั้ง Deno (Edge Function, import map ใน deno.json) และ Node (unit test, ops/b2/proof.mjs)
// ไม่อ่าน env และไม่เรียกเครือข่ายเอง: ผู้เรียกส่งค่าตั้งเข้ามา (b2ConfigFrom) แล้วได้ URL หรือ Request ที่ลงลายเซ็นแล้ว
// กลับไป (ผู้เรียก fetch เอง — ทดสอบด้วย B2 จำลองได้)
import { AwsClient, AwsV4Signer } from 'aws4fetch'

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
// ไฟล์จริง: files/{asset_id}.{jpg|png|pdf} (0017_upload_complete) — ไม่มีโฟลเดอร์ย่อยหรือ ..
const FINAL_KEY = new RegExp(`^files/${UUID}\\.(jpg|png|pdf)$`)

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
  if (!Number.isSafeInteger(file.sizeBytes) || file.sizeBytes < 1)
    throw new Error('b2_size_invalid')
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
 * B2 ปฏิเสธเพราะเกินเพดานรายวัน/พื้นที่ (Caps & Alerts) — เอกสาร B2 (Integration Checklist):
 * "403 Forbidden, cap_exceeded"; Native API ตอบ code เช่น cap_exceeded / download_cap_exceeded พร้อมข้อความ
 * "Cannot download file, download bandwidth or transaction (Class B) cap exceeded. …" — S3 API ตอบ XML <Error>
 * (Code ไม่ระบุในเอกสาร) ข้อความเดียวกัน จึงตรวจทั้งรหัสแบบขีดล่างและข้อความ
 * เพดานดาวน์โหลดกัน CopyObject (คัดลอกฝั่งเซิร์ฟเวอร์) ด้วย (TECHNICAL_DESIGN 9.3 ข้อ 5–6; ห้ามทดสอบด้วยการใช้จนเกินจริง)
 */
export function isCapExceeded(status: number, body: string): boolean {
  return status === 403 && /cap[ _]exceeded/i.test(body)
}

// ---------------------------------------------------------------------------
// คำขอฝั่งเซิร์ฟเวอร์ (ลงลายเซ็นใน header) — ขั้น complete (P3-04)
// ---------------------------------------------------------------------------
/** ขั้น complete อ่านไฟล์พักครั้งเดียว 16 ไบต์แรก (TECHNICAL_DESIGN 9 ข้อ 2) */
export const RANGE_BYTES = 16

/** ไม่ลองซ้ำเอง: GET ที่ลองซ้ำ = นับ Class B เพิ่ม และ CopyObject ที่ลองซ้ำหลังหมดเวลาอาจคัดลอกสองครั้ง */
function client(config: B2Config): AwsClient {
  return new AwsClient({
    accessKeyId: config.keyId,
    secretAccessKey: config.appKey,
    service: 's3',
    region: config.region,
    retries: 0,
  })
}

/** GET แบบ Range 0–15 ของเวอร์ชันล่าสุดของไฟล์พัก */
export async function rangeGetRequest(config: B2Config, key: string): Promise<Request> {
  if (!STAGING_KEY.test(key)) throw new Error('b2_key_not_staging')
  return client(config).sign(objectUrl(config, key).toString(), {
    method: 'GET',
    headers: { Range: `bytes=0-${RANGE_BYTES - 1}` },
  })
}

/** "bytes 0-15/1000" หรือ "bytes *\/0" → ขนาดเต็ม */
export function parseContentRange(value: string | null): number | null {
  const match = /^bytes (?:\d+-\d+|\*)\/(\d{1,15})$/.exec(value ?? '')
  return match ? Number(match[1]) : null
}

/** ETag ไม่เอาเครื่องหมายคำพูด (และ W/ ถ้ามี) — รูปแบบที่บันทึกเป็น checksum */
export function stripEtag(value: string | null | undefined): string | null {
  const v = (value ?? '').trim().replace(/^W\//, '').replace(/^"|"$/g, '')
  return v === '' ? null : v
}

export interface RangeRead {
  versionId: string
  totalBytes: number
  etag: string | null
  bytes: Uint8Array
}

/** ผล GET แบบ Range ที่ใช้ได้: 206 + x-amz-version-id + Content-Range + ไม่เกิน 16 ไบต์ — ไม่ตรงนี้คืน null */
export async function readRange(res: Response): Promise<RangeRead | null> {
  if (res.status !== 206) {
    await res.body?.cancel()
    return null
  }
  const versionId = res.headers.get('x-amz-version-id')
  const totalBytes = parseContentRange(res.headers.get('content-range'))
  const bytes = new Uint8Array(await res.arrayBuffer())
  if (!versionId || totalBytes === null || bytes.length > RANGE_BYTES) return null
  return { versionId, totalBytes, etag: stripEtag(res.headers.get('etag')), bytes }
}

/**
 * CopyObject ฝั่งเซิร์ฟเวอร์ระบุเวอร์ชันต้นทาง (ไฟล์ที่ถูกอัปทับหลังตรวจจะไม่ถูกคัดลอก) และตั้งชนิดที่ตรวจแล้ว
 * (x-amz-metadata-directive: REPLACE — TECHNICAL_DESIGN 9.2 ข้อ 4)
 */
export async function copyObjectRequest(
  config: B2Config,
  copy: { sourceKey: string; sourceVersionId: string; destKey: string; contentType: string },
): Promise<Request> {
  if (!STAGING_KEY.test(copy.sourceKey)) throw new Error('b2_key_not_staging')
  if (!FINAL_KEY.test(copy.destKey)) throw new Error('b2_key_invalid')
  if (!copy.sourceVersionId) throw new Error('b2_version_required')
  const source = `/${config.bucket}/${copy.sourceKey}?versionId=${encodeURIComponent(copy.sourceVersionId)}`
  return client(config).sign(objectUrl(config, copy.destKey).toString(), {
    method: 'PUT',
    headers: {
      'x-amz-copy-source': source,
      'x-amz-metadata-directive': 'REPLACE',
      'content-type': copy.contentType,
    },
  })
}

/** ผล CopyObject ที่สำเร็จ: 200 และเนื้อคำตอบไม่มี <Error> (S3 อาจตอบ 200 แล้วล้มกลางทาง) — ไม่มี ETag ให้เป็น null */
export function parseCopyResult(status: number, body: string): { etag: string | null } | null {
  if (status !== 200 || /<Error>/.test(body)) return null
  const match = /<ETag>([^<]*)<\/ETag>/.exec(body)
  return { etag: match ? stripEtag(match[1].replace(/&quot;|&#34;/g, '"')) : null }
}

/** ลบแบบระบุเวอร์ชัน (ลบจริง ไม่ใช่ซ่อน — TECHNICAL_DESIGN 9 “ลบแล้วต้องคืนพื้นที่จริง”) */
export async function deleteVersionRequest(
  config: B2Config,
  key: string,
  versionId: string,
): Promise<Request> {
  if (!STAGING_KEY.test(key) && !FINAL_KEY.test(key)) throw new Error('b2_key_invalid')
  if (!versionId) throw new Error('b2_version_required')
  const url = objectUrl(config, key)
  url.searchParams.set('versionId', versionId)
  return client(config).sign(url.toString(), { method: 'DELETE' })
}

/** HEAD ไฟล์จริง (sweeper แถว copying — TECHNICAL_DESIGN 9 ข้อ 3): นับเป็นคำขอ Class B 1 ครั้ง ไม่มีไบต์ดาวน์โหลด */
export async function headObjectRequest(config: B2Config, key: string): Promise<Request> {
  if (!FINAL_KEY.test(key)) throw new Error('b2_key_invalid')
  return client(config).sign(objectUrl(config, key).toString(), { method: 'HEAD' })
}

// ---------------------------------------------------------------------------
// เทียบยอดพื้นที่รายวัน (P6-04a) — ListObjectVersions นับทุกเวอร์ชัน รวมเวอร์ชันที่ถูกซ่อนและ staging/
// ---------------------------------------------------------------------------
/** หน้าละ 1000 รายการ (ค่าสูงสุดของ S3 API) = คำขอ Class C 1 ครั้งต่อหน้า */
export const LIST_PAGE_SIZE = 1000

/** ListObjectVersions ทั้ง bucket ต่อจาก cursor ของหน้าก่อน (key-marker + version-id-marker) */
export async function listVersionsRequest(
  config: B2Config,
  cursor: { keyMarker?: string | null; versionIdMarker?: string | null } = {},
): Promise<Request> {
  const url = new URL(`${config.endpoint}/${config.bucket}`)
  url.searchParams.set('versions', '')
  url.searchParams.set('max-keys', String(LIST_PAGE_SIZE))
  if (cursor.keyMarker) {
    url.searchParams.set('key-marker', cursor.keyMarker)
    if (cursor.versionIdMarker) url.searchParams.set('version-id-marker', cursor.versionIdMarker)
  }
  return client(config).sign(url.toString(), { method: 'GET' })
}

/** รายการเวอร์ชันแบบย่อที่ส่งต่อให้ storage_reconcile_step: key, version, ขนาด, เป็นเวอร์ชันล่าสุด */
export interface ListedVersion {
  k: string
  v: string
  s: number
  l: boolean
}

export interface VersionsPage {
  versions: ListedVersion[]
  deleteMarkers: number
  truncated: boolean
  nextKeyMarker: string | null
  nextVersionIdMarker: string | null
}

const decodeXml = (s: string) =>
  s.replace(/&(lt|gt|quot|apos|amp|#\d+|#x[0-9a-f]+);/gi, (m, e: string) => {
    const named: Record<string, string> = {
      lt: '<',
      gt: '>',
      quot: '"',
      apos: "'",
      amp: '&',
    }
    const low = e.toLowerCase()
    if (low in named) return named[low]
    const code = low.startsWith('#x') ? parseInt(low.slice(2), 16) : parseInt(low.slice(1), 10)
    return Number.isFinite(code) ? String.fromCodePoint(code) : m
  })

const tag = (xml: string, name: string): string | null => {
  const match = new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(xml)
  return match ? decodeXml(match[1]) : null
}

/**
 * อ่านผล ListObjectVersions (XML ของ S3) — ไม่ใช่ ListVersionsResult หรือรายการผิดรูป → null
 * <Version> มีขนาด · <DeleteMarker> (ป้ายซ่อนของ B2) ไม่มีขนาด นับแค่จำนวน
 */
export function parseListVersions(xml: string): VersionsPage | null {
  if (!/<ListVersionsResult[\s>]/.test(xml) || /<Error>/.test(xml)) return null
  const versions: ListedVersion[] = []
  for (const m of xml.matchAll(/<Version>([\s\S]*?)<\/Version>/g)) {
    const k = tag(m[1], 'Key')
    const v = tag(m[1], 'VersionId')
    const s = Number(tag(m[1], 'Size'))
    const l = tag(m[1], 'IsLatest')
    if (!k || !v || !Number.isSafeInteger(s) || s < 0 || (l !== 'true' && l !== 'false'))
      return null
    versions.push({ k, v, s, l: l === 'true' })
  }
  const truncated = tag(xml, 'IsTruncated') === 'true'
  const nextKeyMarker = tag(xml, 'NextKeyMarker') || null
  if (truncated && !nextKeyMarker) return null
  return {
    versions,
    deleteMarkers: [...xml.matchAll(/<DeleteMarker>/g)].length,
    truncated,
    nextKeyMarker,
    nextVersionIdMarker: tag(xml, 'NextVersionIdMarker') || null,
  }
}
