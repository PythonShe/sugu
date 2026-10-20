import type { Env } from '../../server/updates';

/** The newest package, wherever the site was built: read from latest.json on every request. */
export const onRequestGet: PagesFunction<Env> = async ({ env, request }) => {
  const object = await env.UPDATES.get('latest.json');
  const latest = object ? ((await object.json()) as { version?: string }) : undefined;
  if (!latest?.version || !/^\d+\.\d+\.\d+$/.test(latest.version)) {
    return Response.redirect(new URL('/', request.url).toString(), 302);
  }
  const target = new URL(`/releases/${latest.version}/Sugu-${latest.version}.pkg`, request.url);
  return new Response(null, { status: 302, headers: { Location: target.toString(), 'Cache-Control': 'no-cache' } });
};
