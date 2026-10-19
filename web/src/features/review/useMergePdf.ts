import { useQueryClient } from '@tanstack/react-query'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { downloadBlob } from '../../lib/download'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { useToast } from '../../ui'
import { submissionFilesQuery } from './api'
import { collectFileBlobs } from './collectFileBlobs'
import type { MergeResult } from './mergePdf'

// ปุ่ม “ดาวน์โหลด PDF” ของหน้าตรวจ (P4-08, UX 9): รวมทุกไฟล์ของชุดที่ส่งล่าสุดของนักเรียนคนที่เปิดอยู่ ในเครื่องครู
// ขั้นตอน: อ่านรายการไฟล์ล่าสุด → รวบรวมเนื้อไฟล์ (แคช/ลิงก์เดิมก่อน — collectFileBlobs) → รวมด้วย pdf-lib (lazy import)
//   → มี PDF ที่เปิดไม่ได้: ถามว่าจะรวมที่เหลือต่อไหม · ไม่มี: บันทึกไฟล์ทันที
// สถานะอยู่ที่หน้าตรวจ (ไม่หายตอนสลับไฟล์) และผูกกับงานส่งที่กำลังรวม — กดซ้ำไม่ได้ระหว่างทำ
export type MergeView =
  | { phase: 'idle' }
  | { phase: 'loading'; done: number; total: number }
  | { phase: 'merging'; done: number; total: number }
  | { phase: 'ask'; failed: string[]; pages: number }
  | { phase: 'none'; failed: string[] }
  | { phase: 'error'; error: AppError }

export interface Merge {
  view: MergeView
  busy: boolean
  fileName: string
  run: () => void
  /** รวมที่เหลือต่อ (หลังถาม) — บันทึกไฟล์ที่รวมไว้แล้ว */
  proceed: () => void
  dismiss: () => void
}

interface Held {
  submissionId: string
  view: MergeView
}

export function useMergePdf(submissionId: string, fileName: string): Merge {
  const queryClient = useQueryClient()
  const toast = useToast()
  const [held, setHeld] = useState<Held>({ submissionId, view: { phase: 'idle' } })
  const pending = useRef<MergeResult | null>(null)
  const running = useRef(false)
  // สถานะของงานส่งอื่น (สลับไปดูคนอื่น) ไม่ใช่ของหน้านี้
  const view: MergeView = held.submissionId === submissionId ? held.view : { phase: 'idle' }
  const set = (v: MergeView) => setHeld({ submissionId, view: v })
  const busy = view.phase === 'loading' || view.phase === 'merging'

  const save = (result: MergeResult) => {
    downloadBlob(fileName, new Blob([result.bytes as BlobPart], { type: 'application/pdf' }))
    toast(th.review.viewer.merge.done(fileName, result.pages), { tone: 'success' })
    pending.current = null
    set({ phase: 'idle' })
  }

  const run = () => {
    if (running.current) return
    running.current = true
    void (async () => {
      try {
        set({ phase: 'loading', done: 0, total: 0 })
        // รายการไฟล์ล่าสุดเสมอ (นักเรียนอาจส่งแก้ระหว่างที่ครูเปิดหน้าไว้)
        const files = await queryClient.fetchQuery({
          ...submissionFilesQuery(submissionId),
          staleTime: 0,
        })
        if (files.length === 0) {
          set({ phase: 'none', failed: [] })
          return
        }
        const blobs = await collectFileBlobs(queryClient, files, (done, total) =>
          set({ phase: 'loading', done, total }),
        )
        set({ phase: 'merging', done: 0, total: files.length })
        const inputs = await Promise.all(
          blobs.map(async (b, i) => ({
            name: files[i].file_name,
            contentType: files[i].content_type,
            bytes: new Uint8Array(await b.arrayBuffer()),
          })),
        )
        // pdf-lib โหลดเมื่อกดครั้งแรกเท่านั้น (ไม่อยู่ใน bundle หลัก)
        const { mergeToPdf } = await import('./mergePdf')
        const result = await mergeToPdf(inputs, (done, total) =>
          set({ phase: 'merging', done, total }),
        )
        if (result.pages === 0) {
          set({ phase: 'none', failed: result.failed })
        } else if (result.failed.length > 0) {
          pending.current = result
          set({ phase: 'ask', failed: result.failed, pages: result.pages })
        } else {
          save(result)
        }
      } catch (error) {
        set({ phase: 'error', error: appErrorOf(error) })
      } finally {
        running.current = false
      }
    })()
  }

  return {
    view,
    busy,
    fileName,
    run,
    proceed: () => {
      if (pending.current) save(pending.current)
    },
    dismiss: () => {
      pending.current = null
      set({ phase: 'idle' })
    },
  }
}
