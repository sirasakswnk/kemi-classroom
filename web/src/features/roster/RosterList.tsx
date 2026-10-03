import { useQuery } from '@tanstack/react-query'
import { EllipsisVertical, FileSpreadsheet, Link2, TriangleAlert, Unlink } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button, Chip, MenuButton, Select } from '../../ui'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { RebindDialog, type RebindMode } from './RebindDialog'
import { filterRoster, rosterOverviewQuery, type RosterFilter, type RosterRow } from './rosterApi'
import styles from './RosterList.module.css'

const FILTERS: RosterFilter[] = ['all', 'unbound', 'notjoined']

// T05 รายชื่อนักเรียน (แบบ v2 tRoster, UX 10): รายชื่อภาคเรียนนี้ทุกห้อง กรองตามห้อง/สถานะ
// แถวที่ผูกแล้วมีเมนู “แก้การผูกบัญชี” 2 แบบ — ตัวกรองอยู่ใน URL (?group=&filter=) ให้หน้าอื่นลิงก์มาได้
export default function RosterList() {
  const { adminMode, term } = useTeacher()
  const copy = th.rosterList
  const roster = useQuery(rosterOverviewQuery(adminMode))
  const [params, setParams] = useSearchParams()
  const group = params.get('group') ?? ''
  const filterParam = params.get('filter') as RosterFilter | null
  const filter: RosterFilter = filterParam && FILTERS.includes(filterParam) ? filterParam : 'all'
  const [target, setTarget] = useState<{ row: RosterRow; mode: RebindMode } | null>(null)

  const rows = useMemo(() => roster.data ?? [], [roster.data])
  const groups = useMemo(() => [...new Set(rows.map((r) => r.group_name))], [rows])
  const inGroup = useMemo(() => filterRoster(rows, group, 'all'), [rows, group])
  const shown = useMemo(() => filterRoster(rows, group, filter), [rows, group, filter])

  const setParam = (key: string, value: string) =>
    setParams(
      (p) => {
        const next = new URLSearchParams(p)
        if (value && value !== 'all') next.set(key, value)
        else next.delete(key)
        return next
      },
      { replace: true },
    )

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.title }]}>
      <div className={styles.head}>
        <div>
          <span className={styles.eyebrow}>{term?.name}</span>
          <h1>{copy.title}</h1>
          <p>{copy.intro}</p>
        </div>
        <Link to="/t/roster/import" className={styles.primaryLink}>
          <FileSpreadsheet aria-hidden="true" />
          {copy.importExcel}
        </Link>
      </div>

      {roster.isPending && (
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      )}
      {roster.isError && (
        <div className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{appErrorOf(roster.error).message}</span>
          <Button size="sm" variant="ghost" onClick={() => void roster.refetch()}>
            {th.teacher.retry}
          </Button>
        </div>
      )}

      {roster.isSuccess && rows.length === 0 && <p className={styles.empty}>{copy.noRoster}</p>}

      {rows.length > 0 && (
        <section className={styles.card} aria-labelledby="rosterCaption">
          <div className={styles.bar}>
            <div className={styles.groupField}>
              <label htmlFor="rosterGroup">{copy.groupLabel}</label>
              <Select
                id="rosterGroup"
                value={group}
                onChange={(e) => setParam('group', e.target.value)}
              >
                <option value="">{copy.allGroups}</option>
                {groups.map((g) => (
                  <option key={g} value={g}>
                    {g}
                  </option>
                ))}
              </Select>
            </div>
            <div className={styles.seg} role="group" aria-label={copy.filterLabel}>
              {FILTERS.map((f) => (
                <button
                  key={f}
                  type="button"
                  aria-pressed={filter === f}
                  onClick={() => setParam('filter', f)}
                >
                  {copy.filters[f]}
                  <span className={styles.n}>{filterRoster(inGroup, '', f).length}</span>
                </button>
              ))}
            </div>
          </div>
          <div className={styles.tableWrap}>
            <table className={styles.table}>
              <caption id="rosterCaption" className="sr-only">
                {copy.caption} · {copy.count(shown.length)}
              </caption>
              <thead>
                <tr>
                  <th scope="col">{copy.columns.roll}</th>
                  <th scope="col">{copy.columns.name}</th>
                  <th scope="col">{copy.columns.code}</th>
                  <th scope="col">{copy.columns.account}</th>
                  <th scope="col">{copy.columns.classes}</th>
                  <th scope="col">
                    <span className="sr-only">{copy.columns.menu}</span>
                  </th>
                </tr>
              </thead>
              <tbody>
                {shown.map((r) => (
                  <tr key={r.student_id}>
                    <td className={styles.roll}>
                      <span className={styles.group}>{r.group_name}</span> {r.roll_number}
                    </td>
                    <th scope="row" className={styles.name}>
                      {r.display_name}
                    </th>
                    <td className="num">{r.student_code}</td>
                    <td>
                      {r.bound ? (
                        <span className={styles.account}>
                          <Chip tone="green">{copy.bound}</Chip>
                          <span className={styles.email}>{r.account_email}</span>
                        </span>
                      ) : (
                        <Chip tone="amber">{copy.unboundChip}</Chip>
                      )}
                    </td>
                    <td>
                      {r.classrooms.length > 0 ? (
                        <span className={styles.chips}>
                          {r.classrooms.map((c) => (
                            <Chip key={c} tone="purple">
                              {c}
                            </Chip>
                          ))}
                        </span>
                      ) : (
                        <Chip tone="plain">{copy.notJoined}</Chip>
                      )}
                    </td>
                    <td className={styles.menuCell}>
                      {r.bound && (
                        <MenuButton
                          label={copy.rowMenu(r.display_name)}
                          icon={<EllipsisVertical aria-hidden="true" />}
                          items={[
                            {
                              label: copy.moveItem,
                              icon: <Link2 />,
                              onSelect: () => setTarget({ row: r, mode: 'move' }),
                            },
                            {
                              label: copy.unbindItem,
                              icon: <Unlink />,
                              tone: 'danger',
                              onSelect: () => setTarget({ row: r, mode: 'unbind' }),
                            },
                          ]}
                        />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {shown.length === 0 && <p className={styles.emptyRow}>{copy.empty}</p>}
          </div>
        </section>
      )}

      {target && (
        <RebindDialog
          key={`${target.row.student_id}${target.mode}`}
          student={target.row}
          mode={target.mode}
          adminMode={adminMode}
          onClose={() => setTarget(null)}
        />
      )}
    </TeacherPage>
  )
}
