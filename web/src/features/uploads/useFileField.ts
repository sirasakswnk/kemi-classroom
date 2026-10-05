// สถานะของช่องไฟล์: เลือกไฟล์ → ตรวจ (J4–J6) → เตรียม (ย่อ/แปลง HEIC ทีละไฟล์) → อัปโหลดเป็นชุด → asset_id
// อัปโหลดทันทีหลังเตรียมเสร็จ (ครูกดโพสต์แล้วไม่ต้องรอนาน) — ผูกกับโพสต์ทำใน P3-06b
import { useCallback, useEffect, useRef, useState } from 'react'
import { th } from '../../copy/th'
import type { AppError } from '../../lib/supabase'
import { completeUpload, putFile, requestBatch, type UploadPurpose } from './api'
import { PrepareError, prepareFile, type PreparedFile } from './image'
import {
  checkOriginal,
  checkPrepared,
  checkSet,
  kindOf,
  UPLOAD_LIMITS,
  type SourceKind,
} from './rules'
import { sleep, uploadSet, type UploadDeps, type UploadEvent } from './uploader'

export type FileStatus = 'preparing' | 'waiting' | 'uploading' | 'completing' | 'done' | 'error'

export interface FileItem {
  id: string
  original: File
  kind: SourceKind | null
  /** ชื่อที่แสดง: ชื่อที่จะส่ง (หลังเปลี่ยนนามสกุล) เมื่อเตรียมแล้ว */
  name: string
  status: FileStatus
  prepared?: PreparedFile
  /** object URL ของรูปหลังย่อ สำหรับตัวอย่าง (PDF ไม่มี) */
  previewUrl?: string
  /** 0–1 ระหว่าง PUT */
  progress: number
  error?: string
  /** ลองใหม่ได้ (ข้อผิดพลาดตอนอัปโหลด) — ไฟล์ที่ตรวจ/เตรียมไม่ผ่านต้องเลือกใหม่ */
  retryable: boolean
  assetId?: string
}

export interface FileFieldTarget {
  purpose: UploadPurpose
  classroomId: string
  postId: string | null
  adminMode: boolean
}

export const defaultUploadDeps: UploadDeps = {
  requestBatch,
  put: putFile,
  complete: completeUpload,
  sleep,
}

const PREPARE_MESSAGE: Record<PrepareError['reason'], string> = {
  heic_failed: th.uploads.heicFailed,
  image_unreadable: th.uploads.imageUnreadable,
  too_large_after_resize: th.uploads.tooLargeAfterResize,
}

/** ข้อความที่แถวไฟล์สำหรับข้อผิดพลาดตอนอัปโหลด (UX 7.1) */
function uploadMessage(error: AppError): { text: string; retryable: boolean } {
  if (error.code === 'download_budget_reached')
    return { text: th.uploads.budgetReached, retryable: true }
  if (error.code === 'upload_type_mismatch' || error.code === 'file_type_not_allowed')
    return { text: error.message, retryable: false }
  const ref = error.ref ? ` (${th.errors.reference(error.ref)})` : ''
  return { text: error.message + ref, retryable: true }
}

/** ไฟล์ที่นับรวมในชุด (ไม่นับไฟล์ที่ผิดพลาดตอนตรวจ/เตรียม) */
const counted = (item: FileItem) => item.status !== 'error' || item.retryable
const bytesOf = (item: FileItem) => item.prepared?.blob.size ?? 0

