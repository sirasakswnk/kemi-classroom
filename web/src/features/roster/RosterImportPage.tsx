import { ArrowRight, Check, FileSpreadsheet, TriangleAlert, Upload } from 'lucide-react'
import { useEffect, useMemo, useRef, useState, type ChangeEvent } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import type { Json } from '../../lib/database.types'
import { supabase, toAppError, type AppError } from '../../lib/supabase'
import { Button, Card, Chip, Field, Input, Select, Steps, useToast, type StepItem } from '../../ui'
import { useTeacher } from '../teacher/teacherContext'
import {
  columnLetter,
  detectLayout,
  extractRows,
  guessGroupName,
  ROSTER_FIELDS,
  type ColumnMapping,
  type DetectedLayout,
  type RosterDraftRow,
  type RosterField,
} from './parseRoster'
import { PlanSchema, type Plan } from './plan'
import { readSheet, ROSTER_LIMITS, type SheetData } from './readSheet'
import styles from './RosterImportPage.module.css'
import {
  isCodeText,
  nameKey,
  rowLabel,
  spacingSuggestion,
  toPayload,
  validateRoster,
  type RosterIssue,
} from './validateRoster'

type FileErrorKind = keyof typeof th.roster.fileErrors
type Loaded = { fileName: string; sheet: SheetData; layout: DetectedLayout }

const FIELD_TO_INPUT: Record<RosterIssue['field'], keyof RosterDraftRow> = {
  roll: 'roll',
  code: 'code',
  first: 'first',
  last: 'last',
}

