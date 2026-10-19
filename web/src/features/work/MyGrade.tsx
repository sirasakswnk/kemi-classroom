import { Info } from 'lucide-react'
import { th } from '../../copy/th'
import { Chip } from '../../ui'
import type { GradeView } from './workState'
import styles from './work.module.css'

// S03 “คะแนนและความครบถ้วน” (UX 6–7): คะแนนก่อนหัก/การหัก/สุทธิ · ไม่ติ๊กครบถ้วน = “รอครูยืนยันความครบถ้วน” (ไม่ใช้คำว่าไม่ผ่าน)
// ผลของชุดก่อนหน้าแสดงไว้พร้อมบอกว่ารอตรวจชุดใหม่ · เหตุผลการปรับหักอยู่ในช่องความคิดเห็น · โทเคนมากับระยะ 5
export function MyGrade({
  view,
  fullScore,
  revision,
}: {
  view: GradeView | null
  fullScore: number
  /** ชุดที่ส่งล่าสุดของนักเรียน */
  revision: number
}) {
  const copy = th.work.grade
  const chip = !view
    ? { label: copy.waiting, tone: 'amber' as const }
    : view.stale
      ? { label: copy.staleChip, tone: 'amber' as const }
      : view.passed
        ? { label: copy.complete, tone: 'green' as const }
        : { label: copy.pending, tone: 'amber' as const }
  const score = view?.score

  return (
    <section className={styles.section} aria-labelledby="workGrade">
      <div className={styles.sectionHead}>
        <h2 id="workGrade">{copy.title}</h2>
        <Chip tone={chip.tone}>{chip.label}</Chip>
      </div>
      <div className={styles.card} data-stale={view?.stale || undefined}>
        {!view && <p className={styles.muted}>{copy.waitingBody}</p>}
        {view?.stale && (
          <p className={styles.note} data-tone="plain">
            <Info aria-hidden="true" />
            <span>{copy.staleNote(view.revision, revision)}</span>
          </p>
        )}
        {view && score && (
          <dl className={styles.scoreRows}>
            {score.penaltyPct > 0 ? (
              <>
                <div>
                  <dt>{copy.raw}</dt>
                  <dd>
                    {score.raw} <small>{copy.outOf(fullScore)}</small>
                  </dd>
                </div>
                <div>
                  <dt>{copy.penalty(score.penaltyPct)}</dt>
                  <dd>−{score.deduction}</dd>
                </div>
                <div className={styles.scoreNet}>
                  <dt>{copy.net}</dt>
                  <dd>
                    {score.net} <small>{copy.outOf(fullScore)}</small>
                  </dd>
                </div>
              </>
            ) : (
              <div className={styles.scoreNet}>
                <dt>{copy.single}</dt>
                <dd>
                  {score.net} <small>{copy.outOf(fullScore)}</small>
                </dd>
              </div>
            )}
          </dl>
        )}
        {view && !score && <p className={styles.muted}>{copy.noScore}</p>}
        {view && view.late && view.override !== null && (
          <p className={styles.note} data-tone="purple">
            <Info aria-hidden="true" />
            <span>{view.override === 0 ? copy.waived : copy.overridden(view.override)}</span>
          </p>
        )}
      </div>
    </section>
  )
}
