import { useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Check,
  CircleCheck,
  ImageUp,
  Info,
  Pencil,
  Plus,
  RotateCcw,
  TriangleAlert,
  Undo2,
} from 'lucide-react'
import { useEffect, useRef, useState, type Dispatch, type Ref, type SetStateAction } from 'react'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { Button, Field, Input, Textarea, useToast } from '../../ui'
import { useRequestKey } from '../review/useRequestKey'
import { Medal } from '../rewards/Medal'
import { tierOf } from '../rewards/rewardState'
import { TeacherPage } from '../teacher/TeacherLayout'
import { useTeacher } from '../teacher/teacherContext'
import { defaultUploadDeps } from '../uploads/useFileField'
import { uploadSet } from '../uploads/uploader'
import { catalogQuery, saveCharm, saveRarityWeights, type AdminCharm, type Catalog } from './api'
import { CharmImageError, prepareCharmImage } from './charmImage'
import {
  canSaveDraft,
  DESC_MAX,
  draftOf,
  NAME_MAX,
  newDraft,
  previewSymbol,
  ratesState,
  toInput,
  type CharmDraft,
} from './charmForm'
import rewardStyles from '../rewards/rewards.module.css'
import styles from './charms.module.css'

const copy = th.charms
const CHIP = [rewardStyles.chip0, rewardStyles.chip1, rewardStyles.chip2, rewardStyles.chip3]
const DOT = [rewardStyles.tier0, rewardStyles.tier1, rewardStyles.tier2, rewardStyles.tier3]

// T06 จัดการเครื่องราง (UX 11; แบบ v2 tCharms): อัตราตามระดับ (รวม 100%) · รายการ · ฟอร์มเพิ่ม/แก้ + ตัวอย่างสด
// รูปที่อัปโหลด: ตัดเป็นสี่เหลี่ยมจัตุรัสบนเครื่อง → ชุดอัปโหลด purpose charm → บันทึกพร้อมฟอร์ม (save_charm)
export default function CharmsPage() {
  const { adminMode } = useTeacher()
  const catalog = useQuery(catalogQuery(adminMode))

  return (
    <TeacherPage crumbs={[{ label: th.teacher.overview, to: '/t' }, { label: copy.title }]}>
      {catalog.isError ? (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {copy.loadFailed} · {appErrorOf(catalog.error).message}
          </span>
          <Button
            size="sm"
            variant="ghost"
            icon={<RotateCcw />}
            onClick={() => void catalog.refetch()}
          >
            {copy.reload}
          </Button>
        </p>
      ) : !catalog.data ? (
        <p role="status" className={styles.muted}>
          {th.common.loading}
        </p>
      ) : (
        <CharmsBody catalog={catalog.data} adminMode={adminMode} />
      )}
    </TeacherPage>
  )
}

function CharmsBody({ catalog, adminMode }: { catalog: Catalog; adminMode: boolean }) {
  const [draft, setDraft] = useState<CharmDraft>(() =>
    catalog.charms[0] ? draftOf(catalog.charms[0]) : newDraft(),
  )
  const panelRef = useRef<HTMLElement>(null)

  const select = (next: CharmDraft) => {
    setDraft(next)
    // จอแคบ: ฟอร์มอยู่ใต้รายการ — เลื่อนไปที่ฟอร์ม (UX 11 ข้อเสนอ)
    const panel = panelRef.current
    if (panel && window.matchMedia('(max-width: 959.98px)').matches)
      panel.scrollIntoView({ block: 'start', behavior: 'smooth' })
  }

  return (
    <>
      <div className={styles.head}>
        <div>
          <span className={styles.eyebrow}>{copy.eyebrow}</span>
          <h1>{copy.title}</h1>
          <p>{copy.intro}</p>
        </div>
        <Button icon={<Plus />} onClick={() => select(newDraft())}>
          {copy.add}
        </Button>
      </div>
      <div className={styles.layout}>
        <div className={styles.mainCol}>
          <RatesPanel catalog={catalog} adminMode={adminMode} />
          <section className={styles.panel} aria-labelledby="charmList">
            <div className={styles.panelHead}>
              <h2 id="charmList">{copy.listTitle}</h2>
              <span className={styles.muted}>{copy.listCount(catalog.charms.length)}</span>
            </div>
            <p className={styles.note}>
              <Pencil aria-hidden="true" />
              <span>{copy.draftNote}</span>
            </p>
            <div className={styles.catGrid}>
              {catalog.charms.map((c) => {
                const rarity = catalog.rarities.find((r) => r.id === c.rarity_id)
                return (
                  <button
                    key={c.id}
                    type="button"
                    className={styles.catCard}
                    aria-pressed={draft.id === c.id}
                    onClick={() => select(draftOf(c))}
                  >
                    <Medal rarityId={c.rarity_id} symbol={c.symbol} size={64} />
                    <b>{c.name}</b>
                    <span className={cx(rewardStyles.tierChip, CHIP[tierOf(c.rarity_id)])}>
                      {rarity?.name}
                    </span>
                    <span className={styles.owners}>{copy.owners(c.owners)}</span>
                  </button>
                )
              })}
              <button
                type="button"
                className={cx(styles.catCard, styles.catAdd)}
                aria-pressed={draft.id === null}
                onClick={() => select(newDraft())}
              >
                <Plus aria-hidden="true" />
                <b>{copy.add}</b>
              </button>
            </div>
          </section>
        </div>
        <EditPanel
          key={draft.id ?? 'new'}
          ref={panelRef}
          draft={draft}
          setDraft={setDraft}
          catalog={catalog}
          adminMode={adminMode}
        />
      </div>
    </>
  )
}

