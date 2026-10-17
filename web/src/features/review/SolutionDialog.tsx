import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  BookOpenCheck,
  Check,
  Info,
  Lock,
  Pencil,
  RotateCcw,
  Send,
  TriangleAlert,
} from 'lucide-react'
import { useRef, useState } from 'react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { thaiDate, thaiTime } from '../../lib/thaiTime'
import { Button, Chip, Field, Modal, Textarea, useToast } from '../../ui'
import { applyScript, type ScriptKind } from '../posts/script'
import { AttachmentList } from '../uploads/AttachmentList'
import { FileField } from '../uploads/FileField'
import type { FileFieldState } from '../uploads/useFileField'
import type { Intake } from './api'
import {
  publishSolution,
  refreshAssignment,
  saveSolution,
  solutionQuery,
  type Solution,
} from './assignmentApi'
import styles from './dialogs.module.css'
import { useRequestKey } from './useRequestKey'

// M3 เฉลย (UX 8, แบบ v2 tModal solution): ยังไม่เผยแพร่ → ข้อความ (ปุ่มตัวห้อย/ตัวยก) + ไฟล์ 10 ไฟล์/20 MB
// + “บันทึกไว้ก่อน” และ “เผยแพร่เฉลย” (ปิดขณะยังเปิดรับ พร้อมคำอธิบายและปุ่มไป M2)
// เผยแพร่แล้ว → ดูเฉลย + เวลาเผยแพร่/แก้ล่าสุด → “แก้เฉลย” แล้ว “บันทึกการแก้ไข” (K4: คงเวลาเผยแพร่แรก)

const when = (iso: string) => `${thaiDate(iso)} ${thaiTime(iso)} น.`

interface Props {
  open: boolean
  onClose: () => void
  postId: string
  classroomId: string
  intake: Intake
  acceptAfterSolution: boolean
  adminMode: boolean
  onGoClose: () => void
}

export function SolutionDialog(props: Props) {
  const solution = useQuery({ ...solutionQuery(props.postId), enabled: props.open })
  const [editing, setEditing] = useState(false)
  if (!props.open) return null
  if (solution.isPending) {
    return (
      <Modal
        open
        onClose={props.onClose}
        icon={<BookOpenCheck />}
        title={th.workActions.solution.title}
      >
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </Modal>
    )
  }
  if (solution.isError) {
    const e = appErrorOf(solution.error)
    return (
      <Modal
        open
        onClose={props.onClose}
        icon={<BookOpenCheck />}
        title={th.workActions.solution.title}
      >
        <p className={styles.error} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{e.message}</span>
        </p>
      </Modal>
    )
  }
  const s = solution.data
  if (s?.publishedAt && !editing) {
    return <PublishedView {...props} solution={s} onEdit={() => setEditing(true)} />
  }
  // key ไม่ผูกกับรุ่นเฉลย: “โหลดข้อมูลล่าสุด” (stale_revision) เปลี่ยนแค่รุ่นที่ใช้บันทึก สิ่งที่พิมพ์ยังอยู่ (UX 7.1)
  return (
    <SolutionForm
      key={s?.publishedAt ? 'edit' : 'draft'}
      {...props}
      solution={s}
      onDone={() => {
        setEditing(false)
        props.onClose()
      }}
      onCancel={() => (editing ? setEditing(false) : props.onClose())}
    />
  )
}

function PublishedLine({ solution }: { solution: Solution }) {
  const copy = th.workActions.solution
  if (!solution.publishedAt) return null
  const edited = Date.parse(solution.updatedAt) > Date.parse(solution.publishedAt)
  return (
    <p className={styles.muted}>
      {copy.publishedAt(when(solution.publishedAt))}
      {edited && ` · ${copy.editedAt(when(solution.updatedAt))}`}
    </p>
  )
}

function PublishedView({
  onClose,
  solution,
  onEdit,
}: Props & { solution: Solution; onEdit: () => void }) {
  const copy = th.workActions.solution
  return (
    <Modal
      open
      onClose={onClose}
      icon={<BookOpenCheck />}
      title={copy.title}
      footer={
        <>
          <Button variant="ghost" onClick={onClose}>
            {th.workActions.closeDialog}
          </Button>
          <Button variant="soft" icon={<Pencil />} onClick={onEdit}>
            {copy.edit}
          </Button>
        </>
      }
    >
      <div className={styles.body}>
        <Chip tone="green" icon={<Check />} className={styles.start}>
          {copy.published}
        </Chip>
        {solution.body && <p className={styles.prose}>{solution.body}</p>}
        {solution.files.length > 0 && <AttachmentList files={solution.files} />}
        <PublishedLine solution={solution} />
      </div>
    </Modal>
  )
}

