import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, Download, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { thaiDate } from '../../lib/thaiTime'
import { Button, Chip, Select, useToast } from '../../ui'
import { PastTermChip } from '../classrooms/RoomTerm'
import { TeacherPage } from '../teacher/TeacherLayout'
import { gradeTableQuery, roomOptionsQuery, type GradeTable } from './api'
import { csvFileName, downloadCsv, gradeCsv } from './gradeCsv'
import {
  cellView,
  clampPage,
  PER_PAGE,
  pageCount,
  pageRows,
  tableTotals,
  termGroups,
  type CellView,
} from './gradebookState'
import styles from './gradebook.module.css'

// T04 ตารางคะแนน (UX 9; แบบ v2 tGradebook): แถวนักเรียน/คอลัมน์งานเรียงเก่า → ใหม่ คะแนนสุทธิหลังหักส่งช้า
// แยก “ยังไม่ส่ง” (ขีด) “รอตรวจ” (ป้ายเหลือง) “0” (ตัวเลขสีแดง) · เลื่อนเฉพาะพื้นที่ตาราง ชื่อติดซ้ายเมื่อเลื่อน
// เลือกภาคเรียน/ห้องแล้วส่งออก CSV (UTF-8 BOM) — โทเคนมากับระยะ 5
export default function GradebookPage() {
  const { classId = '' } = useParams()
  const copy = th.gradebook
  const table = useQuery(gradeTableQuery(classId))
  const rooms = useQuery(roomOptionsQuery)
  const room = rooms.data?.find((r) => r.id === classId)
  const roomName = room?.name ?? '…'
  const crumbs = [
    { label: th.teacher.overview, to: '/t' },
    { label: roomName, to: `/t/c/${classId}` },
    { label: copy.title },
  ]

  if (table.isPending) {
    return (
      <TeacherPage crumbs={crumbs}>
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      </TeacherPage>
    )
  }
  if (table.isError) {
    const error = appErrorOf(table.error)
    const missing = error.code === 'forbidden'
    return (
      <TeacherPage crumbs={crumbs}>
        <div className={styles.empty} role="alert">
          <TriangleAlert aria-hidden="true" />
          <b>{missing ? copy.notFound : copy.loadFailed}</b>
          {!missing && (
            <span>
              {error.message}
              {error.ref && ` (${th.errors.reference(error.ref)})`}
            </span>
          )}
          {missing ? (
            <Link to="/t" className={styles.softLink}>
              {th.classrooms.room.backToOverview}
            </Link>
          ) : (
            <Button size="sm" variant="soft" onClick={() => void table.refetch()}>
              {th.teacher.retry}
            </Button>
          )}
        </div>
      </TeacherPage>
    )
  }
  return (
    <TeacherPage crumbs={crumbs}>
      <Grid
        key={classId}
        table={table.data}
        classId={classId}
        roomName={roomName}
        termId={room?.term_id}
      />
    </TeacherPage>
  )
}

