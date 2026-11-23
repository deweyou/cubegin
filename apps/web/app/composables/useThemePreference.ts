export function useThemePreference() {
  return useState<'light' | 'dark' | undefined>('theme-preference')
}
