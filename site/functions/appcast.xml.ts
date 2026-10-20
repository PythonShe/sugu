import { serve, type Env } from '../server/updates';

/** The Sparkle feed every installed copy reads (`SUFeedURL`). */
export const onRequest: PagesFunction<Env> = ({ request, env }) => serve(request, env, 'appcast.xml');