function RatesPanel({ catalog, adminMode }: { catalog: Catalog; adminMode: boolean }) {
  const queryClient = useQueryClient()
  const toast = useToast()
  const [draft, setDraft] = useState<Record<number, string>>(() =>
    Object.fromEntries(catalog.rarities.map((r) => [r.id, String(r.weight)])),
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const state = ratesState(catalog.rarities, draft)

  const save = async () => {
    if (!state.canSave || saving) return
    setSaving(true)
    setError(null)
    try {
      await saveRarityWeights(state.weights, catalog.weights_key, adminMode)
      toast(copy.ratesSaved, { tone: 'success' })
      await queryClient.invalidateQueries({ queryKey: ['charm-catalog'] })
    } catch (e) {
      setError(appErrorOf(e))
    } finally {
      setSaving(false)
    }
  }

  const reload = async () => {
    setError(null)
    const fresh = await queryClient.fetchQuery({ ...catalogQuery(adminMode), staleTime: 0 })
    setDraft(Object.fromEntries(fresh.rarities.map((r) => [r.id, String(r.weight)])))
  }

  return (
    <section className={styles.panel} aria-labelledby="ratesTitle">
      <h2 id="ratesTitle">{copy.ratesTitle}</h2>
      <div className={styles.rateEdit}>
        {catalog.rarities.map((r) => {
          const tier = tierOf(r.id)
          const value = draft[r.id] ?? ''
          const width = Math.min(100, Math.max(0, Number.parseInt(value, 10) || 0))
          return (
            <div key={r.id} className={styles.rateRow}>
              <span className={cx(rewardStyles.tierChip, CHIP[tier])}>{r.name}</span>
              <span className={styles.barWrap}>
                <span className={styles.bar} aria-hidden="true">
                  <i className={DOT[tier]} style={{ width: `${width}%` }} />
                </span>
                <span className={styles.muted}>{copy.tierCount(r.count)}</span>
              </span>
              <span className={styles.pin}>
                <Input
                  inputMode="numeric"
                  value={value}
                  aria-label={copy.rateAria(r.name)}
                  onChange={(e) =>
                    setDraft((d) => ({
                      ...d,
                      [r.id]: e.target.value.replace(/[^0-9]/g, '').slice(0, 3),
                    }))
                  }
                />
                %
              </span>
            </div>
          )
        })}
      </div>
      <div className={styles.sumLine}>
        <span className={styles.sumChip} data-ok={state.sum === 100} role="status">
          {state.sum === 100 ? (
            <CircleCheck aria-hidden="true" />
          ) : (
            <TriangleAlert aria-hidden="true" />
          )}
          {state.sum === 100 ? copy.sum(state.sum) : copy.sumBad(state.sum)}
        </span>
        <Button
          size="sm"
          variant="soft"
          disabled={!state.canSave || saving}
          onClick={() => void save()}
        >
          {saving ? copy.savingRates : copy.saveRates}
        </Button>
      </div>
      {error && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error.code === 'stale_revision'
              ? copy.stale
              : error.code === 'rates_must_total_100'
                ? `${error.message} ${copy.sumNow(state.sum)}`
                : error.message}
            {error.ref && ` (${th.errors.reference(error.ref)})`}
          </span>
          {error.code === 'stale_revision' && (
            <Button size="sm" variant="ghost" icon={<RotateCcw />} onClick={() => void reload()}>
              {copy.reload}
            </Button>
          )}
        </p>
      )}
      <span className={styles.hint}>{copy.ratesHint}</span>
    </section>
  )
}

