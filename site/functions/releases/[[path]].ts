import { serve, type Env } from '../../server/updates';

/** Downloads and release notes: /releases/<version>/… */
export const onRequest: PagesFunction<Env> = ({ request, env, params }) => {
  const path = Array.isArray(params.path) ? params.path.join('/') : '';
  return serve(request, env, `releases/${path}`);
};
