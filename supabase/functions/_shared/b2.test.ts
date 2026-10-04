// unit test ของ _shared/b2.ts — รันด้วย Node (type stripping): npm run functions:test
// ไม่เรียก B2 จริง (เทสต์กับ B2 จริงอยู่ใน ops/b2/proof.mjs ซึ่งรันด้วยมือ)
import { createHash, createHmac } from 'node:crypto'
import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  b2ConfigFrom,
  contentDisposition,
  GET_CACHE_CONTROL,
  isCapExceeded,
  isStagingKeyOf,
  presignGet,
  presignPut,
  presignUrl,
  regionOf,
  type B2Config,
} from './b2.ts'

const BATCH = '0b6d3c1e-6c55-4f4e-9d8b-2f1a3c4d5e6f'
const KEY = `staging/${BATCH}/7f3e2d1c-0b9a-4876-9543-210fedcba987`
const NOW = new Date('2026-10-05T03:04:05.678Z')
const config: B2Config = {
  keyId: '003testkeyid0000000000001',
  appKey: 'K003testapplicationkey000000000',
  bucket: 'kemi-dev-files',
  endpoint: 'https://s3.eu-central-003.backblazeb2.com',
  region: 'eu-central-003',
}

const sha256 = (s: string) => createHash('sha256').update(s, 'utf8').digest('hex')
const hmac = (k: string | Buffer, s: string) => createHmac('sha256', k).update(s, 'utf8').digest()
const rfc3986 = (s: string) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`)

// ตัวตรวจอิสระ: คำนวณลายเซ็นแบบที่ฝั่ง S3 ทำจาก URL ดิบ (ถอดรหัส %XX ตาม RFC 3986 — '+' ไม่ใช่ช่องว่าง)
function verify(
  signedUrl: string,
  method: string,
  headers: Record<string, string>,
  secret: string,
) {
  const url = new URL(signedUrl)
  const pairs = url.search
    .slice(1)
    .split('&')
    .map((p) => p.split('=').map(decodeURIComponent) as [string, string])
  const params = new Map(pairs)
  const signature = params.get('X-Amz-Signature')
  const query = pairs
    .filter(([k]) => k !== 'X-Amz-Signature')
    .map(([k, v]) => [rfc3986(k), rfc3986(v)])
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map((p) => p.join('='))
    .join('&')
  const all: Record<string, string> = { host: url.host, ...headers }
  const names = Object.keys(all).sort()
  const canonical = [
    method,
    url.pathname,
    query,
    names.map((n) => `${n}:${all[n]}\n`).join(''),
    names.join(';'),
    'UNSIGNED-PAYLOAD',
  ].join('\n')
  const date = params.get('X-Amz-Date')!
  const scope = params.get('X-Amz-Credential')!.split('/').slice(1).join('/')
  const [day, region, service] = scope.split('/')
  const toSign = ['AWS4-HMAC-SHA256', date, scope, sha256(canonical)].join('\n')
  const key = hmac(hmac(hmac(hmac(`AWS4${secret}`, day), region), service), 'aws4_request')
  assert.equal(params.get('X-Amz-SignedHeaders'), names.join(';'))
  assert.equal(signature, createHmac('sha256', key).update(toSign, 'utf8').digest('hex'))
  return params
}

test('presignUrl ตรงกับตัวอย่าง presigned URL ในเอกสาร AWS SigV4 (query string)', async () => {
  const url = await presignUrl({
    config: {
      keyId: 'AKIAIOSFODNN7EXAMPLE',
      appKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
    },
    method: 'GET',
    url: new URL('https://examplebucket.s3.amazonaws.com/test.txt'),
    expiresSeconds: 86400,
    now: new Date('2013-05-24T00:00:00Z'),
  })
  assert.equal(
    new URL(url).searchParams.get('X-Amz-Signature'),
    'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
  )
})

test('regionOf / b2ConfigFrom อ่าน endpoint ของ B2 และไม่บอกค่าลับใน error', () => {
  assert.equal(regionOf('https://s3.eu-central-003.backblazeb2.com'), 'eu-central-003')
  assert.equal(regionOf('s3.us-west-004.backblazeb2.com'), 'us-west-004')
  assert.throws(() => regionOf('https://example.com'), /b2_endpoint_invalid/)
  const env: Record<string, string> = {
    B2_KEY_ID: ' id ',
    B2_APP_KEY: 'secret-value',
    B2_BUCKET: 'kemi-dev-files',
    B2_ENDPOINT: 's3.eu-central-003.backblazeb2.com',
  }
  const got = b2ConfigFrom((n) => env[n])
  assert.deepEqual(got, {
    keyId: 'id',
    appKey: 'secret-value',
    bucket: 'kemi-dev-files',
    endpoint: 'https://s3.eu-central-003.backblazeb2.com',
    region: 'eu-central-003',
  })
  assert.throws(
    () => b2ConfigFrom((n) => (n === 'B2_APP_KEY' ? '' : env[n])),
    /^Error: b2_config_missing:B2_APP_KEY$/,
  )
  assert.throws(
    () =>
      b2ConfigFrom((n) =>
        n === 'B2_ENDPOINT' ? 'http://s3.eu-central-003.backblazeb2.com' : env[n],
      ),
    /b2_endpoint_invalid/,
  )
  assert.throws(
    () => b2ConfigFrom((n) => (n === 'B2_BUCKET' ? 'Kemi_Files' : env[n])),
    /b2_bucket_invalid/,
  )
})

test('isStagingKeyOf: เฉพาะ staging/{batch_id}/{uuid} ของ batch นั้น', () => {
  assert.equal(isStagingKeyOf(KEY, BATCH), true)
  assert.equal(isStagingKeyOf(KEY, BATCH.toUpperCase()), true)
  assert.equal(isStagingKeyOf(KEY, '11111111-2222-4333-8444-555555555555'), false)
  assert.equal(isStagingKeyOf(KEY.replace('staging/', 'files/'), BATCH), false)
  assert.equal(isStagingKeyOf(`${KEY}/x`, BATCH), false)
  assert.equal(isStagingKeyOf(`staging/${BATCH}/../files/x`, BATCH), false)
})

test('presignPut: key ใต้ staging/ อายุ 5 นาที ลงลายเซ็น content-type และ content-length', async () => {
  const url = await presignPut(
    config,
    { key: KEY, contentType: 'image/jpeg', sizeBytes: 940000 },
    NOW,
  )
  assert.ok(url.startsWith(`https://s3.eu-central-003.backblazeb2.com/kemi-dev-files/${KEY}?`))
  const params = verify(
    url,
    'PUT',
    { 'content-length': '940000', 'content-type': 'image/jpeg' },
    config.appKey,
  )
  assert.equal(params.get('X-Amz-Expires'), '300')
  assert.equal(params.get('X-Amz-Date'), '20261005T030405Z')
  assert.equal(
    params.get('X-Amz-Credential'),
    `${config.keyId}/20261005/eu-central-003/s3/aws4_request`,
  )
  assert.equal(params.get('X-Amz-SignedHeaders'), 'content-length;content-type;host')
  assert.ok(!url.includes(config.appKey))
  // ขนาดหรือชนิดต่างจากที่ลงลายเซ็น = ลายเซ็นไม่ตรง
  assert.throws(() =>
    verify(url, 'PUT', { 'content-length': '940001', 'content-type': 'image/jpeg' }, config.appKey),
  )
  assert.throws(() =>
    verify(url, 'PUT', { 'content-length': '940000', 'content-type': 'image/png' }, config.appKey),
  )
})

