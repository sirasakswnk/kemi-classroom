import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Pencil, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf, run } from '../../lib/request'
import { supabase, type AppError } from '../../lib/supabase'
import { z } from '../../lib/zod'
import { Button, Chip, useToast } from '../../ui'
import styles from './grading.module.css'

// ปุ่ม “เปิดสิทธิ์แก้ไข 1 ครั้ง” ของ T03 (K3, UX 8, แบบ v2 g-actions) — แยกจากกล่องความคิดเห็น (การพิมพ์ว่าให้แก้ไม่เปิดสิทธิ์เอง)
// สิทธิ์ค้างอยู่แสดงชิป “มีสิทธิ์แก้ 1 ครั้ง · ยังไม่ใช้” แทนปุ่ม; นักเรียนส่งแก้สำเร็จแล้วสิทธิ์ถูกใช้ ครูเปิดใหม่ได้

const openKey = (submissionId: string) => ['revision-permission', submissionId] as const

function openPermissionQuery(submissionId: string) {
  return {
    queryKey: openKey(submissionId),
    queryFn: () =>
      run(
        supabase
          .from('revision_permissions')
          .select('id')
          .eq('submission_id', submissionId)
          .eq('status', 'open')
          .maybeSingle(),
        z.object({ id: z.uuid() }).nullable(),
      ),
  }
}

export function RevisionPermission({
  submissionId,
  postId,
  adminMode,
}: {
  submissionId: string
  postId: string
  adminMode: boolean
}) {
  const copy = th.grading.permission
  const queryClient = useQueryClient()
  const toast = useToast()
  const current = useQuery(openPermissionQuery(submissionId))
  const [error, setError] = useState<AppError | null>(null)
  const requestKey = useRef<string | null>(null)

  const open = useMutation({
    mutationFn: () => {
      requestKey.current ??= crypto.randomUUID()
      return run(
        supabase.rpc('open_revision_permission', {
          p_submission_id: submissionId,
          p_request_key: requestKey.current,
          p_admin_mode: adminMode,
        }),
        z.object({ permission_id: z.uuid(), already_open: z.boolean() }),
      )
    },
    onSuccess: async () => {
      requestKey.current = null
      setError(null)
      toast(copy.opened, { tone: 'success' })
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: openKey(submissionId) }),
        queryClient.invalidateQueries({ queryKey: ['submission-list', postId] }),
      ])
    },
    onError: (err) => setError(appErrorOf(err)),
  })

  if (current.isPending) return null
  return (
    <>
      {current.data ? (
        <Chip tone="purple" icon={<Pencil />} title={copy.hint}>
          {copy.open}
        </Chip>
      ) : (
        <Button
          type="button"
          variant="ghost"
          icon={<Pencil />}
          disabled={open.isPending}
          onClick={() => open.mutate()}
        >
          {copy.button}
        </Button>
      )}
      {error && (
        <p className={styles.error} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error.message}
            {error.ref && ` (${th.errors.reference(error.ref)})`}
          </span>
        </p>
      )}
    </>
  )
}
