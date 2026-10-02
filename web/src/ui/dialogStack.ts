// กล่อง (<dialog>) ที่เปิดอยู่ เรียงจากล่างขึ้นบน — ใช้ตัดสินว่า Esc/Tab และ toast เป็นของกล่องไหน
const stack: HTMLDialogElement[] = []
const listeners = new Set<() => void>()

const emit = () => listeners.forEach((l) => l())

export function pushDialog(dialog: HTMLDialogElement) {
  stack.push(dialog)
  emit()
}

export function removeDialog(dialog: HTMLDialogElement) {
  const i = stack.indexOf(dialog)
  if (i >= 0) stack.splice(i, 1)
  emit()
}

export function topDialog(): HTMLDialogElement | null {
  return stack.at(-1) ?? null
}

export function subscribeDialogs(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