function EditPanel({
  ref,
  draft,
  setDraft,
  catalog,
  adminMode,
}: {
  ref: Ref<HTMLElement>
  draft: CharmDraft
  setDraft: Dispatch<SetStateAction<CharmDraft>>
  catalog: Catalog
  adminMode: boolean
}) {
  const queryClient = useQueryClient()
  const toast = useToast()
  const requestKey = useRequestKey()
  const fileRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const [imageError, setImageError] = useState<string | null>(null)
  const current: AdminCharm | undefined = catalog.charms.find((c) => c.id === draft.id)
  const isNew = draft.id === null
  const tier = tierOf(draft.rarityId)
  const previewUrl = draft.image.kind === 'new' ? draft.image.previewUrl : null

  // คืนหน่วยความจำของรูปตัวอย่างเมื่อเปลี่ยนรูป/ปิดฟอร์ม
  useEffect(() => {
    if (!previewUrl) return
    return () => URL.revokeObjectURL(previewUrl)
  }, [previewUrl])

  const set = (patch: Partial<CharmDraft>) => setDraft((d) => ({ ...d, ...patch }))

  const pick = async (file: File | undefined) => {
    if (!file) return
    setImageError(null)
    setUploading(true)
    try {
      const blob = await prepareCharmImage(file)
      let assetId: string | null = null
      let failure: AppError | null = null
      await uploadSet(
        [{ id: 'charm', blob, name: 'charm.png', type: 'image/png' }],
        { purpose: 'charm', classroomId: null, postId: null, adminMode },
        crypto.randomUUID(),
        defaultUploadDeps,
        (event) => {
          if (event.phase === 'done') assetId = event.assetId
          if (event.phase === 'failed') failure = event.error
        },
      )
      if (!assetId) {
        const err = failure as AppError | null
        setImageError(err ? err.message : th.errors.fallback)
        return
      }
      set({ image: { kind: 'new', assetId, previewUrl: URL.createObjectURL(blob) } })
    } catch (e) {
      setImageError(e instanceof CharmImageError ? e.message : appErrorOf(e).message)
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  const save = async () => {
    if (!canSaveDraft(draft) || saving || uploading) return
    const input = toInput(draft)
    setSaving(true)
    setError(null)
    try {
      const saved = await saveCharm(
        input,
        draft.version,
        requestKey.keyFor(JSON.stringify([input, draft.version])),
        adminMode,
      )
      requestKey.reset()
      toast(copy.saved(saved.name), { tone: 'success' })
      await queryClient.invalidateQueries({ queryKey: ['charm-catalog'] })
      setDraft(draftOf(saved))
    } catch (e) {
      setError(appErrorOf(e))
    } finally {
      setSaving(false)
    }
  }

  const reload = async () => {
    setError(null)
    requestKey.reset()
    const fresh = await queryClient.fetchQuery({ ...catalogQuery(adminMode), staleTime: 0 })
    const latest = fresh.charms.find((c) => c.id === draft.id)
    if (latest) setDraft(draftOf(latest))
  }

  const medal = previewUrl ? (
    <img src={previewUrl} alt="" className={styles.previewImg} width={96} height={96} />
  ) : (
    <Medal rarityId={draft.rarityId} symbol={previewSymbol(draft, current)} size={96} />
  )
  const smallMedal = previewUrl ? (
    <img src={previewUrl} alt="" className={styles.previewImg} width={64} height={64} />
  ) : (
    <Medal rarityId={draft.rarityId} symbol={previewSymbol(draft, current)} size={64} />
  )
  const hasUploaded = !!current?.image_asset_id && draft.image.kind !== 'remove'

  return (
    <aside ref={ref} className={cx(styles.panel, styles.editPanel)} aria-labelledby="charmEdit">
      <h2 id="charmEdit">{isNew ? copy.newTitle : copy.editTitle(current?.name ?? draft.name)}</h2>
      <div className={styles.editMedal}>
        {medal}
        <div className={styles.imageActions}>
          <input
            ref={fileRef}
            type="file"
            accept="image/png,image/jpeg"
            className="sr-only"
            tabIndex={-1}
            aria-hidden="true"
            onChange={(e) => void pick(e.target.files?.[0])}
          />
          <Button
            size="sm"
            variant="ghost"
            icon={<ImageUp />}
            disabled={uploading || saving}
            onClick={() => fileRef.current?.click()}
          >
            {uploading ? copy.uploading : copy.upload}
          </Button>
          {(draft.image.kind === 'new' || hasUploaded) && (
            <Button
              size="sm"
              variant="ghost"
              icon={<Undo2 />}
              disabled={uploading || saving}
              onClick={() =>
                set({ image: current?.image_asset_id ? { kind: 'remove' } : { kind: 'keep' } })
              }
            >
              {copy.removeImage}
            </Button>
          )}
          <span className={styles.hint}>
            {draft.image.kind === 'new'
              ? copy.imageNew
              : hasUploaded
                ? copy.imageKeep
                : copy.imageHintDrawn}
            {' · '}
            {copy.imageHintCrop}
          </span>
          {imageError && (
            <span className={styles.fieldError} role="alert">
              <TriangleAlert aria-hidden="true" />
              {imageError}
            </span>
          )}
        </div>
      </div>
      <Field label={copy.name}>
        <Input
          value={draft.name}
          maxLength={NAME_MAX}
          placeholder={copy.namePlaceholder}
          onChange={(e) => set({ name: e.target.value })}
        />
      </Field>
      <Field
        label={
          <span className={styles.lblRow}>
            {copy.desc}
            <span className={styles.counter}>{copy.descCount(draft.description.length)}</span>
          </span>
        }
        hint={copy.descHint}
      >
        <Textarea
          rows={4}
          value={draft.description}
          maxLength={DESC_MAX}
          placeholder={copy.descPlaceholder}
          onChange={(e) => set({ description: e.target.value })}
        />
      </Field>
      <div className={styles.tierField} role="group" aria-labelledby="tierLbl">
        <span id="tierLbl" className={styles.lbl}>
          {copy.tier}
        </span>
        <div className={styles.tierPick}>
          {catalog.rarities.map((r) => (
            <button
              key={r.id}
              type="button"
              className={CHIP[tierOf(r.id)]}
              aria-pressed={draft.rarityId === r.id}
              onClick={() => set({ rarityId: r.id })}
            >
              {r.name}
            </button>
          ))}
        </div>
      </div>
      <div className={styles.preview}>
        <span className={styles.eyebrow}>{copy.previewEyebrow}</span>
        <div className={styles.previewCard}>
          {smallMedal}
          <div>
            <span className={cx(rewardStyles.tierChip, CHIP[tier])}>
              {catalog.rarities.find((r) => r.id === draft.rarityId)?.name}
            </span>
            <b>{draft.name.trim() || copy.previewName}</b>
            <p data-empty={!draft.description.trim()}>
              {draft.description.trim() || copy.previewDesc}
            </p>
          </div>
        </div>
      </div>
      <p className={styles.note}>
        <Info aria-hidden="true" />
        <span>{isNew ? copy.noteNew : copy.noteEdit}</span>
      </p>
      {error && (
        <p className={styles.alert} role="alert">
          <TriangleAlert aria-hidden="true" />
          <span>
            {error.code === 'stale_revision' ? copy.stale : error.message}
            {error.ref && ` (${th.errors.reference(error.ref)})`}
          </span>
          {error.code === 'stale_revision' && (
            <Button size="sm" variant="ghost" icon={<RotateCcw />} onClick={() => void reload()}>
              {copy.reload}
            </Button>
          )}
        </p>
      )}
      <Button
        icon={<Check />}
        disabled={!canSaveDraft(draft) || saving || uploading}
        onClick={() => void save()}
      >
        {saving ? copy.saving : isNew ? copy.saveNew : copy.saveEdit}
      </Button>
      <span className={styles.hint}>{copy.noDelete}</span>
    </aside>
  )
}
