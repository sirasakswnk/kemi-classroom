import { useQuery, useQueryClient } from '@tanstack/react-query'
import type { PDFDocumentLoadingTask, PDFDocumentProxy, RenderTask } from 'pdfjs-dist'
import {
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  RotateCcw,
  RotateCw,
  TriangleAlert,
  ZoomIn,
  ZoomOut,
} from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { th } from '../../copy/th'
import { loadSignedFile, signedFileKey, signedFileOptions } from '../../lib/files'
import { appErrorOf } from '../../lib/request'
import type { AttachmentRef } from '../uploads/AttachmentList'
import styles from './review.module.css'

// ตัวดูไฟล์ของหน้าตรวจ (P4-04b/c, TECHNICAL_DESIGN 9.3): โหลดเฉพาะไฟล์ที่กำลังดู ไม่โหลดล่วงหน้า ไม่มีรูปย่อจาก B2
// Blob ของไฟล์เก็บใน cache ของ TanStack Query (5 นาที) และลิงก์ลงลายเซ็นใช้ตลอดอายุ — สลับไฟล์ ซูม หมุน
// เปลี่ยนหน้า PDF ไม่โหลดจาก B2 ซ้ำ; PDF แสดงด้วย pdf.js (โหลดเมื่อเปิด PDF ครั้งแรก, worker จาก origin เดียวกันตาม CSP)

const ZOOMS = [0.5, 0.75, 1, 1.25, 1.5, 2, 2.5, 3]
const copy = th.review.viewer

function useFileBlob(file: AttachmentRef) {
  const queryClient = useQueryClient()
  const blob = useQuery({
    queryKey: ['file-blob', file.asset_id],
    queryFn: async () =>
      loadSignedFile(await queryClient.fetchQuery(signedFileOptions(file.asset_id, 'view'))),
    staleTime: Infinity,
    gcTime: 5 * 60_000,
    retry: false,
  })
  const retry = () => {
    // ลิงก์อาจหมดอายุ (b2_403) — ขอลิงก์ใหม่แล้วโหลดอีกครั้ง
    void queryClient.invalidateQueries({ queryKey: signedFileKey(file.asset_id, 'view') })
    void blob.refetch()
  }
  return { blob, retry }
}

/**
 * เปิด PDF ด้วยตัวดูของเบราว์เซอร์ในแท็บใหม่ — ใช้ลิงก์ลงลายเซ็นตัวเดียวกับที่ตัวดูโหลดไว้ (คิวรีเดียวกัน
 * ลิงก์ยังไม่ใกล้หมดอายุจึงไม่ขอใหม่และไม่นับงบเพิ่ม); เปิดแท็บก่อน await กันตัวบล็อกป๊อปอัป
 */
function OpenOriginal({ file }: { file: AttachmentRef }) {
  const queryClient = useQueryClient()
  const open = async () => {
    const win = window.open('', '_blank')
    try {
      const signed = await queryClient.fetchQuery(signedFileOptions(file.asset_id, 'view'))
      if (win) {
        win.opener = null
        win.location.replace(signed.url)
      } else {
        window.open(signed.url, '_blank', 'noopener')
      }
    } catch {
      win?.close()
    }
  }
  return (
    <button type="button" className={styles.vt} onClick={() => void open()}>
      <ExternalLink aria-hidden="true" />
      {copy.openOriginal}
    </button>
  )
}

function LoadError({ error, onRetry }: { error: unknown; onRetry: () => void }) {
  const e = appErrorOf(error)
  return (
    <p className={styles.error} role="alert">
      <TriangleAlert aria-hidden="true" />
      <span>
        {e.message}
        {e.ref && ` (${th.errors.reference(e.ref)})`}
      </span>
      <button type="button" className={styles.vt} onClick={onRetry}>
        <RotateCcw aria-hidden="true" />
        {copy.retry}
      </button>
    </p>
  )
}

