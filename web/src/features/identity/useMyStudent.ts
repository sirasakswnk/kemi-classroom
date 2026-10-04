import { useCallback, useEffect, useMemo, useState } from 'react'
import type { AppError } from '../../lib/supabase'
import { fetchMyStudent, type MyStudent } from './identity'

export type MyStudentState =
  | { status: 'loading' }
  | { status: 'ready'; student: MyStudent | null }
  | { status: 'error'; error: AppError }

type Loaded = { userId: string; key: number } & (
  { student: MyStudent | null } | { error: AppError }
)

// รายชื่อที่ผูกกับบัญชีนี้ (null = ยังไม่ผูก → เปิด A02) — โหลดใหม่ได้ และตั้งค่าเองได้หลังผูกสำเร็จ
export function useMyStudent(userId: string) {
  const [key, setKey] = useState(0)
  const [loaded, setLoaded] = useState<Loaded | null>(null)

  useEffect(() => {
    let active = true
    fetchMyStudent().then((outcome) => {
      if (!active) return
      setLoaded(
        outcome.ok ? { userId, key, student: outcome.data } : { userId, key, error: outcome.error },
      )
    })
    return () => {
      active = false
    }
  }, [userId, key])

  const state = useMemo<MyStudentState>(() => {
    if (!loaded || loaded.userId !== userId || loaded.key !== key) return { status: 'loading' }
    return 'error' in loaded
      ? { status: 'error', error: loaded.error }
      : { status: 'ready', student: loaded.student }
  }, [loaded, userId, key])

  const reload = useCallback(() => setKey((k) => k + 1), [])
  const setStudent = useCallback(
    (student: MyStudent) => setLoaded({ userId, key, student }),
    [userId, key],
  )

  return { state, reload, setStudent }
}
