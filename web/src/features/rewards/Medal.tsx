import { useId } from 'react'
import { tierOf } from './rewardState'

// รูปชั่วคราว (UX 11, แบบ v2 medal): เหรียญกลมสีตามระดับ มีสัญลักษณ์ตรงกลาง วาดด้วยโค้ด
// gradient ใช้ id ต่อชิ้น (useId) — หลายเหรียญในหน้าเดียวไม่ชนกัน; ตัดอักษรพิเศษออกเพื่อใช้ใน url(#…) ได้

const useSvgId = () => `m${useId().replace(/[^a-zA-Z0-9_-]/g, '')}`

const FACE = [
  ['#A9D8C5', '#5E9A85', '#3B7461'],
  ['#BCC8F7', '#6576D4', '#4150AE'],
  ['#F0B9E8', '#B558AD', '#8A2F84'],
  ['#FFF0BE', '#E7B444', '#B7801B'],
]
const RING = [
  ['#D8EDE3', '#6FA592'],
  ['#E2E7FC', '#7584D8'],
  ['#F8DDF4', '#BE6CB6'],
  ['#FFF6D9', '#D49B2E'],
]

const around = (count: number, r: number, phase = 0) =>
  Array.from({ length: count }, (_, k) => {
    const a = (k * 2 * Math.PI) / count + phase
    return [50 + r * Math.cos(a), 50 + r * Math.sin(a)] as const
  })

export function Medal({
  rarityId,
  symbol,
  size = 64,
  className,
}: {
  rarityId: number
  symbol: string
  size?: number
  className?: string
}) {
  const id = useSvgId()
  const t = tierOf(rarityId)
  const face = FACE[t] ?? FACE[0]
  const ring = RING[t] ?? RING[0]
  const fs = symbol.length > 2 ? 22 : symbol.length === 2 ? 28 : 34
  return (
    <svg className={className} viewBox="0 0 100 100" width={size} height={size} aria-hidden="true">
      <defs>
        <radialGradient id={`${id}f`} cx="38%" cy="32%" r="75%">
          <stop offset="0" stopColor={face[0]} />
          <stop offset={t === 3 ? '.55' : '.6'} stopColor={face[1]} />
          <stop offset="1" stopColor={face[2]} />
        </radialGradient>
        <linearGradient id={`${id}r`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={ring[0]} />
          <stop offset="1" stopColor={ring[1]} />
        </linearGradient>
      </defs>
      {t === 3 && (
        <g stroke="#F4CF6E" strokeOpacity=".55" strokeWidth="3" strokeLinecap="round">
          {around(16, 47).map(([x1, y1], k) => {
            const [x2, y2] = around(16, 50)[k]
            return <line key={k} x1={x1} y1={y1} x2={x2} y2={y2} />
          })}
        </g>
      )}
      <circle cx="50" cy="50" r="46" fill={`url(#${id}r)`} />
      <circle cx="50" cy="50" r="38" fill={`url(#${id}f)`} />
      {around(12, 42).map(([cx, cy], k) => (
        <circle key={k} cx={cx} cy={cy} r="1.7" fill="#fff" fillOpacity=".6" />
      ))}
      <circle
        cx="50"
        cy="50"
        r="32"
        fill="none"
        stroke="#fff"
        strokeOpacity=".45"
        strokeWidth="1.2"
        strokeDasharray="2 3"
      />
      <text
        x="50"
        y="52"
        textAnchor="middle"
        dominantBaseline="middle"
        fontFamily="Mitr, Anuphan, sans-serif"
        fontSize={fs}
        fontWeight="500"
        fill="#FFFDF7"
      >
        {symbol}
      </text>
    </svg>
  )
}

/** เหรียญโทเคน (แบบ v2 COIN) */
export function Coin({ size = 24 }: { size?: number }) {
  const id = useSvgId()
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
      <defs>
        <radialGradient id={`${id}c`} cx="35%" cy="30%" r="75%">
          <stop offset="0" stopColor="#FFF1C2" />
          <stop offset=".55" stopColor="#EDBE52" />
          <stop offset="1" stopColor="#C98A1E" />
        </radialGradient>
      </defs>
      <circle cx="12" cy="12" r="10.5" fill={`url(#${id}c)`} stroke="#B7801B" strokeWidth="1" />
      <circle
        cx="12"
        cy="12"
        r="7.6"
        fill="none"
        stroke="#FFF3CF"
        strokeOpacity=".7"
        strokeWidth=".8"
      />
      <path d="M12 6.6l1.4 3.9 3.9 1.5-3.9 1.4L12 17.4l-1.4-4-3.9-1.4 3.9-1.5z" fill="#FFF6DD" />
    </svg>
  )
}