// T05 นำเข้ารายชื่อจาก Excel (UX_DESIGN ส่วน 10, TECHNICAL_DESIGN ส่วน 4)
// ไฟล์อ่านในเบราว์เซอร์เท่านั้น ส่งขึ้นเซิร์ฟเวอร์เฉพาะ 5 ช่องต่อคน
export function RosterImportPage() {
  const toast = useToast()
  // ผู้ดูแลในโหมดผู้ดูแลนำเข้าแทนครูได้ (L6) — RPC ต้องได้ p_admin_mode
  const { adminMode } = useTeacher()
  const fileInput = useRef<HTMLInputElement>(null)
  const [loaded, setLoaded] = useState<Loaded | null>(null)
  const [fileError, setFileError] = useState<FileErrorKind | null>(null)
  const [mapping, setMapping] = useState<ColumnMapping | null>(null)
  const [group, setGroup] = useState('')
  const [edits, setEdits] = useState<Record<number, Partial<RosterDraftRow>>>({})
  const [confirmed, setConfirmed] = useState<ReadonlySet<number>>(new Set())
  // ช่องชื่อที่ครูเลือกคงค่าเดิมแม้มีช่องว่างแทรก (nameKey) — ไม่แก้ชื่อให้เอง
  const [keptNames, setKeptNames] = useState<ReadonlySet<string>>(new Set())
  const [plan, setPlan] = useState<{
    key: string
    plan: Plan | null
    error: AppError | null
  } | null>(null)
  const [termName, setTermName] = useState('')
  const [committing, setCommitting] = useState(false)
  const [commitError, setCommitError] = useState<AppError | null>(null)
  const [done, setDone] = useState<Plan | null>(null)
  const requestKey = useRef<{ key: string; uuid: string } | null>(null)

  // ชื่อภาคเรียนปัจจุบัน (หัวหน้า)
  useEffect(() => {
    let active = true
    supabase
      .from('term_control')
      .select('terms(name)')
      .maybeSingle()
      .then(({ data }) => {
        const name = (data?.terms as { name?: string } | null)?.name
        if (active && name) setTermName(name)
      })
    return () => {
      active = false
    }
  }, [])

  const extracted = useMemo(
    () =>
      loaded && mapping ? extractRows(loaded.sheet, loaded.layout.dataStartRow, mapping) : null,
    [loaded, mapping],
  )
  // ค่าที่ครูพิมพ์แก้เก็บตามจริง (พิมพ์ช่องว่างกลางชื่อได้) แล้วตัดช่องว่างหัวท้ายตอนตรวจ/ส่ง
  const rows = useMemo<RosterDraftRow[]>(
    () =>
      (extracted?.rows ?? []).map((r, i) => {
        const edited = edits[i] ?? {}
        const trimmed = Object.fromEntries(
          Object.entries(edited).map(([k, v]) => [k, typeof v === 'string' ? v.trim() : v]),
        )
        return { ...r, ...trimmed }
      }),
    [extracted, edits],
  )
  const clientIssues = useMemo(
    () => validateRoster(rows, confirmed, keptNames),
    [rows, confirmed, keptNames],
  )
  // รายการที่ต้องแก้จากไฟล์ตอนแรก — ยังแสดงต่อเมื่อแก้แล้ว (ช่องไม่หายระหว่างพิมพ์ โฟกัสไม่หลุด)
  const initialIssues = useMemo(() => validateRoster(extracted?.rows ?? []), [extracted])
  const payload = useMemo(() => toPayload(rows), [rows])
  const groupName = group.trim()
  const previewKey = JSON.stringify([groupName, payload])
  const canPreview =
    rows.length > 0 && clientIssues.length === 0 && groupName.length > 0 && groupName.length <= 30

  // ตรวจกับรายชื่อในระบบเมื่อไม่มีข้อผิดพลาดฝั่งเครื่องแล้ว (หน่วงเล็กน้อยระหว่างครูพิมพ์แก้)
  useEffect(() => {
    if (!canPreview || done) return
    let active = true
    const timer = setTimeout(() => {
      supabase
        .rpc('preview_roster_import', {
          p_group_name: groupName,
          p_rows: payload as unknown as Json,
          p_admin_mode: adminMode,
        })
        .then(({ data, error }) => {
          if (!active) return
          if (error) return setPlan({ key: previewKey, plan: null, error: toAppError(error) })
          const parsed = PlanSchema.safeParse(data)
          setPlan(
            parsed.success
              ? { key: previewKey, plan: parsed.data, error: null }
              : { key: previewKey, plan: null, error: toAppError({ name: 'InvalidPlan' }) },
          )
        })
    }, 400)
    return () => {
      active = false
      clearTimeout(timer)
    }
  }, [canPreview, done, groupName, payload, previewKey, adminMode])

  const currentPlan = canPreview && plan?.key === previewKey ? plan : null
  const checking = canPreview && !currentPlan
  // ข้อผิดพลาดจากเซิร์ฟเวอร์รายแถว (เลขที่ชนกับคนในห้องที่ไม่อยู่ในไฟล์)
  const serverIssues: RosterIssue[] = (currentPlan?.plan?.rows ?? []).flatMap((r) =>
    r.errors.includes('roll_taken')
      ? [
          {
            index: r.index,
            field: 'roll',
            kind: 'roll_taken',
            message: th.roster.issues.roll_taken,
            confirmable: false,
          } as RosterIssue,
        ]
      : [],
  )
  const issues = [...clientIssues, ...serverIssues]
  const ready = !!currentPlan?.plan?.ok && issues.length === 0
  const slotKey = (i: Pick<RosterIssue, 'index' | 'field'>) => `${i.index}:${i.field}`
  const slots = [
    ...new Map([...initialIssues, ...issues].map((i) => [slotKey(i), i])).values(),
  ].sort(
    (a, b) => a.index - b.index || ROSTER_FIELDS.indexOf(a.field) - ROSTER_FIELDS.indexOf(b.field),
  )

  const resetFile = () => {
    setLoaded(null)
    setMapping(null)
    setEdits({})
    setConfirmed(new Set())
    setKeptNames(new Set())
    setPlan(null)
    setDone(null)
    setCommitError(null)
    setFileError(null)
  }

  const onFile = async (e: ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    resetFile()
    if (file.size > ROSTER_LIMITS.maxFileBytes) return setFileError('too_big')
    try {
      const sheet = await readSheet(await file.arrayBuffer())
      const layout = detectLayout(sheet)
      if (!layout) return setFileError('no_header')
      setLoaded({ fileName: file.name, sheet, layout })
      setMapping(layout.mapping)
      setGroup(guessGroupName(file.name))
    } catch {
      setFileError('unreadable')
    }
  }

  const setColumn = (field: RosterField, value: string) => {
    if (!mapping) return
    setMapping({ ...mapping, [field]: value === '' ? null : Number(value) })
    setEdits({})
    setConfirmed(new Set())
    setKeptNames(new Set())
  }

  const editRow = (index: number, field: keyof RosterDraftRow, value: string) => {
    setEdits((prev) => ({ ...prev, [index]: { ...prev[index], [field]: value } }))
    if (field === 'code') setConfirmed((prev) => new Set([...prev].filter((i) => i !== index)))
    // แก้ชื่อแล้ว การเลือก “คงค่าเดิม” ของช่องนั้นไม่ใช้แล้ว
    if (field === 'first' || field === 'last') {
      const key = nameKey(index, field)
      setKeptNames((prev) => new Set([...prev].filter((k) => k !== key)))
    }
  }

  const keepName = (index: number, field: 'first' | 'last', keep: boolean) =>
    setKeptNames((prev) => {
      const next = new Set(prev)
      if (keep) next.add(nameKey(index, field))
      else next.delete(nameKey(index, field))
      return next
    })

  const commit = async () => {
    if (!ready) return
    if (requestKey.current?.key !== previewKey)
      requestKey.current = { key: previewKey, uuid: crypto.randomUUID() }
    setCommitting(true)
    setCommitError(null)
    const { data, error } = await supabase.rpc('commit_roster_import', {
      p_group_name: groupName,
      p_rows: payload as unknown as Json,
      p_request_key: requestKey.current.uuid,
      p_admin_mode: adminMode,
    })
    setCommitting(false)
    if (error) return setCommitError(toAppError(error))
    const parsed = PlanSchema.safeParse(data)
    if (!parsed.success) return setCommitError(toAppError({ name: 'InvalidPlan' }))
    if (!parsed.data.committed) {
      setPlan({ key: previewKey, plan: parsed.data, error: null })
      return
    }
    setDone(parsed.data)
    toast(th.roster.done(parsed.data.counts?.rows ?? rows.length, parsed.data.group_name))
  }

  const step = done ? 4 : !loaded ? 0 : issues.length > 0 || checking || !ready ? 2 : 3
  const steps: StepItem[] = th.roster.steps.map((label, i) => ({
    label,
    state: i < step ? 'done' : i === step ? 'now' : 'todo',
    icon:
      i === step
        ? [
            <FileSpreadsheet key="f" />,
            <ArrowRight key="a" />,
            <TriangleAlert key="t" />,
            <Upload key="u" />,
          ][i]
        : undefined,
  }))

  const statusChip = (index: number) => {
    if (issues.some((i) => i.index === index))
      return (
        <Chip tone="red" icon={<TriangleAlert />}>
          {th.roster.status.error}
        </Chip>
      )
    const row = currentPlan?.plan?.rows.find((r) => r.index === index)
    if (!row) return <Chip tone="plain">{th.roster.status.pending}</Chip>
    const s = th.roster.status
    switch (row.status) {
      case 'new':
        return <Chip tone="purple">{s.new}</Chip>
      case 'added':
        return <Chip tone="purple">{s.added}</Chip>
      case 'moved':
        return <Chip tone="amber">{s.moved(row.from_group ?? '')}</Chip>
      case 'updated':
        return (
          <Chip tone="amber">
            {s.updated} ·{' '}
            {row.changes
              .map((c) => th.roster.changes[c as keyof typeof th.roster.changes] ?? c)
              .join(', ')}
          </Chip>
        )
      case 'unchanged':
        return <Chip tone="plain">{s.unchanged}</Chip>
      default:
        return <Chip tone="red">{s.error}</Chip>
    }
  }

  const missing = currentPlan?.plan?.missing ?? []
  const serverTopErrors = currentPlan?.plan?.errors ?? []

  return (
    <div className={styles.page}>
      <header className={styles.head}>
        {termName && <p className={styles.eyebrow}>{th.roster.eyebrow(termName)}</p>}
        <h1>{th.roster.title}</h1>
        <p className={styles.intro}>{th.roster.intro}</p>
      </header>

      <Steps label={th.roster.stepsLabel} steps={steps} className={styles.steps} />

      {done ? (
        <Card as="section" padding="lg" className={styles.panel}>
          <h2>
            <Check aria-hidden="true" className={styles.okIcon} />
            {th.roster.done(done.counts?.rows ?? 0, done.group_name)}
          </h2>
          <p className={styles.muted}>{th.roster.footNote}</p>
          <div className={styles.actions}>
            <Button onClick={resetFile} variant="soft">
              {th.roster.importAnother}
            </Button>
          </div>
        </Card>
      ) : (
        <>
          <div className={styles.grid}>
            <Card as="section" className={styles.panel} aria-labelledby="imp-file-title">
              <h2 id="imp-file-title">{th.roster.columnsTitle}</h2>
              <input
                ref={fileInput}
                type="file"
                accept=".xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                className="sr-only"
                tabIndex={-1}
                aria-hidden="true"
                onChange={onFile}
              />
              {loaded ? (
                <div className={styles.fileChip}>
                  <span className={styles.fileIcon} aria-hidden="true">
                    <FileSpreadsheet />
                  </span>
                  <span className={styles.fileText}>
                    <b>{loaded.fileName}</b>
                    <small>{th.roster.fileSummary(rows.length, loaded.sheet.sheetCount)}</small>
                  </span>
                  <Button size="sm" variant="ghost" onClick={() => fileInput.current?.click()}>
                    {th.roster.changeFile}
                  </Button>
                </div>
              ) : (
                <Button icon={<FileSpreadsheet />} onClick={() => fileInput.current?.click()}>
                  {th.roster.chooseFile}
                </Button>
              )}
              <p className={styles.hint}>{th.roster.fileHint}</p>
              {fileError && (
                <p className={styles.alert} role="alert">
                  <TriangleAlert aria-hidden="true" />
                  <span>{th.roster.fileErrors[fileError]}</span>
                </p>
              )}
              {extracted?.tooMany && (
                <p className={styles.alert} role="alert">
                  <TriangleAlert aria-hidden="true" />
                  <span>{th.roster.fileErrors.too_many}</span>
                </p>
              )}
              {loaded && extracted && rows.length === 0 && (
                <p className={styles.alert} role="alert">
                  <TriangleAlert aria-hidden="true" />
                  <span>{th.roster.fileErrors.no_rows}</span>
                </p>
              )}

              {loaded && mapping && (
                <>
                  <Field
                    label={th.roster.group}
                    hint={th.roster.groupHint}
                    error={
                      serverTopErrors.includes('group_invalid') ||
                      (groupName === '' && rows.length > 0)
                        ? th.roster.serverErrors.group_invalid
                        : undefined
                    }
                  >
                    <Input
                      value={group}
                      onChange={(e) => setGroup(e.target.value)}
                      maxLength={30}
                      autoComplete="off"
                    />
                  </Field>
                  <fieldset className={styles.mapping}>
                    <legend className={styles.lbl}>{th.roster.columnsLabel}</legend>
                    {ROSTER_FIELDS.map((field) => (
                      <Field key={field} label={th.roster.fields[field]}>
                        <Select
                          value={mapping[field] ?? ''}
                          onChange={(e) => setColumn(field, e.target.value)}
                        >
                          <option value="">{th.roster.notUsed}</option>
                          {loaded.layout.headers.map((header, col) => (
                            <option key={col} value={col}>
                              {th.roster.column(columnLetter(col), header)}
                            </option>
                          ))}
                        </Select>
                      </Field>
                    ))}
                  </fieldset>
                  <p className={styles.hint}>{th.roster.onlyFive}</p>
                </>
              )}
            </Card>

            <Card as="section" className={styles.panel} aria-labelledby="imp-issues-title">
              <div className={styles.sectionHead}>
                <h2 id="imp-issues-title">{th.roster.issuesTitle}</h2>
                {loaded && (
                  <Chip
                    tone={issues.length === 0 ? 'green' : 'amber'}
                    icon={issues.length === 0 ? <Check /> : <TriangleAlert />}
                  >
                    {th.roster.issuesDone(issues.length)}
                  </Chip>
                )}
              </div>
              {loaded && slots.length === 0 && <p className={styles.muted}>{th.roster.noIssues}</p>}
              <ul className={styles.issues}>
                {slots.map((slot) => {
                  const issue = issues.find((i) => slotKey(i) === slotKey(slot))
                  const row = rows[slot.index]
                  const input = FIELD_TO_INPUT[slot.field]
                  const raw =
                    (edits[slot.index]?.[input] as string | undefined) ?? (row[input] as string)
                  return (
                    <li
                      key={slotKey(slot)}
                      className={styles.issue}
                      data-ok={issue ? undefined : 'true'}
                    >
                      <span className={styles.issueIcon} aria-hidden="true">
                        {issue ? <TriangleAlert /> : <Check />}
                      </span>
                      <Field
                        label={`${rowLabel(row)} · ${th.roster.fields[slot.field]}`}
                        error={issue?.message}
                        hint={issue ? undefined : th.roster.fixed}
                      >
                        <Input
                          value={raw}
                          onChange={(e) => editRow(slot.index, input, e.target.value)}
                          inputMode={
                            slot.field === 'roll' || slot.field === 'code' ? 'numeric' : undefined
                          }
                          autoComplete="off"
                          className={styles.fixInput}
                        />
                      </Field>
                      {slot.kind === 'name_spacing' &&
                        (slot.field === 'first' || slot.field === 'last') &&
                        (() => {
                          const field = slot.field
                          const suggestion = spacingSuggestion(row[field])
                          const kept = keptNames.has(nameKey(slot.index, field))
                          if (!suggestion && !kept) return null
                          return (
                            <div className={styles.nameChoice}>
                              {suggestion && !kept && (
                                <Button
                                  variant="soft"
                                  size="sm"
                                  onClick={() => editRow(slot.index, field, suggestion)}
                                >
                                  {th.roster.useSuggestion(suggestion)}
                                </Button>
                              )}
                              <label className={styles.confirm}>
                                <input
                                  type="checkbox"
                                  checked={kept}
                                  onChange={(e) => keepName(slot.index, field, e.target.checked)}
                                />
                                {th.roster.keepName}
                              </label>
                            </div>
                          )
                        })()}
                      {slot.kind === 'code_length' && isCodeText(row.code) && (
                        <label className={styles.confirm}>
                          <input
                            type="checkbox"
                            checked={confirmed.has(slot.index)}
                            onChange={(e) =>
                              setConfirmed((prev) => {
                                const next = new Set(prev)
                                if (e.target.checked) next.add(slot.index)
                                else next.delete(slot.index)
                                return next
                              })
                            }
                          />
                          {th.roster.confirmCode}
                        </label>
                      )}
                    </li>
                  )
                })}
              </ul>
            </Card>
          </div>

          {rows.length > 0 && (
            <Card
              as="section"
              padding="none"
              className={styles.tableCard}
              aria-labelledby="imp-table-title"
            >
              <div className={styles.tableBar}>
                <h2 id="imp-table-title">{th.roster.previewTitle}</h2>
                <span className={styles.muted} role="status">
                  {checking ? th.roster.checking : th.roster.previewCount(rows.length)}
                </span>
              </div>
              <div className={styles.tableWrap}>
                <table className={styles.table}>
                  <thead>
                    <tr>
                      <th scope="col">{th.roster.table.roll}</th>
                      <th scope="col">{th.roster.table.name}</th>
                      <th scope="col">{th.roster.table.code}</th>
                      <th scope="col">{th.roster.table.result}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r, i) => (
                      <tr key={r.sourceRow}>
                        <td className="num">{r.roll}</td>
                        <td>{[r.prefix, r.first, r.last].filter(Boolean).join(' ')}</td>
                        <td className="num">{r.code}</td>
                        <td>
                          <span className={styles.chips}>
                            {statusChip(i)}
                            {currentPlan?.plan?.rows.find((p) => p.index === i)?.bound && (
                              <Chip tone="plain">{th.roster.bound}</Chip>
                            )}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {missing.length > 0 && (
                <details className={styles.missing}>
                  <summary>{th.roster.missingTitle(missing.length)}</summary>
                  <ul>
                    {missing.map((m) => (
                      <li key={m.student_code}>
                        <span className="num">{m.roll_number}</span> {m.display_name}
                      </li>
                    ))}
                  </ul>
                </details>
              )}
            </Card>
          )}

          <div className={styles.foot}>
            <span className={styles.footNote}>{th.roster.footNote}</span>
            {(commitError ||
              currentPlan?.error ||
              serverTopErrors.some((e) => e !== 'group_invalid')) && (
              <p className={styles.alert} role="alert">
                <TriangleAlert aria-hidden="true" />
                <span>
                  {commitError?.message ??
                    currentPlan?.error?.message ??
                    serverTopErrors
                      .filter((e) => e !== 'group_invalid')
                      .map(
                        (e) =>
                          th.roster.serverErrors[e as keyof typeof th.roster.serverErrors] ?? e,
                      )
                      .join(' ')}
                  {(commitError?.ref ?? currentPlan?.error?.ref) && (
                    <small className={styles.ref}>
                      {' '}
                      {th.errors.reference((commitError?.ref ?? currentPlan?.error?.ref)!)}
                    </small>
                  )}
                </span>
              </p>
            )}
            <Link to="/t/roster" className={styles.cancel}>
              {th.roster.cancel}
            </Link>
            <Button
              icon={<Upload />}
              onClick={commit}
              disabled={!ready || committing}
              aria-busy={committing || undefined}
            >
              {committing ? th.roster.committing : th.roster.commit(rows.length)}
            </Button>
          </div>
        </>
      )}
    </div>
  )
}
