// One project-owned interpreter choice for Node tools that run Python diagnostics.
// Callers keep their existing fail-closed handling if the chosen binary is absent.
export function pythonExecutable({ platform = process.platform, env = process.env } = {}) {
  return env.PYTHON?.trim() || (platform === 'win32' ? 'python' : 'python3')
}
