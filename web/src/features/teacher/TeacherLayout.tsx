import { useQuery } from '@tanstack/react-query'
import {
  ChevronRight,
  CirclePlus,
  LayoutDashboard,
  ShieldCheck,
  TriangleAlert,
  Users,
} from 'lucide-react'
import { Fragment, useMemo, type ReactNode } from 'react'
import { Link, NavLink, Navigate, Outlet, useNavigate } from 'react-router'
import { useAuth } from '../../app/auth/useAuth'
import { BrandLogo } from '../../app/common/brand'
import { FullPageCard, FullPageStatus } from '../../app/common/FullPageStatus'
import { th } from '../../copy/th'
import { Button } from '../../ui'
import { appErrorOf, classroomsQuery, teachersQuery, termQuery } from '../classrooms/api'
import { classTone } from '../classrooms/tone'
import { exitAdminMode, useAdminModeFlag } from './adminMode'
import { TeacherContext, useTeacher, type TeacherContextValue } from './teacherContext'
import { initialOf as initialOfTeacher } from '../../lib/initial'
import styles from './TeacherLayout.module.css'
import { TeacherStorageBar } from '../storage/Storage'

// โครงหน้าครู (แบบ v2 .desk): เมนูข้างตั้งแต่ 900 px ต่ำกว่านั้นเป็นแถบเลื่อนด้านบน (UX 13) + แถบเตือนโหมดผู้ดูแล (L6)
// เข้าได้เฉพาะครู หรือผู้ดูแลที่กดเข้าโหมดผู้ดูแลแล้ว
export function TeacherLayout() {
  const { state, signOut } = useAuth()
  const adminFlag = useAdminModeFlag()
  const navigate = useNavigate()
  const account = state.status === 'ready' ? state.account : null
  const adminMode = account?.role === 'admin' && adminFlag

  const term = useQuery(termQuery)
  const classrooms = useQuery(classroomsQuery(term.data?.id))
  const teachers = useQuery({ ...teachersQuery, enabled: account?.role === 'teacher' })

  const value = useMemo<TeacherContextValue | null>(() => {
    if (!account || !term.isSuccess || (term.data && !classrooms.isSuccess)) return null
    const me = teachers.data?.find((t) => t.id === account.teacher_id)
    return {
      account,
      adminMode,
      displayName: adminMode ? th.teacher.adminName : (me?.display_name ?? account.email ?? ''),
      term: term.data,
      classrooms: classrooms.data ?? [],
    }
  }, [
    account,
    adminMode,
    term.isSuccess,
    term.data,
    classrooms.isSuccess,
    classrooms.data,
    teachers.data,
  ])

  if (!account) return <FullPageStatus />
  if (account.role === 'admin' && !adminFlag) return <Navigate to="/admin" replace />

  const failed = term.error ?? classrooms.error
  if (failed) {
    const error = appErrorOf(failed)
    return (
      <FullPageCard title={th.teacher.loadFailed}>
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error.message}
            {error.ref && <small> {th.errors.reference(error.ref)}</small>}
          </span>
        </p>
        <Button onClick={() => void Promise.all([term.refetch(), classrooms.refetch()])}>
          {th.teacher.retry}
        </Button>
        <Button variant="ghost" onClick={signOut}>
          {th.common.signOut}
        </Button>
      </FullPageCard>
    )
  }
  if (!value) return <FullPageStatus />

  return (
    <TeacherContext value={value}>
      <div className={styles.desk}>
        <nav className={styles.side} aria-label={th.teacher.navLabel}>
          <Link to="/t" className={styles.brand}>
            <BrandLogo />
            <span>{th.appName}</span>
          </Link>
          <NavLink to="/t" end className={styles.nav}>
            <LayoutDashboard aria-hidden="true" />
            {th.teacher.overview}
          </NavLink>
          <span className={styles.label}>{th.teacher.classes}</span>
          {value.classrooms.map((c, i) => (
            <NavLink key={c.id} to={`/t/c/${c.id}`} className={styles.nav}>
              <span className={styles.dot} data-tone={classTone(i)} aria-hidden="true" />
              <span className={styles.navText}>{c.name}</span>
            </NavLink>
          ))}
          <NavLink to="/t/new-class" className={styles.nav}>
            <CirclePlus aria-hidden="true" />
            {th.teacher.newClass}
          </NavLink>
          <span className={styles.label}>{th.teacher.manage}</span>
          <NavLink to="/t/roster" className={styles.nav}>
            <Users aria-hidden="true" />
            {th.teacher.roster}
          </NavLink>
          <p className={styles.foot}>
            {value.term?.name}
            <br />
            {th.teacher.sideFoot(value.classrooms.length)}
          </p>
        </nav>
        <div className={styles.main}>
          {adminMode && (
            <div className={styles.adminBar} role="note">
              <ShieldCheck aria-hidden="true" />
              <span>
                {th.teacher.adminBar}
                <b>{th.teacher.adminBarRole}</b> {th.teacher.adminBarTail}
              </span>
              <button
                type="button"
                className={styles.adminExit}
                onClick={() => {
                  exitAdminMode()
                  navigate('/admin')
                }}
              >
                {th.teacher.exitAdmin}
              </button>
            </div>
          )}
          <Outlet />
        </div>
      </div>
    </TeacherContext>
  )
}

export interface Crumb {
  label: string
  to?: string
}

// แถบบนของแต่ละหน้า (แบบ v2 tTop): ตำแหน่ง + ชื่อผู้ใช้ + ออกจากระบบ แล้วตามด้วยเนื้อหาหน้า
export function TeacherPage({ crumbs, children }: { crumbs: Crumb[]; children: ReactNode }) {
  const { displayName } = useTeacher()
  return (
    <>
      <header className={styles.top}>
        <nav aria-label={th.teacher.crumbsLabel} className={styles.crumbs}>
          {crumbs.map((c, i) => (
            <Fragment key={`${i}${c.label}`}>
              {i > 0 && <ChevronRight aria-hidden="true" />}
              {c.to ? <Link to={c.to}>{c.label}</Link> : <b aria-current="page">{c.label}</b>}
            </Fragment>
          ))}
        </nav>
        <Link
          to="/t/me"
          className={styles.who}
          aria-label={`${th.teacherAccount.title} · ${displayName}`}
        >
          <span className={styles.avatar} aria-hidden="true">
            {initialOfTeacher(displayName)}
          </span>
          <span className={styles.whoName} aria-hidden="true">
            {displayName}
          </span>
        </Link>
      </header>
      <main className={styles.body}>
        <TeacherStorageBar />
        {children}
      </main>
    </>
  )
}
