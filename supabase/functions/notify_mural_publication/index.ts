import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

import { corsHeaders } from '../_shared/cors.ts';

type Payload = {
  marina_id?: string;
  marinaId?: string;
  post_id?: string;
  postId?: string;
  title?: string;
  type?: string;
  start_date?: string;
  startDate?: string;
  end_date?: string;
  endDate?: string;
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

type BoatRecipientRow = {
  id?: string;
  name?: string;
  marina_id?: string;
  primary_owner_id?: string | null;
  co_owner_ids?: (string | null)[];
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
    const marinaId = body.marina_id ?? body.marinaId ?? '';
    const postId = body.post_id ?? body.postId ?? '';
    const title = (body.title ?? '').toString().trim();
    const type = (body.type ?? '').toString().trim();
    const startDate = body.start_date ?? body.startDate;
    const endDate = body.end_date ?? body.endDate;

    if (!marinaId) {
      return new Response(
        JSON.stringify({
          error: 'marina_id is required.',
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

    const { data: marina, error: marinaError } = await supabase
        .from('marinas')
        .select('id,name')
        .eq('id', marinaId)
        .maybeSingle();

    if (marinaError) {
      console.error('Error loading marina', marinaError);
      return new Response(
        JSON.stringify({ error: 'Could not load marina.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (!marina) {
      return new Response(
        JSON.stringify({ error: 'Marina not found.' }),
        { status: 404, headers: jsonHeaders },
      );
    }

    const { data: boats, error: boatsError } = await supabase
        .from('boats_detailed')
        .select('id,name,primary_owner_id,co_owner_ids')
        .eq('marina_id', marinaId);

    if (boatsError) {
      console.error('Error loading boats for marina', boatsError);
      return new Response(
        JSON.stringify({ error: 'Could not load boats for marina.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const recipientIds = collectRecipientIds(boats ?? []);
    if (recipientIds.size === 0) {
      return new Response(
        JSON.stringify({
          message: 'No eligible boat owners found for this marina.',
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const { data: tokens, error: tokensError } = await supabase
        .from('user_push_tokens')
        .select('token')
        .in('user_id', Array.from(recipientIds));

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
          message: 'No push tokens found for the recipients.',
          totalRecipients: recipientIds.size,
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

    const typeLabel = resolveTypeLabel(type);
    const dateLabel = formatDateRange(startDate, endDate);
    const notificationTitle =
        `Nova publicacao na ${marina.name ?? 'marina'}`.trim();

    const bodyParts = [];
    if (typeLabel) bodyParts.push(typeLabel);
    if (title) bodyParts.push(title);
    const composedBody = `${bodyParts.join(' · ')}${
      dateLabel ? ` (${dateLabel})` : ''
    }`.trim();

    const dataPayload: Record<string, string> = {
      event: 'marina_wall_post',
      marina_id: marinaId,
      post_id: postId,
    };
    if (type) dataPayload.type = type;
    if (startDate) dataPayload.start_date = startDate;
    if (endDate) dataPayload.end_date = endDate;

    const pushResult = await sendFcmNotifications({
      tokens: validTokens,
      title: notificationTitle,
      body: composedBody.length === 0 ? notificationTitle : composedBody,
      data: dataPayload,
      accessToken,
      projectId,
    });

    return new Response(
      JSON.stringify({
        delivered: pushResult.successCount,
        failed: pushResult.failureCount,
        totalRecipients: recipientIds.size,
        targetedDevices: validTokens.length,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    console.error('Unexpected error sending push', error);
    return new Response(
      JSON.stringify({
        error: 'Unexpected error while sending notification.',
        details: error?.message ?? String(error),
      }),
      { status: 500, headers: jsonHeaders },
    );
  }
});

function collectRecipientIds(rows: BoatRecipientRow[]): Set<string> {
  const ids = new Set<string>();
  for (const row of rows) {
    if (row.primary_owner_id) {
      ids.add(String(row.primary_owner_id));
    }
    if (Array.isArray(row.co_owner_ids)) {
      for (const ownerId of row.co_owner_ids) {
        if (ownerId) {
          ids.add(String(ownerId));
        }
      }
    }
  }
  return ids;
}

function resolveTypeLabel(type: string | null | undefined): string {
  const normalized = (type ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'evento':
      return 'Evento';
    case 'aviso':
      return 'Aviso';
    case 'publicidade':
      return 'Publicidade';
    default:
      return '';
  }
}

function formatDateRange(startDate?: string, endDate?: string): string {
  const parsedStart = startDate ? new Date(startDate) : null;
  const parsedEnd = endDate ? new Date(endDate) : null;
  if (!parsedStart || isNaN(parsedStart.getTime())) {
    return parsedEnd && !isNaN(parsedEnd.getTime())
        ? formatDate(parsedEnd)
        : '';
  }
  if (!parsedEnd || isNaN(parsedEnd.getTime())) {
    return formatDate(parsedStart);
  }
  if (parsedStart.toDateString() === parsedEnd.toDateString()) {
    return formatDate(parsedStart);
  }
  return `${formatDate(parsedStart)} - ${formatDate(parsedEnd)}`;
}

function formatDate(date: Date): string {
  const day = `${date.getUTCDate()}`.padStart(2, '0');
  const month = `${date.getUTCMonth() + 1}`.padStart(2, '0');
  const year = date.getUTCFullYear();
  return `${day}/${month}/${year}`;
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
