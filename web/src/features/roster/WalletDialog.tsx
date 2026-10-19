import { useMutation, useQueryClient } from '@tanstack/react-query'
import { Coins, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button, Modal, Stepper, useToast } from '../../ui'
import { walletAdjust, type RosterRow } from './rosterApi'
import styles from './RosterList.module.css'

// UX 9–10 ปรับโทเคนรายคน (แบบ v2 wallet-row เปิดเป็นหน้าต่างแทนแผงข้าง — UX 10 P5-03):
// ปุ่ม −/+ · ยอดหลังปรับ · ไม่มีเหตุผล/ประวัติ · ยอดต่ำสุด 0 · ส่งรุ่นยอดที่เห็นไปเทียบ (0036_wallet_ops)
// ยอดไม่พอ/รุ่นยอดเก่า: โหลดรายชื่อใหม่ก่อน แล้วแสดงข้อความพร้อมยอดล่าสุด (student มาจากผลรายชื่อล่าสุดเสมอ)
const MAX_DELTA = 1000

export function WalletDialog({
  student,
  term,
  adminMode,
  onClose,
}: {
  student: RosterRow
  term: string | undefined
  adminMode: boolean
  onClose: () => void
}) {
  const copy = th.rosterList.wallet
  const [delta, setDelta] = useState(0)
  const [error, setError] = useState<{ text: string; latest: boolean } | null>(null)
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const queryClient = useQueryClient()
  const toast = useToast()

  const balance = student.wallet_balance
  const after = balance + delta

  const save = useMutation({
    mutationFn: () => {
      const fingerprint = `${student.student_id}:${delta}:${student.wallet_version}`
      if (requestKey.current?.fingerprint !== fingerprint)
        requestKey.current = { fingerprint, key: crypto.randomUUID() }
      return walletAdjust({
        studentId: student.student_id,
        delta,
        expectedVersion: student.wallet_version,
        requestKey: requestKey.current.key,
        adminMode,
      })
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['roster-overview'] })
      toast(copy.done(student.display_name), { tone: 'success' })
      onClose()
    },
    onError: async (e) => {
      const app = appErrorOf(e)
      const latest = app.code === 'insufficient_balance' || app.code === 'stale_revision'
      if (latest) await queryClient.invalidateQueries({ queryKey: ['roster-overview'] })
      setError({
        text: app.message + (app.ref ? ` (${th.errors.reference(app.ref)})` : ''),
        latest,
      })
    },
  })

  const close = () => {
    if (!save.isPending) onClose()
  }

  return (
    <Modal
      open
      onClose={close}
      icon={<Coins />}
      title={copy.title(student.display_name)}
      description={term ? copy.term(term) : undefined}
      footer={
        <>
          <Button variant="ghost" disabled={save.isPending} onClick={close}>
            {th.rosterList.cancel}
          </Button>
          <Button
            disabled={save.isPending || delta === 0 || after < 0}
            onClick={() => {
              setError(null)
              save.mutate()
            }}
          >
            {save.isPending ? copy.saving : copy.save}
          </Button>
        </>
      }
    >
      <div className={styles.wallet}>
        <span className={styles.walletBalance}>
          <span>{copy.balance}</span>
          <b className="num">{balance}</b>
        </span>
        <Stepper
          value={delta}
          onChange={(v) => {
            setDelta(v)
            setError(null)
          }}
          label={copy.stepper}
          min={Math.max(-balance, -MAX_DELTA)}
          max={MAX_DELTA}
          format={(v) => (v > 0 ? `+${v}` : String(v))}
          disabled={save.isPending}
        />
      </div>
      {delta !== 0 && (
        <p className={styles.walletAfter} aria-live="polite">
          {copy.after} <b className="num">{after}</b> {copy.unit}
        </p>
      )}
      <p className={styles.walletHint}>{copy.hint}</p>
      {error && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{error.latest ? `${error.text} ${copy.latest(balance)}` : error.text}</span>
        </p>
      )}
    </Modal>
  )
}
