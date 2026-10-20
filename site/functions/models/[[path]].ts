import { serve, type Env } from '../../server/updates';

/** Optional data the app downloads on request, as reviewed: /models/… */
export const onRequest: PagesFunction<Env> = ({ request, env, params }) => {
  const path = Array.isArray(params.path) ? params.path.join('/') : '';
  return serve(request, env, `models/${path}`);
};
