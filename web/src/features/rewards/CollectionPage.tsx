import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, BadgeCheck, CalendarDays, Check, Eye, EyeOff, RotateCcw } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router'
import { th } from '../../copy/th'
import { cx } from '../../lib/cx'
import { appErrorOf } from '../../lib/request'
import type { AppError } from '../../lib/supabase'
import { thaiDate } from '../../lib/thaiTime'
import { Button, Sheet, useToast } from '../../ui'
import { collectionQuery, setEquipment, type OwnedSlot } from './api'
import { Medal } from './Medal'
import { tierOf } from './rewardState'
import styles from './rewards.module.css'

const copy = th.rewards
const CHIP = [styles.chip0, styles.chip1, styles.chip2, styles.chip3]
const GLOW = [styles.glow0, styles.glow1, styles.glow2, styles.glow3]

// S05 ตู้สะสมส่วนตัว (UX 11; แบบ v2 sCollection/charmSheet)
// ช่องที่ยังไม่ได้รับแสดงแบบปิด (“?” + “ยังไม่ได้รับ” + ระดับ) และกดไม่ได้ — เซิร์ฟเวอร์ไม่ส่งชื่อ/รูป/คำอธิบายของช่องนั้น
// กดชิ้นที่มีแล้ว → แผ่นคำอธิบาย วันที่ได้รับ และปุ่มแสดงข้างชื่อ (เลือกได้ชิ้นเดียว)
export default function CollectionPage() {
  const collection = useQuery(collectionQuery)
  const [open, setOpen] = useState<OwnedSlot | null>(null)

  const c = collection.data
  return (
    <main className={styles.colPage}>
      <Link to="/draw" className={styles.colBack}>
        <ArrowLeft aria-hidden="true" />
        {copy.backToDraw}
      </Link>
      <div className={styles.colHead}>
        <h1>{copy.colTitle}</h1>
        {c && (
          <>
            <div className={styles.colProgress}>
              <span>{copy.colProgress}</span>
              <b>
                {c.owned} / {c.total}
              </b>
            </div>
            <div className={styles.meter} aria-hidden="true">
              <i style={{ width: `${c.total ? (c.owned / c.total) * 100 : 0}%` }} />
            </div>
          </>
        )}
      </div>
      <p className={styles.colNote}>
        <Eye aria-hidden="true" />
        <span>{copy.colNote}</span>
      </p>

      {collection.isError ? (
        <p className={styles.colError} role="alert">
          {appErrorOf(collection.error).message}
          <Button
            size="sm"
            variant="soft"
            icon={<RotateCcw />}
            onClick={() => void collection.refetch()}
          >
            {copy.retry}
          </Button>
        </p>
      ) : !c ? (
        <div className={styles.skel} aria-hidden="true" />
      ) : (
        <ul className={styles.colGrid}>
          {c.items.map((slot) => {
            const tier = tierOf(slot.rarity_id)
            if (!slot.owned)
              return (
                <li
                  key={slot.position}
                  className={cx(styles.tile, styles.tileLocked)}
                  aria-label={copy.lockedAria(slot.rarity_name)}
                >
                  <LockedMedal />
                  <b>{copy.locked}</b>
                  <span className={cx(styles.tierChip, CHIP[tier])}>{slot.rarity_name}</span>
                </li>
              )
            const on = slot.charm_id === c.equipped_charm_id
            return (
              <li key={slot.position}>
                <button
                  type="button"
                  className={styles.tile}
                  data-equipped={on}
                  aria-haspopup="dialog"
                  aria-label={copy.tileAria(slot.name, slot.rarity_name, on)}
                  onClick={() => setOpen(slot)}
                >
                  {on && (
                    <span className={styles.eq} aria-hidden="true">
                      <Check />
                    </span>
                  )}
                  <Medal rarityId={slot.rarity_id} symbol={slot.symbol} size={84} />
                  <b>{slot.name}</b>
                  <span className={cx(styles.tierChip, CHIP[tier])}>{slot.rarity_name}</span>
                </button>
              </li>
            )
          })}
        </ul>
      )}

      {open && c && (
        <CharmSheet
          slot={open}
          equipped={open.charm_id === c.equipped_charm_id}
          onClose={() => setOpen(null)}
        />
      )}
    </main>
  )
}

function LockedMedal() {
  return (
    <svg viewBox="0 0 100 100" width={84} height={84} aria-hidden="true">
      <circle cx="50" cy="50" r="46" fill="#E4D9C6" />
      <circle cx="50" cy="50" r="38" fill="#D6CAB6" />
      <circle
        cx="50"
        cy="50"
        r="32"
        fill="none"
        stroke="#fff"
        strokeOpacity=".6"
        strokeWidth="1.2"
        strokeDasharray="2 3"
      />
      <text
        x="50"
        y="52"
        textAnchor="middle"
        dominantBaseline="middle"
        fontFamily="Mitr, sans-serif"
        fontSize="34"
        fill="#FFFBF4"
      >
        ?
      </text>
    </svg>
  )
}

function CharmSheet({
  slot,
  equipped,
  onClose,
}: {
  slot: OwnedSlot
  equipped: boolean
  onClose: () => void
}) {
  const queryClient = useQueryClient()
  const toast = useToast()
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<AppError | null>(null)
  const tier = tierOf(slot.rarity_id)

  const save = async (charmId: string | null) => {
    if (saving) return
    setSaving(true)
    setError(null)
    try {
      await setEquipment(charmId)
      await queryClient.invalidateQueries({ queryKey: ['collection'] })
      void queryClient.invalidateQueries({ queryKey: ['classroom-view'] })
      toast(charmId ? copy.equipped(slot.name) : copy.unequipped, { tone: 'success' })
      onClose()
    } catch (e) {
      setError(appErrorOf(e))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Sheet open onClose={onClose} title={slot.name}>
      <div className={styles.sheetBody}>
        <div className={cx(styles.sheetArt, GLOW[tier])}>
          <Medal
            rarityId={slot.rarity_id}
            symbol={slot.symbol}
            size={132}
            className={styles.sheetMedal}
          />
        </div>
        <span className={cx(styles.tierChip, CHIP[tier])}>{slot.rarity_name}</span>
        <p className={styles.sheetDesc} data-empty={!slot.description}>
          {slot.description || copy.noDesc}
        </p>
        <span className={styles.sheetMeta}>
          <CalendarDays aria-hidden="true" />
          {copy.obtained(thaiDate(slot.obtained_at))}
        </span>
        {error && (
          <p className={styles.colError} role="alert">
            {error.message}
            {error.ref && <small> ({th.errors.reference(error.ref)})</small>}
          </p>
        )}
        {equipped ? (
          <>
            <Button variant="soft" block icon={<BadgeCheck />} disabled>
              {copy.equippedNow}
            </Button>
            <Button
              variant="ghost"
              block
              icon={<EyeOff />}
              disabled={saving}
              onClick={() => void save(null)}
            >
              {saving ? copy.equipping : copy.unequip}
            </Button>
          </>
        ) : (
          <Button
            block
            icon={<BadgeCheck />}
            disabled={saving}
            onClick={() => void save(slot.charm_id)}
          >
            {saving ? copy.equipping : copy.equipThis}
          </Button>
        )}
        <span className={styles.sheetHint}>{copy.sheetHint}</span>
      </div>
    </Sheet>
  )
}