function Grid({
  table,
  classId,
  roomName,
  termId,
}: {
  table: GradeTable
  classId: string
  roomName: string
  termId: string | undefined
}) {
  const copy = th.gradebook
  const navigate = useNavigate()
  const toast = useToast()
  const rooms = useQuery(roomOptionsQuery)
  const [page, setPage] = useState(1)
  const groups = termGroups(rooms.data ?? [])
  const group = groups.find((g) => g.termId === table.term_id)
  const pages = pageCount(table.rows.length)
  const current = clampPage(page, table.rows.length)
  const rows = pageRows(table.rows, current)
  const totals = tableTotals(table)

  const exportCsv = () => {
    const file = csvFileName(roomName, table.term_name)
    downloadCsv(file, gradeCsv(table))
    toast(copy.exported(file), { tone: 'success' })
  }
  const goRoom = (id: string) => void navigate(`/t/c/${id}/grades`)

  return (
    <div className={styles.page}>
      <header className={styles.head}>
        <div>
          {table.term_name && <span className={styles.eyebrow}>{table.term_name}</span>}
          <PastTermChip termId={termId} />
          <h1>{copy.heading(roomName)}</h1>
          <p>{copy.lead}</p>
        </div>
        <div className={styles.actions}>
          <Button variant="primary" icon={<Download />} onClick={exportCsv}>
            {copy.export}
          </Button>
        </div>
      </header>

      {groups.length > 0 && (
        <div className={styles.pickers}>
          <label className={styles.picker}>
            <span>{copy.pickTerm}</span>
            <Select
              value={table.term_id}
              onChange={(e) => {
                const first = groups.find((g) => g.termId === e.target.value)?.rooms[0]
                if (first) goRoom(first.id)
              }}
            >
              {groups.map((g) => (
                <option key={g.termId} value={g.termId}>
                  {g.name}
                </option>
              ))}
            </Select>
          </label>
          <label className={styles.picker}>
            <span>{copy.pickRoom}</span>
            <Select value={classId} onChange={(e) => goRoom(e.target.value)}>
              {(group?.rooms ?? []).map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </Select>
          </label>
        </div>
      )}

      {table.assignments.length === 0 ? (
        <div className={styles.empty}>
          <b>{copy.noWorks}</b>
          <span>{copy.noWorksBody}</span>
          <Link to={`/t/c/${classId}`} className={styles.softLink}>
            {copy.backToRoom}
          </Link>
        </div>
      ) : table.rows.length === 0 ? (
        <div className={styles.empty}>
          <b>{copy.noStudents}</b>
        </div>
      ) : (
        <>
          <p className={styles.summary}>
            {copy.summary(totals.students, totals.assignments, totals.waiting)}
          </p>
          <div className={styles.card}>
            <div className={styles.wrap} role="region" aria-label={copy.tableAria} tabIndex={0}>
              <table className={styles.table}>
                <thead>
                  <tr>
                    <th scope="col">{copy.roll}</th>
                    <th scope="col">{copy.name}</th>
                    {table.assignments.map((a) => (
                      <th scope="col" key={a.post_id}>
                        <b>{a.title}</b>
                        {copy.colMeta(thaiDate(a.due_at), a.full_score)}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.student_id}>
                      <td>{row.roll_number ?? '–'}</td>
                      <th scope="row">
                        {row.display_name}
                        {!row.member && <small>{copy.left}</small>}
                      </th>
                      {table.assignments.map((a) => (
                        <Score key={a.post_id} view={cellView(row.cells[a.post_id])} />
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {pages > 1 && (
              <nav className={styles.pager} aria-label={copy.pageOf(current, pages, PER_PAGE)}>
                <span>{copy.pageOf(current, pages, PER_PAGE)}</span>
                <div className={styles.pg}>
                  <button
                    type="button"
                    disabled={current <= 1}
                    aria-label={copy.prevPage}
                    onClick={() => setPage(current - 1)}
                  >
                    <ChevronLeft aria-hidden="true" />
                  </button>
                  {Array.from({ length: pages }, (_, k) => (
                    <button
                      type="button"
                      key={k + 1}
                      aria-label={copy.pageAria(k + 1)}
                      aria-current={current === k + 1 ? 'page' : undefined}
                      onClick={() => setPage(k + 1)}
                    >
                      {k + 1}
                    </button>
                  ))}
                  <button
                    type="button"
                    disabled={current >= pages}
                    aria-label={copy.nextPage}
                    onClick={() => setPage(current + 1)}
                  >
                    <ChevronRight aria-hidden="true" />
                  </button>
                </div>
              </nav>
            )}
          </div>
          <ul className={styles.legend} aria-label={copy.legendAria}>
            <li>
              <Chip tone="amber">{copy.waiting}</Chip>
              {copy.legendWaiting}
            </li>
            <li>
              <span className={styles.dash}>{copy.notSubmitted}</span>
              {copy.legendNone}
            </li>
            <li>
              <span className={styles.zero}>0</span>
              {copy.legendZero}
            </li>
            <li>
              <Chip tone="plain">{copy.noScore}</Chip>
              {copy.legendNoScore}
            </li>
            <li>
              <span className={styles.lateDot} aria-hidden="true">
                •
              </span>
              {copy.legendLate}
            </li>
          </ul>
        </>
      )}
    </div>
  )
}

function Score({ view }: { view: CellView }) {
  const copy = th.gradebook
  if (view.kind === 'none') {
    return (
      <td>
        <span className={styles.dash}>{copy.notSubmitted}</span>
      </td>
    )
  }
  if (view.kind === 'waiting') {
    return (
      <td>
        <Chip tone="amber">{copy.waiting}</Chip>
      </td>
    )
  }
  const late = view.late && (
    <span className={styles.lateDot}>
      <span aria-hidden="true">•</span>
      <span className={styles.sr}>{copy.late}</span>
    </span>
  )
  if (view.kind === 'noScore') {
    return (
      <td>
        <Chip tone="plain">{copy.noScore}</Chip>
        {late}
      </td>
    )
  }
  return (
    <td className={view.net === 0 ? styles.zeroCell : styles.score}>
      {view.net}
      {late}
    </td>
  )
}
