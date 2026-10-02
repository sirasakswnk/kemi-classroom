import '@fontsource/anuphan/400.css'
import '@fontsource/anuphan/500.css'
import '@fontsource/anuphan/600.css'
import '@fontsource/mitr/500.css'
import './styles/tokens.css'
import './styles/base.css'
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import App from './app/App'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
