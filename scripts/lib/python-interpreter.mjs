// One interpreter choice for every repository tool that shells out to Python
// (#3629, #3795). Linux hosts ship `python3` without a bare `python`; Windows
// ships `python`. An explicit PYTHON environment variable always wins.
export function pythonInterpreter({ env = process.env, platform = process.platform } = {}) {
  if (env.PYTHON) return env.PYTHON
  return platform === 'win32' ? 'python' : 'python3'
}
