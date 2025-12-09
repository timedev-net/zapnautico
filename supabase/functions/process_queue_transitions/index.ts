import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';

import { corsHeaders } from '../_shared/cors.ts';

type ProcessedEntry = {
  entry_id?: string;
  id?: string;
  new_status?: string;
  status?: string;
};

const jsonHeaders = {
  ...corsHeaders,
  'Content-Type': 'application/json',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const secret = Deno.env.get('QUEUE_TRANSITIONS_SECRET');

  if (!supabaseUrl || !serviceRoleKey) {
    console.error('Missing Supabase credentials.');
    return new Response(
      JSON.stringify({ error: 'Missing Supabase credentials.' }),
      { status: 500, headers: jsonHeaders },
    );
  }

  if (secret) {
    const providedSecret =
        req.headers.get('x-queue-secret') ??
        req.headers.get('x-cron-secret') ??
        '';
    if (providedSecret !== secret) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: jsonHeaders },
      );
    }
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const searchParams = new URL(req.url).searchParams;
  const parsedLimit = Number(searchParams.get('limit') ?? searchParams.get('max'));
  const maxBatch =
      Number.isFinite(parsedLimit) && parsedLimit > 0
          ? Math.min(parsedLimit, 200)
          : 50;

  const { data, error } = await supabase.rpc(
    'process_launch_queue_transitions',
    { max_batch: maxBatch },
  );

  if (error) {
    console.error('Failed to process queue transitions', error);
    return new Response(
      JSON.stringify({
        error: 'Failed to process queue transitions.',
        details: error.message ?? String(error),
      }),
      { status: 500, headers: jsonHeaders },
    );
  }

  const processed = Array.isArray(data) ? (data as ProcessedEntry[]) : [];
  if (processed.length === 0) {
    return new Response(
      JSON.stringify({ processed: 0, notified: 0, max_batch: maxBatch }),
      { status: 200, headers: jsonHeaders },
    );
  }

  let notified = 0;
  let notifyFailures = 0;

  for (const entry of processed) {
    const entryId = entry.entry_id ?? entry.id ?? '';
    const status = entry.new_status ?? entry.status ?? '';

    if (!entryId) continue;

    try {
      const { error: notifyError } = await supabase.functions.invoke(
        'notify_queue_status_change',
        {
          body: {
            entry_id: entryId,
            status,
          },
        },
      );

      if (notifyError) {
        notifyFailures += 1;
        console.error('Failed to notify queue status', notifyError);
      } else {
        notified += 1;
      }
    } catch (notifyError) {
      notifyFailures += 1;
      console.error('Unexpected notify error', notifyError);
    }
  }

  return new Response(
    JSON.stringify({
      processed: processed.length,
      notified,
      failed_notifications: notifyFailures,
      max_batch: maxBatch,
    }),
    { status: 200, headers: jsonHeaders },
  );
});
