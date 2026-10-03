import { useCallback } from 'react'
import { useSearchParams } from 'react-router'

/** แท็บที่เลือกเก็บใน URL (?tab=) — แชร์ลิงก์/กดย้อนกลับแล้วได้แท็บเดิม; ค่าที่ไม่รู้จักใช้ค่าเริ่มต้น */
export function useTabParam<K extends string>(
  keys: readonly K[],
  fallback: K,
): [K, (key: K) => void] {
  const [params, setParams] = useSearchParams()
  const value = params.get('tab')
  const tab = (keys as readonly string[]).includes(value ?? '') ? (value as K) : fallback
  const select = useCallback(
    (key: K) =>
      setParams(
        (p) => {
          const next = new URLSearchParams(p)
          next.set('tab', key)
          return next
        },
        { replace: true },
      ),
    [setParams],
  )
  return [tab, select]
}