export function useFileField(
  target: FileFieldTarget,
  onAssetsChange?: (assetIds: string[]) => void,
  deps: UploadDeps = defaultUploadDeps,
) {
  const [items, setItems] = useState<FileItem[]>([])
  const itemsRef = useRef(items)
  const controllers = useRef(new Map<string, AbortController>())
  const targetRef = useRef(target)
  const mounted = useRef(true)

  useEffect(() => {
    targetRef.current = target
  })

  const commit = useCallback((next: (list: FileItem[]) => FileItem[]) => {
    itemsRef.current = next(itemsRef.current)
    if (mounted.current) setItems(itemsRef.current)
  }, [])
  const patch = useCallback(
    (id: string, change: Partial<FileItem>) =>
      commit((list) => list.map((x) => (x.id === id ? { ...x, ...change } : x))),
    [commit],
  )

  // ปิดหน้าแล้ว: ยกเลิกการอัปโหลดที่ค้าง และคืนหน่วยความจำของตัวอย่างรูป
  useEffect(() => {
    mounted.current = true
    const active = controllers.current
    return () => {
      mounted.current = false
      for (const c of active.values()) c.abort()
      for (const item of itemsRef.current) if (item.previewUrl) URL.revokeObjectURL(item.previewUrl)
    }
  }, [])

  const doneIds = items
    .filter((x) => x.status === 'done' && x.assetId)
    .map((x) => x.assetId as string)
  const doneKey = doneIds.join(',')
  const onChangeRef = useRef(onAssetsChange)
  useEffect(() => {
    onChangeRef.current = onAssetsChange
  })
  useEffect(() => {
    onChangeRef.current?.(doneKey ? doneKey.split(',') : [])
  }, [doneKey])

  const upload = useCallback(
    async (ids: string[]) => {
      const entries = itemsRef.current
        .filter((x) => ids.includes(x.id) && x.prepared)
        .map((x) => {
          const controller = new AbortController()
          controllers.current.set(x.id, controller)
          const prepared = x.prepared as PreparedFile
          return {
            id: x.id,
            blob: prepared.blob,
            name: prepared.name,
            type: prepared.type,
            signal: controller.signal,
          }
        })
      if (entries.length === 0) return
      for (const e of entries)
        patch(e.id, { status: 'uploading', progress: 0, error: undefined, retryable: false })
      const onEvent = (event: UploadEvent) => {
        switch (event.phase) {
          case 'uploading':
            patch(event.id, {
              status: 'uploading',
              progress: event.total > 0 ? event.loaded / event.total : 0,
            })
            break
          case 'completing':
            patch(event.id, { status: 'completing', progress: 1 })
            break
          case 'done':
            controllers.current.delete(event.id)
            patch(event.id, { status: 'done', assetId: event.assetId })
            break
          case 'failed': {
            controllers.current.delete(event.id)
            const { text, retryable } = uploadMessage(event.error)
            patch(event.id, { status: 'error', error: text, retryable })
            break
          }
          case 'cancelled':
            controllers.current.delete(event.id)
            break
        }
      }
      const { purpose, classroomId, postId, adminMode } = targetRef.current
      // หนึ่งการเลือก/ลองใหม่ = หนึ่งชุด (request key ใหม่) — ลิงก์หมดอายุ uploadSet ขอซ้ำด้วย key เดิมเอง
      await uploadSet(
        entries,
        { purpose, classroomId, postId, adminMode },
        crypto.randomUUID(),
        deps,
        onEvent,
      )
    },
    [deps, patch],
  )

  const add = useCallback(
    async (files: File[]) => {
      let active = itemsRef.current.filter(counted).length
      const added: FileItem[] = files.map((file) => {
        const kind = kindOf(file)
        const base: FileItem = {
          id: crypto.randomUUID(),
          original: file,
          kind,
          name: file.name,
          status: 'preparing',
          progress: 0,
          retryable: false,
        }
        const code = checkOriginal(file)
        if (code === 'file_too_large')
          return {
            ...base,
            status: 'error',
            error: kind === 'pdf' ? th.uploads.pdfTooLarge : th.uploads.imageTooLarge,
          }
        if (code) return { ...base, status: 'error', error: th.errors[code] }
        if (checkSet(active + 1, 0)) {
          return { ...base, status: 'error', error: th.errors.too_many_files }
        }
        active++
        return base
      })
      commit((list) => [...list, ...added])

      // เตรียมทีละไฟล์ (รูปใหญ่หลายรูปพร้อมกันทำให้หน่วยความจำมือถือเต็ม)
      const ready: string[] = []
      for (const item of added) {
        if (item.status !== 'preparing' || !item.kind) continue
        if (!itemsRef.current.some((x) => x.id === item.id)) continue
        let prepared: PreparedFile
        try {
          prepared = await prepareFile(item.original, item.kind)
        } catch (e) {
          patch(item.id, {
            status: 'error',
            error:
              e instanceof PrepareError ? PREPARE_MESSAGE[e.reason] : th.uploads.imageUnreadable,
          })
          continue
        }
        // นำออกระหว่างเตรียม
        if (!itemsRef.current.some((x) => x.id === item.id)) continue
        const others = itemsRef.current.filter((x) => x.id !== item.id && counted(x))
        const code =
          checkPrepared(prepared.type, prepared.blob.size) ??
          checkSet(
            others.length + 1,
            others.reduce((n, x) => n + bytesOf(x), 0) + prepared.blob.size,
          )
        if (code) {
          patch(item.id, { status: 'error', name: prepared.name, error: th.errors[code] })
          continue
        }
        patch(item.id, {
          status: 'waiting',
          name: prepared.name,
          prepared,
          previewUrl:
            prepared.type === 'application/pdf' ? undefined : URL.createObjectURL(prepared.blob),
        })
        ready.push(item.id)
      }
      await upload(ready)
    },
    [commit, patch, upload],
  )

  const remove = useCallback(
    (id: string) => {
      controllers.current.get(id)?.abort()
      controllers.current.delete(id)
      const item = itemsRef.current.find((x) => x.id === id)
      if (item?.previewUrl) URL.revokeObjectURL(item.previewUrl)
      commit((list) => list.filter((x) => x.id !== id))
    },
    [commit],
  )

  const retry = useCallback(
    (id: string) => {
      const item = itemsRef.current.find((x) => x.id === id)
      if (!item || item.status !== 'error' || !item.retryable || !item.prepared) return
      void upload([id])
    },
    [upload],
  )

  const cancelAll = useCallback(() => {
    // ยกเลิกเฉพาะไฟล์ที่ยังส่งไม่จบ — ไฟล์ที่ขึ้นไปแล้วกำลังบันทึก (complete) ปล่อยให้จบ
    for (const item of itemsRef.current) {
      if (item.status !== 'uploading' && item.status !== 'waiting') continue
      controllers.current.get(item.id)?.abort()
      controllers.current.delete(item.id)
      patch(item.id, { status: 'error', error: th.uploads.cancelled, retryable: true })
    }
  }, [patch])

  const activeItems = items.filter(counted)
  const totalBytes = activeItems.reduce((n, x) => n + bytesOf(x), 0)
  return {
    items,
    count: activeItems.length,
    totalBytes,
    full: activeItems.length >= UPLOAD_LIMITS.maxFiles,
    largeSet: totalBytes > UPLOAD_LIMITS.largeSetHintBytes,
    busy: items.some((x) => ['preparing', 'waiting', 'uploading', 'completing'].includes(x.status)),
    uploading: items.some((x) => x.status === 'uploading'),
    assetIds: doneIds,
    add,
    remove,
    retry,
    cancelAll,
  }
}