interface ToolsProps {
  zoom: number
  setZoom: (z: number) => void
  onRotate: () => void
  rotateLabel: string
  children?: React.ReactNode
}

function Tools({ zoom, setZoom, onRotate, rotateLabel, children }: ToolsProps) {
  const at = ZOOMS.indexOf(zoom)
  return (
    <div className={styles.tools} role="toolbar" aria-label={copy.toolsAria}>
      <button
        type="button"
        className={styles.vt}
        aria-label={copy.zoomOut}
        disabled={at <= 0}
        onClick={() => setZoom(ZOOMS[at - 1] ?? zoom)}
      >
        <ZoomOut aria-hidden="true" />
      </button>
      <span className={styles.pct} aria-live="polite">
        {Math.round(zoom * 100)}%
      </span>
      <button
        type="button"
        className={styles.vt}
        aria-label={copy.zoomIn}
        disabled={at >= ZOOMS.length - 1}
        onClick={() => setZoom(ZOOMS[at + 1] ?? zoom)}
      >
        <ZoomIn aria-hidden="true" />
      </button>
      <button type="button" className={styles.vt} aria-label={rotateLabel} onClick={onRotate}>
        <RotateCw aria-hidden="true" />
      </button>
      {children}
    </div>
  )
}

/** รูป: แสดงจาก object URL ของ Blob ที่โหลดไว้; ซูมด้วยขนาดภาพ หมุนทีละ 90° */
export function ImagePane({ file, owner }: { file: AttachmentRef; owner: string }) {
  const { blob, retry } = useFileBlob(file)
  const [zoom, setZoom] = useState(1)
  const [rotation, setRotation] = useState(0)
  // object URL ผูกกับ <img> ตรง ๆ — สร้างเมื่อได้ Blob และคืนเมื่อเปลี่ยนไฟล์/ปิดตัวดู
  const imgRef = useRef<HTMLImageElement>(null)
  useEffect(() => {
    const img = imgRef.current
    if (!blob.data || !img) return
    const url = URL.createObjectURL(blob.data)
    img.src = url
    return () => {
      img.removeAttribute('src')
      URL.revokeObjectURL(url)
    }
  }, [blob.data])

  if (blob.isError) return <LoadError error={blob.error} onRetry={retry} />
  if (!blob.data) {
    return (
      <p role="status" className={styles.muted}>
        {copy.loading}
      </p>
    )
  }
  const sideways = rotation % 180 !== 0
  return (
    <div className={styles.pane}>
      <Tools
        zoom={zoom}
        setZoom={setZoom}
        rotateLabel={copy.rotate}
        onRotate={() => setRotation((r) => (r + 90) % 360)}
      />
      <div className={styles.scroller} data-zoomed={zoom > 1 || sideways || undefined}>
        <img
          ref={imgRef}
          alt={copy.imageAlt(owner, file.file_name)}
          className={styles.zoomImg}
          style={{
            // ซูมด้วยความกว้าง (เลื่อนดูได้) — หมุนด้วย transform; แนวตั้ง↔แนวนอนสลับด้านจำกัดขนาด
            // หมุนข้าง: ลดความกว้างให้ด้านยาวของรูปถ่ายแนวตั้ง (≈ 4:3) ยังอยู่ในกรอบ
            width: `${zoom * (sideways ? 60 : 100)}%`,
            maxWidth: zoom === 1 && !sideways ? '100%' : 'none',
            transform: rotation ? `rotate(${rotation}deg)` : undefined,
          }}
        />
      </div>
    </div>
  )
}

