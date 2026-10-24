import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { EllipsisVertical, Info, Maximize2, TriangleAlert, UserMinus, Users } from 'lucide-react'
import { useRef, useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { Button, Chip, MenuButton, Modal, useToast } from '../../ui'
import { initialOf as initialOfTeacher } from '../../lib/initial'
import { appErrorOf, membersQuery, removeMember, type Classroom, type Member } from './api'
import styles from './classrooms.module.css'
import { MemberCharm } from '../rewards/MemberCharm'

// แท็บสมาชิกของครู (UX 9): เฉพาะคนที่เข้าห้องแล้ว + ป้ายห้องตามรายชื่อ (เห็นคนที่เข้าผิดห้อง)
// แต่ละแถวมีเมนู “เอาออกจากชั้นเรียน” → กล่องยืนยัน; ลิงก์ไปดูคนที่ยังไม่เข้าใน T05
export function MembersPanel({
  classroom: c,
  termId,
  teacherName,
  adminMode,
  onOpenCode,
}: {
  classroom: Classroom
  termId: string | undefined
  teacherName: string
  adminMode: boolean
  onOpenCode: () => void
}) {
  const copy = th.classrooms.room
  const members = useQuery(membersQuery(c.id, termId))
  const [target, setTarget] = useState<Member | null>(null)
  const [removeError, setRemoveError] = useState<string | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const queryClient = useQueryClient()
  const toast = useToast()

  const remove = useMutation({
    mutationFn: (m: Member) => removeMember(c.id, m.student_id, adminMode),
    onSuccess: async (_result, m) => {
      setTarget(null)
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['members', c.id] }),
        queryClient.invalidateQueries({ queryKey: ['classroom', c.id] }),
        queryClient.invalidateQueries({ queryKey: ['classrooms'] }),
      ])
      toast(copy.removed(m.display_name), { tone: 'success' })
      // แถวที่เปิดเมนูหายไปแล้ว — ย้ายโฟกัสไปที่แผงของแท็บแทน
      rootRef.current?.closest<HTMLElement>('[role="tabpanel"]')?.focus()
    },
    onError: (error) => {
      const e = appErrorOf(error)
      setRemoveError(e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : ''))
    },
  })

  const ask = (m: Member) => {
    setRemoveError(null)
    setTarget(m)
  }

  if (members.isPending) {
    return (
      <p role="status" className={styles.muted}>
        {th.common.loading}
      </p>
    )
  }
  if (members.isError) {
    const e = appErrorOf(members.error)
    return (
      <p className={styles.alert} role="alert">
        <TriangleAlert aria-hidden="true" />
        <span>
          {e.message}
          {e.ref && ` (${th.errors.reference(e.ref)})`}
        </span>
      </p>
    )
  }

  const list = members.data
  return (
    <>
      <div className={styles.members} ref={rootRef}>
        <p className={styles.mGroup}>{copy.teacherGroup}</p>
        <div className={styles.mRow}>
          <span className={styles.mAvatar} aria-hidden="true">
            {initialOfTeacher(teacherName)}
          </span>
          <b className={styles.mName}>{teacherName}</b>
        </div>
        {list.length > 0 && (
          <>
            <p className={styles.mGroup}>{copy.studentsGroup(list.length)}</p>
            <ul className={styles.memGrid}>
              {list.map((m) => (
                <li key={m.student_id} className={styles.mRow}>
                  <span className={styles.mNo} aria-hidden="true">
                    {m.roll_number ?? '–'}
                  </span>
                  <span className={styles.mName}>
                    {m.display_name}
                    {m.roll_number !== null && (
                      <span className="sr-only">, {copy.roll(m.roll_number)}</span>
                    )}
                  </span>
                  {m.charm && <MemberCharm charm={m.charm} />}
                  {m.group_name ? (
                    <Chip tone="purple">{m.group_name}</Chip>
                  ) : (
                    <Chip tone="plain">{copy.notInRoster}</Chip>
                  )}
                  <MenuButton
                    label={copy.memberMenu(m.display_name)}
                    icon={<EllipsisVertical aria-hidden="true" />}
                    items={[
                      {
                        label: copy.remove,
                        icon: <UserMinus />,
                        tone: 'danger',
                        onSelect: () => ask(m),
                      },
                    ]}
                  />
                </li>
              ))}
            </ul>
          </>
        )}
      </div>

      {list.length === 0 && (
        <div className={styles.empty}>
          <Users aria-hidden="true" />
          <b>{copy.noMembersTitle}</b>
          {c.join_enabled ? (
            <>
              <span>{copy.noMembersBody(c.join_code)}</span>
              <button
                type="button"
                className={styles.codeChipSm}
                aria-label={copy.codeAria(c.join_code)}
                onClick={onOpenCode}
              >
                <b aria-hidden="true">{c.join_code}</b>
                <Maximize2 aria-hidden="true" />
              </button>
            </>
          ) : (
            <span>{copy.noMembersClosed}</span>
          )}
        </div>
      )}

      <p className={styles.note} data-tone="plain">
        <Info aria-hidden="true" />
        <span>
          {copy.notJoinedPrefix} <Link to="/t/roster?filter=notjoined">{copy.roster}</Link>
        </span>
      </p>

      <Modal
        open={target !== null}
        onClose={() => {
          if (!remove.isPending) setTarget(null)
        }}
        icon={<UserMinus />}
        title={target ? copy.removeTitle(target.display_name, c.name) : ''}
        description={copy.removeBody}
        footer={
          <>
            <Button variant="ghost" disabled={remove.isPending} onClick={() => setTarget(null)}>
              {copy.cancel}
            </Button>
            <Button
              variant="danger"
              icon={<UserMinus />}
              disabled={remove.isPending}
              onClick={() => target && remove.mutate(target)}
            >
              {remove.isPending ? copy.removing : copy.remove}
            </Button>
          </>
        }
      >
        {removeError && (
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{removeError}</span>
          </p>
        )}
      </Modal>
    </>
  )
}
