/** ชื่อจาก “ชื่อ นามสกุล” สำหรับคำทักทาย */
export const firstName = (displayName: string): string => displayName.trim().split(/\s+/)[0] ?? ''
