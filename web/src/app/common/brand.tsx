// โลโก้และลายวงเบนซีนจากแบบ v2 (LOGO, BENZENE) — ตกแต่งเท่านั้น ซ่อนจากเครื่องอ่านหน้าจอ

export function BrandLogo({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 32 32" aria-hidden="true">
      <rect width="32" height="32" rx="10" fill="#6B3FA0" />
      <path d="M10.4 21.2h11.2l1.3 2.3c.5.9-.2 2-1.2 2H10.3c-1 0-1.7-1.1-1.2-2z" fill="#E9B949" />
      <path
        d="M13 6.8h6M14.1 6.8v6.8L8.9 22.7A2.3 2.3 0 0 0 10.9 26h10.2a2.3 2.3 0 0 0 2-3.3l-5.2-9.1V6.8"
        fill="none"
        stroke="#FFF8EC"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <circle cx="15" cy="18.6" r="1.1" fill="#FFF8EC" />
      <circle cx="17.8" cy="16.4" r=".8" fill="#FFF8EC" />
    </svg>
  )
}

export function Benzene({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      viewBox="0 0 150 150"
      aria-hidden="true"
      fill="none"
      stroke="rgba(255,249,240,.35)"
      strokeWidth="2"
    >
      <polygon points="75,20 122,47 122,101 75,128 28,101 28,47" />
      <circle cx="75" cy="74" r="28" strokeDasharray="4 5" />
      <line x1="122" y1="47" x2="146" y2="33" />
      <line x1="75" y1="20" x2="75" y2="0" />
      <circle cx="146" cy="33" r="5" fill="rgba(233,185,73,.8)" stroke="none" />
      <circle cx="28" cy="101" r="4" fill="rgba(255,249,240,.5)" stroke="none" />
    </svg>
  )
}
