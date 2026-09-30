import { renderToString } from 'react-dom/server'
import { describe, expect, it } from 'vitest'
import App from './App'

describe('App', () => {
  it('แสดงชื่อระบบ', () => {
    expect(renderToString(<App />)).toContain('ห้องเคมี')
  })
})
