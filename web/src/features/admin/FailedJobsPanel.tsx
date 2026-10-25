import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { RotateCcw, TriangleAlert } from 'lucide-react'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button, useToast } from '../../ui'
import { adminB2UsageQuery } from '../storage/api'
import { adminFailedJobsQuery, retryJob } from './api'
import { failedJobRow } from './failedJobs'
import styles from './AdminHome.module.css'

// D01 งานเบื้องหลังที่ล้มเหลว (P6-04c): ชนิด เวลา จำนวนครั้ง error ย่อ (ไม่มี payload) + ลองใหม่
// ปุ่มปิดระหว่างส่ง และฐานข้อมูลกันการกดซ้ำ/พร้อมกันเอง (งานที่ไม่ใช่ failed แล้ว = not_failed)
export function FailedJobsPanel() {
  const copy = th.admin.jobs
  const toast = useToast()
  const queryClient = useQueryClient()
  const jobs = useQuery(adminFailedJobsQuery)
  const retry = useMutation({
    mutationFn: retryJob,
    onSuccess: ({ result }) => {
      toast(
        result === 'queued'
          ? copy.queued
          : result === 'superseded'
            ? copy.superseded
            : copy.notFailed,
        { tone: result === 'queued' ? 'success' : 'info' },
      )
    },
    onSettled: () => {
      void queryClient.invalidateQueries({ queryKey: adminFailedJobsQuery.queryKey })
      void queryClient.invalidateQueries({ queryKey: adminB2UsageQuery.queryKey })
    },
  })
  const now = new Date()

  return (
    <section className={styles.panel} aria-labelledby="failedJobsTitle">
      <h2 id="failedJobsTitle">{copy.title}</h2>
      <p className={styles.hint}>{copy.intro}</p>
      {jobs.isPending ? (
        <p className={styles.hint}>{th.common.loading}</p>
      ) : jobs.isError ? (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.loadFailed} {appErrorOf(jobs.error).message}
          </span>
        </p>
      ) : jobs.data.items.length === 0 ? (
        <p className={styles.hint}>{copy.empty}</p>
      ) : (
        <>
          <ul className={styles.jobs}>
            {jobs.data.items.map((job) => {
              const row = failedJobRow(job, now)
              const busy = retry.isPending && retry.variables === job.id
              return (
                <li key={row.id} className={styles.job}>
                  <span className={styles.jobText}>
                    <b>{row.kind}</b>
                    <span>{row.meta}</span>
                    <code>{row.error}</code>
                  </span>
                  <Button
                    size="sm"
                    variant="ghost"
                    icon={<RotateCcw />}
                    disabled={retry.isPending}
                    aria-label={copy.retryAria(row.kind)}
                    onClick={() => retry.mutate(row.id)}
                  >
                    {busy ? th.common.loading : copy.retry}
                  </Button>
                </li>
              )
            })}
          </ul>
          {jobs.data.failed_total > jobs.data.items.length && (
            <p className={styles.hint}>
              {copy.shown(jobs.data.items.length, jobs.data.failed_total)}
            </p>
          )}
        </>
      )}
      {retry.isError && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.retryFailed} {appErrorOf(retry.error).message}
          </span>
        </p>
      )}
    </section>
  )
}
