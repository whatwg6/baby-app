export class UnsafeMediaPathError extends Error {
  constructor(readonly path: string, message = '媒体路径不安全或不在 App 私有目录中') {
    super(`${message}：${path}`);
    this.name = 'UnsafeMediaPathError';
  }
}

export function normalizePrivateFilePath(path: string, root: string): string {
  try {
    const candidate = parseFileUri(path);
    const privateRoot = parseFileUri(root);
    if (candidate.protocol !== privateRoot.protocol ||
        candidate.host !== privateRoot.host ||
        candidate.username !== privateRoot.username ||
        candidate.password !== privateRoot.password ||
        candidate.port !== privateRoot.port) {
      throw new Error('scheme or authority mismatch');
    }

    const rootPath = stripTrailingSlash(privateRoot.pathname);
    const prefix = `${rootPath}/`;
    if (!candidate.pathname.startsWith(prefix) || candidate.pathname.length <= prefix.length) {
      throw new Error('path is outside the private root');
    }
    return candidate.href;
  } catch (cause) {
    if (cause instanceof UnsafeMediaPathError) {
      throw cause;
    }
    throw new UnsafeMediaPathError(path);
  }
}

export function normalizePrivateRoot(root: string): string {
  try {
    return stripTrailingSlash(parseFileUri(root).href);
  } catch {
    throw new UnsafeMediaPathError(root, 'App 私有媒体目录无效');
  }
}

function parseFileUri(value: string): URL {
  if (value.length === 0 || value.includes('\0') || value.includes('\\') ||
      value.includes('?') || value.includes('#')) {
    throw new Error('ambiguous file URI');
  }
  const decoded = decodeRepeatedly(value);
  const raw = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/([^/?#]*)(\/[^?#]*)$/.exec(decoded);
  if (raw === null) {
    throw new Error('file URI is malformed');
  }
  const rawPath = raw[3];
  if (rawPath.split('/').some((segment, index) => (
    index > 0 && (segment.length === 0 || segment === '.' || segment === '..')
  ))) {
    throw new Error('path traversal is not allowed');
  }

  const parsed = new URL(decoded);
  if (parsed.protocol !== 'file:' || parsed.search !== '' || parsed.hash !== '') {
    throw new Error('only unqualified file URIs are supported');
  }
  parsed.pathname = parsed.pathname.normalize('NFC');
  return parsed;
}

function decodeRepeatedly(value: string): string {
  let decoded = value;
  for (let pass = 0; pass < 5; pass += 1) {
    if (/%(?:2f|5c)/i.test(decoded)) {
      throw new Error('encoded path separators are not allowed');
    }
    const next = decodeURIComponent(decoded);
    if (next === decoded) {
      return decoded;
    }
    decoded = next;
  }
  throw new Error('path encoding is excessively nested');
}

function stripTrailingSlash(value: string): string {
  return value.replace(/\/+$/, '');
}
