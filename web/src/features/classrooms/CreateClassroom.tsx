import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarRange, KeyRound, Plus, TriangleAlert } from 'lucide-react'
import { useRef, useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router'
import { th } from '../../copy/th'
import { Card, Chip, Field, Input, Select, useToast } from '../../ui'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { appErrorOf, createClassroom, teachersQuery } from './api'
import styles from './classrooms.module.css'

const NAME_MAX = 80
const DESCRIPTION_MAX = 200

interface Errors {
  name?: string
  teacher?: string
  form?: string
}

// T09 สร้างชั้นเรียน: ชื่อ รายละเอียด (ไม่บังคับ) ภาคเรียนปัจจุบัน → สร้างแล้วพาไป T08 แท็บสมาชิก
// โหมดผู้ดูแลต้องเลือกครูเจ้าของห้อง; ข้อผิดพลาดแสดงใต้ช่องที่เกี่ยวข้องตาม UX 7.1
export default function CreateClassroom() {
  const { adminMode, term } = useTeacher()
  const teachers = useQuery({ ...teachersQuery, enabled: adminMode })
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [teacherId, setTeacherId] = useState('')
  const [errors, setErrors] = useState<Errors>({})
  const nameRef = useRef<HTMLInputElement>(null)
  const teacherRef = useRef<HTMLSelectElement>(null)
  // ส่งซ้ำด้วยเนื้อหาเดิม (เช่นเน็ตหลุดแล้วกดอีกครั้ง) ใช้ request key เดิม → ไม่เกิดห้องซ้ำ
  const requestKey = useRef<{ fingerprint: string; key: string } | null>(null)
  const queryClient = useQueryClient()
  const navigate = useNavigate()
  const toast = useToast()

  const mutation = useMutation({
    mutationFn: createClassroom,
    onSuccess: async (created) => {
      await queryClient.invalidateQueries({ queryKey: ['classrooms'] })
      toast(th.classrooms.create.created(created.name), { tone: 'success' })
      navigate(`/t/classes/${created.classroom_id}?tab=members`)
    },
    onError: (error) => {
      const appError = appErrorOf(error)
      if (appError.code === 'name_invalid') {
        setErrors({ name: appError.message })
        nameRef.current?.focus()
      } else if (appError.code === 'teacher_required') {
        setErrors({ teacher: appError.message })
        teacherRef.current?.focus()
      } else {
        const ref = appError.ref ? ` (${th.errors.reference(appError.ref)})` : ''
        setErrors({ form: appError.message + ref })
      }
    },
  })

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (mutation.isPending) return
    const trimmed = name.trim()
    if (trimmed.length < 1 || trimmed.length > NAME_MAX) {
      setErrors({ name: th.errors.name_invalid })
      nameRef.current?.focus()
      return
    }
    if (adminMode && !teacherId) {
      setErrors({ teacher: th.errors.teacher_required })
      teacherRef.current?.focus()
      return
    }
    setErrors({})
    const fingerprint = JSON.stringify([trimmed, description.trim(), teacherId])
    if (requestKey.current?.fingerprint !== fingerprint) {
      requestKey.current = { fingerprint, key: crypto.randomUUID() }
    }
    mutation.mutate({
      name: trimmed,
      description: description.trim(),
      requestKey: requestKey.current.key,
      teacherId: adminMode ? teacherId : null,
      adminMode,
    })
  }

  const copy = th.classrooms.create
  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.title }]}>
      <div className={styles.head}>
        <div>
          <span className={styles.eyebrow}>{term?.name}</span>
          <h1>{copy.title}</h1>
          <p>{copy.intro}</p>
        </div>
      </div>
      <div className={styles.createGrid}>
        {term ? (
          <Card as="section" padding="none">
            <form className={styles.form} onSubmit={submit} noValidate>
              <Field label={copy.name} error={errors.name}>
                <Input
                  ref={nameRef}
                  value={name}
                  onChange={(e) => {
                    setName(e.target.value)
                    if (errors.name) setErrors((x) => ({ ...x, name: undefined }))
                  }}
                  placeholder={copy.namePlaceholder}
                  maxLength={NAME_MAX}
                  autoComplete="off"
                  required
                />
              </Field>
              <Field label={copy.description} optional>
                <Input
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder={copy.descriptionPlaceholder}
                  maxLength={DESCRIPTION_MAX}
                  autoComplete="off"
                />
              </Field>
              {adminMode && (
                <Field label={copy.teacher} error={errors.teacher}>
                  <Select
                    ref={teacherRef}
                    value={teacherId}
                    onChange={(e) => {
                      setTeacherId(e.target.value)
                      if (errors.teacher) setErrors((x) => ({ ...x, teacher: undefined }))
                    }}
                    required
                  >
                    <option value="">{copy.teacherPlaceholder}</option>
                    {teachers.data?.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.display_name}
                      </option>
                    ))}
                  </Select>
                </Field>
              )}
              <div className={styles.termGroup}>
                <span className={styles.groupLabel}>{copy.term}</span>
                <Chip tone="purple" icon={<CalendarRange />}>
                  {term.name}
                </Chip>
                <span className={styles.small}>{copy.termHint}</span>
              </div>
              <p className={styles.note} data-tone="purple">
                <KeyRound aria-hidden="true" />
                <span>{copy.note}</span>
              </p>
              <div className={styles.formFoot}>
                {errors.form && (
                  <p className={styles.alert} role="alert">
                    <TriangleAlert aria-hidden="true" />
                    <span>{errors.form}</span>
                  </p>
                )}
                <Link to="/t" className={styles.ghostLink}>
                  {copy.cancel}
                </Link>
                <button type="submit" className={styles.submit} disabled={mutation.isPending}>
                  <Plus aria-hidden="true" />
                  {mutation.isPending ? copy.submitting : copy.submit}
                </button>
              </div>
            </form>
          </Card>
        ) : (
          <p className={styles.alert} role="alert">
            <TriangleAlert aria-hidden="true" />
            <span>{copy.noTerm}</span>
          </p>
        )}
        <aside className={styles.howPanel} aria-labelledby="howTitle">
          <h2 id="howTitle">{copy.howTitle}</h2>
          <ol className={styles.how}>
            {copy.how.map((step, i) => (
              <li key={step.title}>
                <span className={styles.hn} aria-hidden="true">
                  {i + 1}
                </span>
                <span>
                  <b>{step.title}</b>
                  <span>{step.detail}</span>
                </span>
              </li>
            ))}
          </ol>
        </aside>
      </div>
    </TeacherPage>
  )
}
