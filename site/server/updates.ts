// Shared by the Pages Functions in functions/; outside it, so it is no route itself.
// They serve the sugu-updates bucket at the paths it was served at before the
// site moved here, so installed copies and old links keep working (ADR 0006).

export interface Env {
  UPDATES: R2Bucket;
}

const immutable = 'public, max-age=31536000, immutable';

/** How each kind of object is served. */
function kind(key: string): { type: string; cache: string; download?: boolean } | undefined {
  if (key === 'appcast.xml') return { type: 'application/xml', cache: 'no-cache' };
  if (key === 'latest.json' || key === 'releases.json') return { type: 'application/json', cache: 'no-cache' };
  if (/^releases\/\d+\.\d+\.\d+\/Sugu-\d+\.\d+\.\d+\.(pkg|zip)$/.test(key)) {
    return { type: 'application/octet-stream', cache: immutable, download: true };
  }
  // Named with their checksum's start, so a name is never reused.
  if (/^models\/[a-z0-9-]+-[0-9a-f]{8}\.(gram|gguf|zip)$/.test(key)) {
    return { type: 'application/octet-stream', cache: immutable, download: true };
  }
  if (/^releases\/\d+\.\d+\.\d+\/notes\/(en|ja|zh-Hans|zh-Hant)\.md$/.test(key)) {
    return { type: 'text/markdown; charset=utf-8', cache: 'no-cache' };
  }
  return undefined;
}

/**
 * An object from the bucket, for GET and HEAD, with a single range (resumed
 * downloads) and conditional requests; anything else is not found.
 * Preconditions and ranges are read here rather than by R2, so each failure
 * gets its own status: 304, 412 or 416.
 */
export async function serve(request: Request, env: Env, key: string): Promise<Response> {
  const served = kind(key);
  if (!served) return new Response('Not found', { status: 404 });
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
  }
  const head = await env.UPDATES.head(key);
  if (!head) return new Response('Not found', { status: 404 });
  const headers = new Headers({
    'Content-Type': served.type,
    'Cache-Control': served.cache,
    'Accept-Ranges': 'bytes',
    ETag: head.httpEtag,
    'Last-Modified': head.uploaded.toUTCString(),
    'X-Content-Type-Options': 'nosniff',
  });
  if (served.download) headers.set('Content-Disposition', `attachment; filename="${key.split('/').pop()}"`);

  const status = precondition(request.headers, head);
  if (status) return new Response(null, { status, headers });

  let range = requestedRange(request.headers, head);
  if (range === 'unsatisfiable') {
    headers.set('Content-Range', `bytes */${head.size}`);
    return new Response(null, { status: 416, headers });
  }
  if (range && range.start === 0 && range.length === head.size) range = undefined;
  if (range) headers.set('Content-Range', `bytes ${range.start}-${range.start + range.length - 1}/${head.size}`);
  headers.set('Content-Length', String(range ? range.length : head.size));
  if (request.method === 'HEAD') return new Response(null, { status: range ? 206 : 200, headers });

  // The same object the headers describe, or none if it changed since.
  const object = await env.UPDATES.get(key, {
    onlyIf: { etagMatches: head.etag },
    ...(range ? { range: { offset: range.start, length: range.length } } : {}),
  });
  if (!object || !('body' in object)) {
    return new Response('Changed while being read', { status: 503, headers: { 'Retry-After': '1' } });
  }
  return new Response((object as R2ObjectBody).body, { status: range ? 206 : 200, headers });
}

/** 412 when a precondition fails, 304 when the client's copy is current. */
function precondition(request: Headers, object: R2Object): 304 | 412 | undefined {
  const etag = object.httpEtag;
  // Whole seconds, as HTTP dates carry.
  const modified = Math.floor(object.uploaded.getTime() / 1000) * 1000;
  const ifMatch = request.get('If-Match');
  if (ifMatch !== null) {
    if (!matches(ifMatch, etag, false)) return 412;
  } else {
    const since = date(request.get('If-Unmodified-Since'));
    if (since !== undefined && modified > since) return 412;
  }
  const ifNoneMatch = request.get('If-None-Match');
  if (ifNoneMatch !== null) {
    if (matches(ifNoneMatch, etag, true)) return 304;
  } else {
    const since = date(request.get('If-Modified-Since'));
    if (since !== undefined && modified <= since) return 304;
  }
  return undefined;
}

/** Whether a list of entity tags names `etag`; weak tags count when `weak`. */
function matches(list: string, etag: string, weak: boolean): boolean {
  if (list.trim() === '*') return true;
  const strip = (tag: string) => (weak ? tag.replace(/^W\//, '') : tag);
  return list.split(',').some((tag) => {
    const candidate = tag.trim();
    if (!weak && candidate.startsWith('W/')) return false;
    return strip(candidate) === strip(etag);
  });
}

function date(value: string | null): number | undefined {
  if (value === null) return undefined;
  const time = Date.parse(value);
  return Number.isNaN(time) ? undefined : time;
}

/**
 * The one byte range asked for. Several ranges, a malformed header, or an
 * If-Range for another version get the whole object, as HTTP allows.
 */
function requestedRange(request: Headers, object: R2Object): { start: number; length: number } | 'unsatisfiable' | undefined {
  const header = request.get('Range');
  if (header === null) return undefined;
  const ifRange = request.get('If-Range');
  if (ifRange !== null && ifRange.trim() !== object.httpEtag) return undefined;
  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim());
  if (!match || (match[1] === '' && match[2] === '')) return undefined;
  const size = object.size;
  if (match[1] === '') {
    // The last n bytes.
    const length = Math.min(Number(match[2]), size);
    return length === 0 ? 'unsatisfiable' : { start: size - length, length };
  }
  const start = Number(match[1]);
  if (start >= size) return 'unsatisfiable';
  const end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
  if (end < start) return undefined;
  return { start, length: end - start + 1 };
}