/** PDF: วาดทีละหน้าลง canvas (หน้าที่เปิดอยู่เท่านั้น) — ซูม หมุน เปลี่ยนหน้า */
export function PdfPane({ file, owner }: { file: AttachmentRef; owner: string }) {
  const { blob, retry } = useFileBlob(file)
  const [doc, setDoc] = useState<PDFDocumentProxy | null>(null)
  const [openError, setOpenError] = useState(false)
  const [page, setPage] = useState(1)
  const [zoom, setZoom] = useState(1)
  const [rotation, setRotation] = useState(0)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const boxRef = useRef<HTMLDivElement>(null)

  // เปิดเอกสารจาก Blob ในหน่วยความจำ (ไม่ขอ Range จาก B2) แล้วคืนทรัพยากรเมื่อเปลี่ยนไฟล์
  useEffect(() => {
    if (!blob.data) return
    let cancelled = false
    let task: PDFDocumentLoadingTask | null = null
    void (async () => {
      try {
        const { openDocument } = await import('./pdfjs')
        const data = new Uint8Array(await blob.data.arrayBuffer())
        if (cancelled) return
        task = openDocument(data)
        const opened = await task.promise
        if (!cancelled) setDoc(opened)
      } catch {
        if (!cancelled) setOpenError(true)
      }
    })()
    return () => {
      cancelled = true
      setDoc(null)
      void task?.destroy()
    }
  }, [blob.data])

  // วาดหน้าที่เปิดอยู่: กว้างพอดีกรอบที่ 100% แล้วคูณซูม; คมตามความละเอียดจอ
  useEffect(() => {
    const canvas = canvasRef.current
    const box = boxRef.current
    if (!doc || !canvas || !box) return
    let task: RenderTask | null = null
    let cancelled = false
    void (async () => {
      const pdfPage = await doc.getPage(page)
      if (cancelled) return
      const base = pdfPage.getViewport({ scale: 1, rotation })
      const fit = Math.max(200, box.clientWidth - 24) / base.width
      const viewport = pdfPage.getViewport({ scale: fit * zoom, rotation })
      const ratio = Math.min(window.devicePixelRatio || 1, 2)
      canvas.width = Math.floor(viewport.width * ratio)
      canvas.height = Math.floor(viewport.height * ratio)
      canvas.style.width = `${Math.floor(viewport.width)}px`
      canvas.style.height = `${Math.floor(viewport.height)}px`
      task = pdfPage.render({
        canvas,
        viewport,
        transform: ratio !== 1 ? [ratio, 0, 0, ratio, 0, 0] : undefined,
      })
      await task.promise.catch(() => undefined)
    })()
    return () => {
      cancelled = true
      task?.cancel()
    }
  }, [doc, page, zoom, rotation])

  if (blob.isError) return <LoadError error={blob.error} onRetry={retry} />
  if (openError) {
    return (
      <p className={styles.error} role="alert">
        <TriangleAlert aria-hidden="true" />
        <span>{copy.pdfError}</span>
        <OpenOriginal file={file} />
      </p>
    )
  }
  if (!blob.data || !doc) {
    return (
      <p role="status" className={styles.muted}>
        {copy.pdfLoading}
      </p>
    )
  }
  const pages = doc.numPages
  return (
    <div className={styles.pane}>
      <Tools
        zoom={zoom}
        setZoom={setZoom}
        rotateLabel={copy.rotatePage}
        onRotate={() => setRotation((r) => (r + 90) % 360)}
      >
        <span className={styles.pageNav}>
          <button
            type="button"
            className={styles.vt}
            aria-label={copy.prevPage}
            disabled={page <= 1}
            onClick={() => setPage(page - 1)}
          >
            <ChevronLeft aria-hidden="true" />
          </button>
          <span aria-live="polite">{copy.pageOf(page, pages)}</span>
          <button
            type="button"
            className={styles.vt}
            aria-label={copy.nextPage}
            disabled={page >= pages}
            onClick={() => setPage(page + 1)}
          >
            <ChevronRight aria-hidden="true" />
          </button>
        </span>
        <OpenOriginal file={file} />
      </Tools>
      <div ref={boxRef} className={styles.scroller} data-zoomed={zoom > 1 || undefined}>
        <canvas
          ref={canvasRef}
          className={styles.pdfCanvas}
          role="img"
          aria-label={copy.pdfAlt(owner, file.file_name, page)}
        />
      </div>
    </div>
  )
}