test('presignPut ปฏิเสธ key นอก staging/ และขนาดผิด', async () => {
  const file = { key: KEY, contentType: 'image/png', sizeBytes: 10 }
  await assert.rejects(presignPut(config, { ...file, key: 'files/abc' }), /b2_key_not_staging/)
  await assert.rejects(
    presignPut(config, { ...file, key: `staging/${BATCH}/x` }),
    /b2_key_not_staging/,
  )
  await assert.rejects(presignPut(config, { ...file, sizeBytes: 0 }), /b2_size_invalid/)
  await assert.rejects(presignPut(config, { ...file, sizeBytes: 1.5 }), /b2_size_invalid/)
})

test('contentDisposition: ชื่อไทยเป็น filename* แบบ UTF-8 และมี filename ASCII สำรอง', () => {
  assert.equal(
    contentDisposition('attachment', "การบ้าน (1)'s.pdf"),
    `attachment; filename="_______ (1)'s.pdf"; filename*=UTF-8''%E0%B8%81%E0%B8%B2%E0%B8%A3%E0%B8%9A%E0%B9%89%E0%B8%B2%E0%B8%99%20%281%29%27s.pdf`,
  )
  assert.equal(
    contentDisposition('inline', 'a"b\\c.png'),
    `inline; filename="a_b_c.png"; filename*=UTF-8''a%22b%5Cc.png`,
  )
})

test('presignGet: versionId + response-* อยู่ในลายเซ็น ช่องว่างเป็น %20 (ไม่ใช่ +)', async () => {
  const disposition = contentDisposition('attachment', 'ใบงาน ที่ 1 + เฉลย.pdf')
  const url = await presignGet(
    config,
    {
      key: KEY,
      versionId:
        '4_z27c88f1d182b150646ff0b16_f1004ba650fe24e6b_d20260105_m030405_c003_v0312005_t0000_u01',
      contentType: 'application/pdf',
      disposition,
      cacheControl: GET_CACHE_CONTROL,
    },
    { now: NOW },
  )
  assert.ok(!new URL(url).search.includes('+'))
  const params = verify(url, 'GET', {}, config.appKey)
  assert.equal(params.get('response-content-disposition'), disposition)
  assert.equal(params.get('response-content-type'), 'application/pdf')
  assert.equal(params.get('response-cache-control'), 'private,max-age=600')
  assert.equal(params.get('X-Amz-Expires'), '600')
  assert.equal(params.get('X-Amz-SignedHeaders'), 'host')
  await assert.rejects(presignGet(config, { key: 'other/x' }), /b2_key_invalid/)
})

test('isCapExceeded: 403 ที่ข้อความลงท้าย cap exceeded เท่านั้น', () => {
  const body = (m: string) =>
    `<?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code><Message>${m}</Message></Error>`
  assert.equal(
    isCapExceeded(
      403,
      body('Cannot download file, download bandwidth or transaction (Class B) cap exceeded.'),
    ),
    true,
  )
  assert.equal(isCapExceeded(403, body('Cannot upload files, storage cap exceeded.')), true)
  assert.equal(isCapExceeded(403, body('Signature validation failed')), false)
  assert.equal(isCapExceeded(500, body('cap exceeded')), false)
})
