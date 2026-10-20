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
  if (/^releases\/\d+\.\d+\.\d+\/notes\/(en|ja|zh-Hans|zh-Hant)\.md$/.test(key)) {
    return { type: 'text/markdown; charset=utf-8', cache: 'no-cache' };
  }
  return undefined;
}

/**
 * An object from the bucket, for GET and HEAD, with ranges (resumed
 * downloads) and conditional requests; anything else is not found.
 */
export async function serve(request: Request, env: Env, key: string): Promise<Response> {
  const served = kind(key);
  if (!served) return new Response('Not found', { status: 404 });
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
  }
  const object =
    request.method === 'HEAD'
      ? await env.UPDATES.head(key)
      : await env.UPDATES.get(key, { onlyIf: request.headers, range: request.headers });
  if (!object) return new Response('Not found', { status: 404 });
  const headers = new Headers({
    'Content-Type': served.type,
    'Cache-Control': served.cache,
    'Accept-Ranges': 'bytes',
    ETag: object.httpEtag,
    'X-Content-Type-Options': 'nosniff',
  });
  if (served.download) headers.set('Content-Disposition', `attachment; filename="${key.split('/').pop()}"`);
  // A GET whose precondition held for the copy the client has.
  if (request.method === 'GET' && !('body' in object)) return new Response(null, { status: 304, headers });
  const range = request.method === 'GET' ? bytes(object.range, object.size) : undefined;
  if (range) {
    headers.set('Content-Range', `bytes ${range.start}-${range.start + range.length - 1}/${object.size}`);
    headers.set('Content-Length', String(range.length));
  } else {
    headers.set('Content-Length', String(object.size));
  }
  const body = 'body' in object ? (object as R2ObjectBody).body : null;
  return new Response(body, { status: range ? 206 : 200, headers });
}

/** The bytes R2 returned for a range request; undefined for the whole object. */
function bytes(range: R2Range | undefined, size: number): { start: number; length: number } | undefined {
  if (!range) return undefined;
  if ('suffix' in range && range.suffix !== undefined) {
    const length = Math.min(range.suffix, size);
    return { start: size - length, length };
  }
  const start = 'offset' in range && range.offset !== undefined ? range.offset : 0;
  const length = 'length' in range && range.length !== undefined ? range.length : size - start;
  if (start === 0 && length === size) return undefined;
  return { start, length };
}
