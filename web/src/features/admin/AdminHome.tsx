import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CloudUpload,
  LogIn,
  LogOut,
  Plus,
  ShieldCheck,
  TriangleAlert,
  UserMinus,
  UserRound,
} from 'lucide-react'
import { useRef, useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router'
import { useAuth } from '../../app/auth/useAuth'
import { BrandLogo } from '../../app/common/brand'
import { th } from '../../copy/th'
import { appErrorOf } from '../../lib/request'
import { Button, Chip, Field, Input, Modal, Select, useToast } from '../../ui'
import { enterAdminMode } from '../teacher/adminMode'
import { addTeacher, adminTeachersQuery, removeTeacher, type AllowlistRow } from './api'
import styles from './AdminHome.module.css'

const NEW = '__new__'

// D01 ดูแลระบบ (UX 12 L6, แบบ v2 renderAdmin): บัญชีครู (เพิ่ม/เอาออก ต้องเหลืออย่างน้อย 1) และเข้าหน้าครูในโหมดผู้ดูแล
// สำรองข้อมูลและพื้นที่เก็บไฟล์มาในระยะ 6–7
export default function AdminHome() {
  const { signOut } = useAuth()
  const navigate = useNavigate()
  const data = useQuery(adminTeachersQuery)
  const copy = th.admin

  return (
    <div className={styles.app}>
      <header className={styles.top}>
        <span className={styles.brand}>
          <BrandLogo />
          <span>{th.appName}</span>
        </span>
        <Button size="sm" variant="ghost" icon={<LogOut />} onClick={signOut}>
          {th.common.signOut}
        </Button>
      </header>
      <main className={styles.page}>
        <div className={styles.head}>
          <div>
            <span className={styles.eyebrow}>{copy.eyebrow}</span>
            <h1>{copy.title}</h1>
            <p>{copy.intro}</p>
          </div>
          {data.data?.admin_email && (
            <Chip tone="purple" icon={<ShieldCheck />}>
              {copy.adminChip(data.data.admin_email)}
            </Chip>
          )}
        </div>

        <section className={styles.later} aria-labelledby="adminLater">
          <CloudUpload aria-hidden="true" />
          <span>
            <b id="adminLater">{copy.laterTitle}</b>
            <span>{copy.laterBody}</span>
          </span>
        </section>

        <div className={styles.cols}>
          <TeachersPanel />
          <section className={styles.panel} aria-labelledby="actAsTitle">
            <h2 id="actAsTitle">{copy.actAsTitle}</h2>
            <p>{copy.actAsBody}</p>
            <p className={styles.note} data-tone="amber">
              <TriangleAlert aria-hidden="true" />
              <span>{copy.actAsNote}</span>
            </p>
            <Button
              icon={<LogIn />}
              className={styles.start}
              onClick={() => {
                enterAdminMode()
                navigate('/t')
              }}
            >
              {th.teacher.enterAdmin}
            </Button>
          </section>
        </div>
      </main>
    </div>
  )
}

function TeachersPanel() {
  const copy = th.admin
  const data = useQuery(adminTeachersQuery)
  const queryClient = useQueryClient()
  const toast = useToast()
  const [email, setEmail] = useState('')
  const [teacherId, setTeacherId] = useState('')
  const [newName, setNewName] = useState('')
  const [errors, setErrors] = useState<{
    email?: string
    teacher?: string
    name?: string
    form?: string
  }>({})
  const [target, setTarget] = useState<AllowlistRow | null>(null)
  const [removeError, setRemoveError] = useState<string | null>(null)
  const emailRef = useRef<HTMLInputElement>(null)
  const teacherRef = useRef<HTMLSelectElement>(null)
  const nameRef = useRef<HTMLInputElement>(null)

  const teachers = data.data?.teachers ?? []
  const rows = data.data?.allowlist ?? []
  // ครูคนเดียวในระบบ → เลือกให้ก่อน
  const selected = teacherId || (teachers.length === 1 ? teachers[0].id : '')

  const add = useMutation({
    mutationFn: addTeacher,
    onSuccess: async (row) => {
      setEmail('')
      setNewName('')
      setTeacherId('')
      setErrors({})
      await queryClient.invalidateQueries({ queryKey: ['admin-teachers'] })
      toast(copy.added(row.email ?? ''), { tone: 'success' })
    },
    onError: (error) => {
      const e = appErrorOf(error)
      if (e.code === 'email_invalid' || e.code === 'teacher_email_exists') {
        setErrors({ email: e.message })
        emailRef.current?.focus()
      } else if (e.code === 'teacher_name_invalid') {
        setErrors({ name: e.message })
        nameRef.current?.focus()
      } else if (e.code === 'teacher_required') {
        setErrors({ teacher: copy.pickTeacher })
        teacherRef.current?.focus()
      } else {
        setErrors({ form: e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : '') })
      }
    },
  })

  const remove = useMutation({
    mutationFn: (row: AllowlistRow) => removeTeacher(row.id),
    onSuccess: async (_r, row) => {
      setTarget(null)
      await queryClient.invalidateQueries({ queryKey: ['admin-teachers'] })
      toast(copy.removed(row.email ?? ''), { tone: 'success' })
    },
    onError: (error) => {
      const e = appErrorOf(error)
      setRemoveError(e.message + (e.ref ? ` (${th.errors.reference(e.ref)})` : ''))
    },
  })

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (add.isPending) return
    const value = email.trim()
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) {
      setErrors({ email: th.errors.email_invalid })
      emailRef.current?.focus()
      return
    }
    if (!selected) {
      setErrors({ teacher: copy.pickTeacher })
      teacherRef.current?.focus()
      return
    }
    if (selected === NEW && (newName.trim().length < 1 || newName.trim().length > 60)) {
      setErrors({ name: th.errors.teacher_name_invalid })
      nameRef.current?.focus()
      return
    }
    setErrors({})
    add.mutate({
      email: value,
      teacherId: selected === NEW ? null : selected,
      newName: newName.trim(),
    })
  }

  return (
    <section className={styles.panel} aria-labelledby="teachersTitle">
      <h2 id="teachersTitle">{copy.teachersTitle}</h2>
      <p className={styles.hint}>{copy.teachersHint}</p>
      {data.isPending && (
        <p role="status" className={styles.hint}>
          {th.common.loading}
        </p>
      )}
      {data.isError && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>{appErrorOf(data.error).message}</span>
        </p>
      )}
      <ul className={styles.list}>
        {rows.map((r) => (
          <li key={r.id} className={styles.row}>
            <span className={styles.rowIcon} aria-hidden="true">
              <UserRound />
            </span>
            <span className={styles.rowText}>
              <b>{r.teacher_name}</b>
              <span>
                {r.email}
                {!r.signed_in && ` · ${copy.notSignedIn}`}
              </span>
            </span>
            {rows.length > 1 && (
              <Button
                size="sm"
                variant="ghost"
                aria-label={copy.removeAria(r.teacher_name, r.email ?? '')}
                onClick={() => {
                  setRemoveError(null)
                  setTarget(r)
                }}
              >
                {copy.remove}
              </Button>
            )}
          </li>
        ))}
        {data.data && (
          <li className={styles.row}>
            <span className={styles.rowIcon} aria-hidden="true">
              <ShieldCheck />
            </span>
            <span className={styles.rowText}>
              <b>{copy.you}</b>
              <span>{copy.youDetail(data.data.admin_email ?? '')}</span>
            </span>
          </li>
        )}
      </ul>
      {rows.length === 1 && <p className={styles.hint}>{copy.lastHint}</p>}

      <form
        className={styles.addForm}
        onSubmit={submit}
        noValidate
        aria-labelledby="addTeacherTitle"
      >
        <h3 id="addTeacherTitle">{copy.addTitle}</h3>
        <Field label={copy.emailLabel} error={errors.email}>
          <Input
            ref={emailRef}
            type="email"
            inputMode="email"
            autoComplete="off"
            spellCheck={false}
            value={email}
            placeholder={copy.emailPlaceholder}
            onChange={(e) => {
              setEmail(e.target.value)
              if (errors.email) setErrors((x) => ({ ...x, email: undefined }))
            }}
          />
        </Field>
        <Field label={copy.teacherLabel} error={errors.teacher}>
          <Select
            ref={teacherRef}
            value={selected}
            onChange={(e) => {
              setTeacherId(e.target.value)
              if (errors.teacher) setErrors((x) => ({ ...x, teacher: undefined }))
            }}
          >
            {teachers.length !== 1 && (
              <option value="">{th.classrooms.create.teacherPlaceholder}</option>
            )}
            {teachers.map((t) => (
              <option key={t.id} value={t.id}>
                {t.display_name}
              </option>
            ))}
            <option value={NEW}>{copy.newTeacher}</option>
          </Select>
        </Field>
        {selected === NEW && (
          <Field label={copy.newTeacherName} error={errors.name}>
            <Input
              ref={nameRef}
              value={newName}
              maxLength={60}
              placeholder={copy.newTeacherPlaceholder}
              onChange={(e) => {
                setNewName(e.target.value)
                if (errors.name) setErrors((x) => ({ ...x, name: undefined }))
              }}
            />
          </Field>
        )}
        {errors.form && (
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{errors.form}</span>
          </p>
        )}
        <Button type="submit" icon={<Plus />} disabled={add.isPending} className={styles.start}>
          {add.isPending ? copy.adding : copy.add}
        </Button>
      </form>

      <Modal
        open={target !== null}
        onClose={() => {
          if (!remove.isPending) setTarget(null)
        }}
        icon={<UserMinus />}
        title={target ? copy.removeTitle(target.email ?? '') : ''}
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
    </section>
  )
}
