import { serve, type Env } from '../server/updates';

export const onRequest: PagesFunction<Env> = ({ request, env }) => serve(request, env, 'releases.json');
