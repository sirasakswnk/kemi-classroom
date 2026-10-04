import { toAppError, type AppError } from './supabase'
import type { z } from './zod'

// เรียก Supabase (ตาราง/RPC) แล้วตรวจรูปแบบผลด้วย zod — ผิดพลาดโยนเป็น RequestError ที่แปลงตาม UX 7.1 แล้ว
// ใช้กับ TanStack Query (queryFn/mutationFn โยนข้อผิดพลาดได้)
/** ผิดพลาดจาก Supabase ที่แปลงตาม UX 7.1 แล้ว — ใช้กับ TanStack Query (throw ได้) */
export class RequestError extends Error {
  readonly appError: AppError
  constructor(appError: AppError) {
    super(appError.message)
    this.appError = appError
  }
}

export async function run<T>(
  request: PromiseLike<{ data: unknown; error: unknown }>,
  schema: z.ZodType<T>,
): Promise<T> {
  let result: { data: unknown; error: unknown }
  try {
    result = await request
  } catch (error) {
    throw new RequestError(toAppError(error))
  }
  if (result.error) throw new RequestError(toAppError(result.error))
  const parsed = schema.safeParse(result.data)
  if (!parsed.success) throw new RequestError(toAppError({ name: 'InvalidResponse' }))
  return parsed.data
}

export function appErrorOf(error: unknown): AppError {
  return error instanceof RequestError ? error.appError : toAppError(error)
}
