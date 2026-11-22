export const themeStorageKey = 'cubegin.web.theme'

export const initialThemeScript = `
  try {
    const theme = localStorage.getItem(${JSON.stringify(themeStorageKey)})
    if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme
  } catch {}
`