function SolutionForm({
  postId,
  classroomId,
  intake,
  acceptAfterSolution,
  adminMode,
  onGoClose,
  solution,
  onDone,
  onCancel,
}: Props & { solution: Solution | null; onDone: () => void; onCancel: () => void }) {
  const copy = th.workActions.solution
  const queryClient = useQueryClient()
  const toast = useToast()
  const saveKey = useRequestKey()
  const publishKey = useRequestKey()
  const published = !!solution?.publishedAt
  const [text, setText] = useState(solution?.body ?? '')
  const [files, setFiles] = useState<FileFieldState>(() => ({
    assetIds: solution?.files.map((f) => f.asset_id) ?? [],
    busy: false,
    hasErrors: false,
  }))
  const [error, setError] = useState<AppError | null>(null)
  const bodyRef = useRef<HTMLTextAreaElement>(null)
  const has = text.trim() !== '' || files.assetIds.length > 0
  const dirty =
    !solution ||
    text.trim() !== (solution.body ?? '') ||
    files.assetIds.join() !== solution.files.map((f) => f.asset_id).join()
  const closed = intake !== 'open'

  const applyScriptTo = (kind: ScriptKind) => {
    const box = bodyRef.current
    if (!box) return
    const result = applyScript(text, box.selectionStart ?? 0, box.selectionEnd ?? 0, kind)
    if (!result) {
      toast(th.posts.create.selectFirst)
      box.focus()
      return
    }
    setText(result.value)
    requestAnimationFrame(() => {
      box.focus()
      box.setSelectionRange(result.start, result.end)
    })
  }

  const save = async () => {
    const payload = { body: text, files: files.assetIds, expectedVersion: solution?.version ?? 0 }
    return saveSolution({
      postId,
      ...payload,
      requestKey: saveKey.keyFor(JSON.stringify(payload)),
      adminMode,
    })
  }

  const run = useMutation({
    mutationFn: async (action: 'save' | 'publish') => {
      let version = solution?.version ?? 0
      if (dirty) version = (await save()).version
      if (action === 'publish') {
        await publishSolution({
          postId,
          expectedVersion: version,
          requestKey: publishKey.keyFor(String(version)),
          adminMode,
        })
      }
      return action
    },
    onSuccess: async (action) => {
      toast(
        action === 'publish'
          ? copy.publishedToast
          : published
            ? copy.updatedToast
            : copy.savedToast,
        {
          tone: 'success',
        },
      )
      await refreshAssignment(queryClient, postId)
      onDone()
    },
    onError: (err) => {
      const e = appErrorOf(err)
      setError(e)
      // บันทึกร่างผ่านแล้วแต่เผยแพร่ไม่ผ่าน (เช่นยังเปิดรับ): โหลดรุ่นใหม่ให้กดครั้งต่อไปไม่เจอ stale_revision
      if (e.code !== 'stale_revision')
        void queryClient.invalidateQueries({ queryKey: ['solution', postId] })
    },
  })

  const reload = () => {
    setError(null)
    void queryClient.invalidateQueries({ queryKey: ['solution', postId] })
  }
  const fileCodes = ['post_file_unavailable', 'too_many_files', 'batch_too_large']
  const bodyCodes = ['post_body_too_long', 'post_body_required']
  const busy = run.isPending || files.busy

  return (
    <Modal
      open
      onClose={onCancel}
      icon={<BookOpenCheck />}
      title={published ? copy.editTitle : copy.title}
      footer={
        published ? (
          <>
            <Button variant="ghost" onClick={onCancel}>
              {th.workActions.cancel}
            </Button>
            <Button
              icon={<Check />}
              disabled={!has || !dirty || busy || files.hasErrors}
              onClick={() => run.mutate('save')}
            >
              {copy.saveEdit}
            </Button>
          </>
        ) : (
          <>
            <Button variant="ghost" onClick={onCancel}>
              {th.workActions.cancel}
            </Button>
            <Button
              variant="soft"
              disabled={!has || !dirty || busy || files.hasErrors}
              onClick={() => run.mutate('save')}
            >
              {copy.saveDraft}
            </Button>
            <Button
              icon={<Send />}
              disabled={!closed || !has || busy || files.hasErrors}
              onClick={() => run.mutate('publish')}
            >
              {copy.publish}
            </Button>
          </>
        )
      }
    >
      <div className={styles.body}>
        {published ? (
          <p className={styles.note}>
            <Info aria-hidden="true" />
            <span>{copy.editNote}</span>
          </p>
        ) : (
          <Chip tone="plain" className={styles.start}>
            {solution ? copy.draft : copy.none}
          </Chip>
        )}
        <Field
          label={copy.textLabel}
          error={error && bodyCodes.includes(error.code) ? error.message : undefined}
        >
          <div className={styles.toolRow}>
            {(['sub', 'sup'] as const).map((kind) => (
              <button
                key={kind}
                type="button"
                className={styles.tool}
                // ไม่ดึงโฟกัสออกจากช่องข้อความตอนกด (ช่วงที่เลือกยังอยู่)
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => applyScriptTo(kind)}
              >
                {th.posts.create[kind]}
              </button>
            ))}
          </div>
          <Textarea
            ref={bodyRef}
            rows={4}
            value={text}
            placeholder={copy.placeholder}
            onChange={(e) => setText(e.target.value)}
          />
        </Field>
        <FileField
          kind="solution"
          target={{ purpose: 'solution', classroomId, postId, adminMode }}
          initial={solution?.files}
          onChange={setFiles}
          error={error && fileCodes.includes(error.code) ? error.message : undefined}
        />
        {!published && (
          <div className={styles.kv}>
            <span>{copy.afterLabel}</span>
            <b>{acceptAfterSolution ? copy.afterYes : copy.afterNo}</b>
          </div>
        )}
        {!published && !closed && (
          <p className={styles.note} data-tone="amber">
            <Lock aria-hidden="true" />
            <span>{copy.mustClose}</span>
            <button type="button" className={styles.link} onClick={onGoClose}>
              {copy.goClose}
            </button>
          </p>
        )}
        {solution && <PublishedLine solution={solution} />}
        {!has && <p className={styles.muted}>{copy.emptyHint}</p>}
        {error && ![...fileCodes, ...bodyCodes].includes(error.code) && (
          <p className={styles.error} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>
              {error.message}
              {error.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
            {error.code === 'close_required' && (
              <button type="button" className={styles.link} onClick={onGoClose}>
                {copy.goClose}
              </button>
            )}
            {error.code === 'stale_revision' && (
              <Button size="sm" variant="ghost" icon={<RotateCcw />} onClick={reload}>
                {th.grading.reload}
              </Button>
            )}
          </p>
        )}
      </div>
    </Modal>
  )
}
