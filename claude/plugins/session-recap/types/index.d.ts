export type Recap = { text: string; isStale: boolean }

declare module 'claude-code' {
  interface PluginState {
    'session-recap': { recap: Recap | null }
  }
}
