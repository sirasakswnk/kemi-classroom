import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, BadgeCheck, RotateCcw, Sparkles } from 'lucide-react'
import { useId, useRef, useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { Button, useToast } from '../../ui'
import { DialogBase } from '../../ui/DialogBase'
import { useRequestKey } from '../review/useRequestKey'
import {
  collectionQuery,
  drawCharm,
  drawOptionsQuery,
  setEquipment,
  type DrawOptions,
  type DrawResult,
} from './api'
import { Coin, Medal } from './Medal'
import {
  drawButton,
  drawErrorText,
  fmtPct,
  reloadsOptions,
  tierOf,
  weightsText,
} from './rewardState'
import styles from './rewards.module.css'
import { useCharmImages } from '../charms/charmImages'

const copy = th.rewards
const TIER = [styles.tier0, styles.tier1, styles.tier2, styles.tier3]
const CHIP = [styles.chip0, styles.chip1, styles.chip2, styles.chip3]
const GLYPHS = ['⇌', 'Au', 'e⁻', 'H₂O', 'mol', '∞', '♡', '✎']
/** เวลาลุ้นขั้นต่ำก่อนเปิดผล — ปิดเมื่ออุปกรณ์ตั้งลดการเคลื่อนไหว */
const CHARGE_MS = 900

const reducedMotion = () =>
  typeof window.matchMedia === 'function' &&
  window.matchMedia('(prefers-reduced-motion: reduce)').matches

// S04 หอสุ่มเครื่องราง (UX 11; แบบ v2 sDraw/revealCard)
// อัตราที่แสดง = อัตราจริงจาก get_draw_options (K6) และส่ง rates_key กลับไปตอนสุ่ม — อัตราเปลี่ยนแล้วเซิร์ฟเวอร์ตอบ
// stale_revision จึงไม่มีการสุ่มด้วยอัตราที่นักเรียนไม่เห็น; กำลังสุ่มปุ่มกดซ้ำไม่ได้; เน็ตหลุดกดลองใหม่ใช้ key เดิม
export default function DrawPage() {
  const queryClient = useQueryClient()
  const options = useQuery(drawOptionsQuery)
  const requestKey = useRequestKey()
  const [drawing, setDrawing] = useState(false)
  const [error, setError] = useState<{ err: AppError; latest: number | null } | null>(null)
  const [result, setResult] = useState<DrawResult | null>(null)
  const busy = useRef(false)

  const draw = async (o: DrawOptions) => {
    if (busy.current || o.status !== 'ok') return
    busy.current = true
    setDrawing(true)
    setError(null)
    const started = performance.now()
    try {
      const res = await drawCharm(o.rates_key, requestKey.keyFor(o.rates_key))
      requestKey.reset()
      const wait = reducedMotion() ? 0 : CHARGE_MS - (performance.now() - started)
      if (wait > 0) await new Promise((r) => setTimeout(r, wait))
      setResult(res)
      void queryClient.invalidateQueries({ queryKey: ['collection'] })
      await queryClient.invalidateQueries({ queryKey: ['draw-options'] })
    } catch (e) {
      const err = appErrorOf(e)
      let latest: number | null = null
      if (reloadsOptions(err.code)) {
        requestKey.reset()
        const fresh = await options.refetch()
        latest = fresh.data?.balance ?? null
      }
      setError({ err, latest })
    } finally {
      busy.current = false
      setDrawing(false)
    }
  }

  const o = options.data
  return (
    <main className={styles.layout}>
      <section className={styles.wrap} aria-labelledby="drawTitle">
        <Link to="/" className={styles.back}>
          <ArrowLeft aria-hidden="true" />
          {copy.back}
        </Link>
        <div className={styles.title}>
          <h1 id="drawTitle">{copy.title}</h1>
          <p>{copy.subtitle}</p>
        </div>
        <div className={styles.altar} aria-hidden="true">
          <span className={styles.ring} />
          <span className={styles.ring} data-r="2" />
          <span className={styles.ring} data-r="3" />
          <div className={styles.glyphs}>
            {GLYPHS.map((g, k) => {
              const a = (k * Math.PI) / 4 - Math.PI / 2
              return (
                <span
                  key={g}
                  style={{
                    transform: `translate(-50%,-50%) translate(${(Math.cos(a) * 104).toFixed(1)}px,${(Math.sin(a) * 104).toFixed(1)}px)`,
                  }}
                >
                  {g}
                </span>
              )
            })}
          </div>
          <div className={styles.orb} data-charging={drawing}>
            {o?.status === 'completed' ? '✓' : '?'}
          </div>
        </div>
        {o ? (
          <DrawCta options={o} drawing={drawing} onDraw={() => void draw(o)} />
        ) : options.isError ? (
          <div className={styles.cta}>
            <p className={styles.error} role="alert">
              {copy.loadFailed} · {appErrorOf(options.error).message}
              <Button
                size="sm"
                variant="soft"
                icon={<RotateCcw />}
                onClick={() => void options.refetch()}
              >
                {copy.retry}
              </Button>
            </p>
          </div>
        ) : null}
        {error && o && (
          <div className={styles.cta}>
            <p className={styles.error} role="alert">
              <span>
                {drawErrorText(error.err.code, error.err.message, error.latest)}
                {error.err.ref && <small> ({th.errors.reference(error.err.ref)})</small>}
              </span>
              {!reloadsOptions(error.err.code) && o.status === 'ok' && (
                <Button
                  size="sm"
                  variant="soft"
                  icon={<RotateCcw />}
                  disabled={drawing}
                  onClick={() => void draw(o)}
                >
                  {copy.retryDraw}
                </Button>
              )}
            </p>
          </div>
        )}
      </section>

      <div className={styles.side}>
        {o ? <Rates options={o} /> : <div className={styles.skel} aria-hidden="true" />}
        {o && (
          <Link to="/collection" className={cx(styles.card, styles.equipBar)}>
            <Coin size={40} />
            <span>
              <b>{copy.collection(o.owned, o.total)}</b>
              <span>{copy.collectionHint}</span>
            </span>
          </Link>
        )}
      </div>

      {result && <Reveal result={result} onClose={() => setResult(null)} />}
    </main>
  )
}

function DrawCta({
  options,
  drawing,
  onDraw,
}: {
  options: DrawOptions
  drawing: boolean
  onDraw: () => void
}) {
  const btn = drawButton(options, drawing)
  const whyId = useId()
  return (
    <div className={styles.cta}>
      <span className={styles.have}>
        <Coin size={22} />
        {copy.have} <b>{options.balance}</b> {copy.unit}
      </span>
      <Button
        variant="gold"
        className={styles.drawBtn}
        icon={drawing ? undefined : <Sparkles />}
        disabled={btn.disabled}
        aria-busy={drawing}
        aria-describedby={btn.why ? whyId : undefined}
        onClick={onDraw}
      >
        {btn.label}
      </Button>
      {btn.why && (
        <span id={whyId} className={styles.why}>
          {btn.why}
        </span>
      )}
    </div>
  )
}

function Rates({ options }: { options: DrawOptions }) {
  return (
    <section aria-labelledby="ratesTitle">
      <div className={cx(styles.card, styles.rates)}>
        <h2 id="ratesTitle">{copy.ratesTitle}</h2>
        {options.levels.map((l) => {
          const out = l.remaining === 0
          const tier = TIER[tierOf(l.rarity_id)]
          return (
            <div key={l.rarity_id} className={styles.rateRow} data-out={out}>
              <span className={cx(styles.dot, tier)} aria-hidden="true" />
              <span>
                {l.name}
                <span className={styles.rm}>{copy.remaining(l.remaining, l.total)}</span>
              </span>
              <b>{fmtPct(l.pct)}</b>
              <span className={styles.bar} aria-hidden="true">
                <i className={tier} style={{ width: `${l.pct}%` }} />
              </span>
            </div>
          )
        })}
        <p>{copy.ratesNote(weightsText(options))}</p>
      </div>
    </section>
  )
}

function Reveal({ result, onClose }: { result: DrawResult; onClose: () => void }) {
  const queryClient = useQueryClient()
  const toast = useToast()
  const id = useId()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const { charm } = result
  // ผลสุ่มไม่มีรูป — ใช้รูปจากตู้สะสมที่โหลดใหม่หลังสุ่ม (ไม่มี = เหรียญวาด)
  const collection = useQuery(collectionQuery)
  const slot = collection.data?.items.find((s) => s.owned && s.charm_id === charm.id)
  const imageId = slot?.owned ? slot.image_asset_id : null
  const images = useCharmImages([imageId])
  const tier = tierOf(charm.rarity_id)

  const equip = async () => {
    if (saving) return
    setSaving(true)
    setError(null)
    try {
      await setEquipment(charm.id)
      void queryClient.invalidateQueries({ queryKey: ['collection'] })
      void queryClient.invalidateQueries({ queryKey: ['classroom-view'] })
      toast(copy.equipped(charm.name), { tone: 'success' })
      onClose()
    } catch (e) {
      setError(appErrorOf(e))
      setSaving(false)
    }
  }

  return (
    <DialogBase
      open
      onClose={onClose}
      dismissible
      labelledBy={`${id}name`}
      describedBy={`${id}desc`}
      className={styles.reveal}
    >
      <div className={styles.revealBody} aria-label={copy.revealLabel}>
        <span className={styles.revealEyebrow}>{copy.revealEyebrow}</span>
        <Medal
          rarityId={charm.rarity_id}
          symbol={charm.symbol}
          size={150}
          image={imageId ? images.get(imageId) : null}
          className={styles.bigMedal}
        />
        <span className={cx(styles.tierChip, CHIP[tier])}>{charm.rarity_name}</span>
        <h2 id={`${id}name`}>{charm.name}</h2>
        <p id={`${id}desc`}>{charm.description}</p>
        {error && (
          <p className={styles.error} role="alert">
            {error.message}
            {error.ref && <small> ({th.errors.reference(error.ref)})</small>}
          </p>
        )}
        <div className={styles.revealRow}>
          <Button variant="ghost" className={styles.ghostDark} onClick={onClose}>
            {copy.keep}
          </Button>
          <Button
            variant="gold"
            icon={<BadgeCheck />}
            disabled={saving}
            onClick={() => void equip()}
          >
            {saving ? copy.equipping : copy.equip}
          </Button>
        </div>
      </div>
    </DialogBase>
  )
}
