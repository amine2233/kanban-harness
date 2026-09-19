export function folderName(path: string): string {
  const last = path
    .replace(/[\\/]+$/, '')
    .split(/[\\/]/)
    .pop()
  return last === undefined || last === '' ? 'project' : last
}
