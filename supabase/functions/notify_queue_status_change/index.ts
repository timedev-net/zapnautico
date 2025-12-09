import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

import { corsHeaders } from '../_shared/cors.ts';
import { persistNotifications } from '../_shared/notifications.ts';

type Payload = {
  entry_id?: string;
  entryId?: string;
  queue_entry_id?: string;
  queueEntryId?: string;
  status?: string;
};

type LaunchQueueRow = {
  id?: string;
  status?: string | null;
  boat_id?: string | null;
  boat_name?: string | null;
  generic_boat_name?: string | null;
  marina_id?: string | null;
  marina_name?: string | null;
};

type BoatRow = {
  id?: string;
  name?: string | null;
  primary_owner_id?: string | null;
  co_owner_ids?: (string | null)[];
};

type NotificationResult = {
  successCount: number;
  failureCount: number;
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id?: string;
};

const jsonHeaders = {
  ...corsHeaders,
  'Content-Type': 'application/json',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = (await req.json()) as Payload;
    const entryId =
        body.entry_id ??
        body.entryId ??
        body.queue_entry_id ??
        body.queueEntryId ??
        '';
    const providedStatus = (body.status ?? '').toString().trim().toLowerCase();

    if (!entryId) {
      return new Response(
        JSON.stringify({
          error: 'entry_id is required.',
        }),
        { status: 400, headers: jsonHeaders },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error(
        'Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.',
      );
      return new Response(
        JSON.stringify({
          error: 'Supabase credentials are not configured.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: entry, error: entryError } = await supabase
        .from('boat_launch_queue_view')
        .select(
          'id,status,boat_id,boat_name,generic_boat_name,marina_id,marina_name',
        )
        .eq('id', entryId)
        .maybeSingle();

    if (entryError) {
      console.error('Error loading queue entry', entryError);
      return new Response(
        JSON.stringify({ error: 'Could not load queue entry.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (!entry) {
      return new Response(
        JSON.stringify({ error: 'Queue entry not found.' }),
        { status: 404, headers: jsonHeaders },
      );
    }

    const entryData = entry as LaunchQueueRow;
    const boatId = entryData.boat_id?.toString() ?? '';
    const status = providedStatus || entryData.status?.toString() || '';

    if (!boatId) {
      return new Response(
        JSON.stringify({
          message: 'No boat linked to this queue entry. Notification skipped.',
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const { data: boat, error: boatError } = await supabase
        .from('boats_detailed')
        .select('id,name,primary_owner_id,co_owner_ids')
        .eq('id', boatId)
        .maybeSingle();

    if (boatError) {
      console.error('Error loading boat', boatError);
      return new Response(
        JSON.stringify({ error: 'Could not load boat.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (!boat) {
      return new Response(
        JSON.stringify({ error: 'Boat not found for this entry.' }),
        { status: 404, headers: jsonHeaders },
      );
    }

    const recipients = collectOwnerRecipients(boat as BoatRow);
    if (recipients.size === 0) {
      return new Response(
        JSON.stringify({
          message: 'No eligible boat owners found to receive notification.',
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const { data: tokens, error: tokensError } = await supabase
        .from('user_push_tokens')
        .select('token')
        .in('user_id', Array.from(recipients));

    if (tokensError) {
      console.error('Error loading push tokens', tokensError);
      return new Response(
        JSON.stringify({ error: 'Could not load push tokens.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const validTokens = Array.from(
      new Set(
        (tokens ?? [])
            .map((row) => row.token as string | null | undefined)
            .filter((token): token is string => Boolean(token?.trim())),
      ),
    );

    if (validTokens.length === 0) {
      return new Response(
        JSON.stringify({
          message: 'No push tokens found for recipients.',
          totalRecipients: recipients.size,
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const serviceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT');
    if (!serviceAccountRaw) {
      console.error('FCM_SERVICE_ACCOUNT is not configured.');
      return new Response(
        JSON.stringify({
          error:
              'FCM_SERVICE_ACCOUNT is not configured. Add the Firebase service account credentials.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    let serviceAccount: ServiceAccount;
    try {
      serviceAccount = parseServiceAccount(serviceAccountRaw);
    } catch (error) {
      console.error('Failed to parse FCM_SERVICE_ACCOUNT', error);
      return new Response(
        JSON.stringify({
          error: 'Failed to parse FCM service account credentials.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const projectId =
        Deno.env.get('FCM_PROJECT_ID') ?? serviceAccount.project_id ?? '';

    if (!projectId) {
      console.error('Missing Firebase project id.');
      return new Response(
        JSON.stringify({
          error:
              'Firebase project id not found. Set FCM_PROJECT_ID or include project_id in the service account.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const accessToken = await getAccessToken(serviceAccount);
    const statusLabel = translateStatus(status);

    const boatName = (boat as BoatRow).name ??
        entryData.boat_name ??
        entryData.generic_boat_name ??
        'Embarcação';
    const marinaName = entryData.marina_name ?? 'marina';

    const notificationTitle = `Fila - ${marinaName}`;
    const notificationBody = `Status de ${boatName}: ${statusLabel}.`;

    const dataPayload: Record<string, string> = {
      event: 'queue_status_update',
      queue_entry_id: entryId.toString(),
      marina_id: entryData.marina_id?.toString() ?? '',
      boat_id: boatId,
      status: status,
    };

    const pushResult = await sendFcmNotifications({
      tokens: validTokens,
      title: notificationTitle,
      body: notificationBody,
      data: dataPayload,
      accessToken,
      projectId,
    });

    await persistNotifications(
      supabase,
      Array.from(recipients).map((userId) => ({
        userId,
        title: notificationTitle,
        body: notificationBody,
        data: dataPayload,
      })),
    );

    return new Response(
      JSON.stringify({
        delivered: pushResult.successCount,
        failed: pushResult.failureCount,
        totalRecipients: recipients.size,
        targetedDevices: validTokens.length,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    console.error('Unexpected error sending queue status push', error);
    return new Response(
      JSON.stringify({
        error: 'Unexpected error while sending notification.',
        details: error?.message ?? String(error),
      }),
      { status: 500, headers: jsonHeaders },
    );
  }
});

function collectOwnerRecipients(boat: BoatRow): Set<string> {
  const ids = new Set<string>();
  if (boat.primary_owner_id) {
    ids.add(String(boat.primary_owner_id));
  }
  if (Array.isArray(boat.co_owner_ids)) {
    for (const ownerId of boat.co_owner_ids) {
      if (ownerId) {
        ids.add(String(ownerId));
      }
    }
  }
  return ids;
}

function translateStatus(status: string): string {
  switch (status) {
    case 'pending':
      return 'Pendente';
    case 'in_progress':
      return 'Em andamento';
    case 'in_water':
      return 'Na água';
    case 'completed':
      return 'Concluído';
    case 'cancelled':
      return 'Cancelado';
    default:
      return status || 'Atualizado';
  }
}

async function sendFcmNotifications({
  tokens,
  title,
  body,
  data,
  accessToken,
  projectId,
}: {
  tokens: string[];
  title: string;
  body: string;
  data: Record<string, string>;
  accessToken: string;
  projectId: string;
}): Promise<NotificationResult> {
  let successCount = 0;
  let failureCount = 0;

  for (const token of tokens) {
    const payload = {
      message: {
        token,
        notification: {
          title,
          body,
        },
        data,
        android: {
          notification: {
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      },
    };

    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify(payload),
      },
    );

    if (response.ok) {
      successCount += 1;
    } else {
      failureCount += 1;
      const errorText = await response.text();
      console.error('Failed to send push for token', token, errorText);
    }
  }

  return { successCount, failureCount };
}

function parseServiceAccount(raw: string): ServiceAccount {
  try {
    return JSON.parse(raw) as ServiceAccount;
  } catch (_) {
    try {
      const decoded = decodeBase64(raw);
      return JSON.parse(decoded) as ServiceAccount;
    } catch (error) {
      throw new Error(
        `Could not decode service account credentials: ${error}`,
      );
    }
  }
}

function decodeBase64(value: string): string {
  const normalized = value.replace(/\s/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return new TextDecoder().decode(bytes);
}

async function getAccessToken(serviceAccount: ServiceAccount): Promise<string> {
  const { client_email, private_key } = serviceAccount;
  if (!client_email || !private_key) {
    throw new Error('Invalid service account: missing client_email or private_key.');
  }

  const key = await importPrivateKey(private_key);

  const now = getNumericDate(0);
  const payload = {
    iss: client_email,
    sub: client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: getNumericDate(3600),
  };

  const jwt = await create({ alg: 'RS256', typ: 'JWT' }, payload, key);

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error('Failed to get FCM access token', errorText);
    throw new Error('Could not obtain access token for FCM.');
  }

  const json = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
  };

  if (!json.access_token) {
    throw new Error('Response from Google did not include access_token.');
  }

  return json.access_token;
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const cleaned = pem
      .replace('-----BEGIN PRIVATE KEY-----', '')
      .replace('-----END PRIVATE KEY-----', '')
      .replace(/\s/g, '');
  const binary = atob(cleaned);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return crypto.subtle.importKey(
    'pkcs8',
    bytes.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
}
