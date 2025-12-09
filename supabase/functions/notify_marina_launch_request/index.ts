import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

import { corsHeaders } from '../_shared/cors.ts';
import { persistNotifications } from '../_shared/notifications.ts';

type LaunchRequestPayload = {
  marina_id?: string;
  marinaId?: string;
  boat_id?: string;
  boatId?: string;
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
    const body = (await req.json()) as LaunchRequestPayload;
    const marinaId = body.marina_id ?? body.marinaId ?? '';
    const boatId = body.boat_id ?? body.boatId ?? '';

    if (!marinaId || !boatId) {
      return new Response(
        JSON.stringify({
          error: 'Parâmetros obrigatórios ausentes. Informe marina_id e boat_id.',
        }),
        { status: 400, headers: jsonHeaders },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error(
        'Variáveis SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY não configuradas.',
      );
      return new Response(
        JSON.stringify({
          error:
              'Supabase não configurado corretamente para executar esta função.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    const { data: boat, error: boatError } = await supabase
        .from('boats_detailed')
        .select(
          'id, name, marina_name, primary_owner_id, primary_owner_name, co_owner_ids',
        )
        .eq('id', boatId)
        .single();

    if (boatError) {
      console.error('Erro ao carregar embarcação', boatError);
      return new Response(
        JSON.stringify({ error: 'Falha ao carregar dados da embarcação.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (!boat) {
      return new Response(
        JSON.stringify({ error: 'Embarcação não encontrada.' }),
        { status: 404, headers: jsonHeaders },
      );
    }

    const { data: marinaProfiles, error: marinaProfilesError } = await supabase
        .from('user_profiles_view')
        .select('user_id')
        .eq('profile_slug', 'marina')
        .eq('marina_id', marinaId);

    if (marinaProfilesError) {
      console.error('Erro ao carregar perfis de marina', marinaProfilesError);
      return new Response(
        JSON.stringify({ error: 'Falha ao carregar perfis da marina.' }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const recipientIds = new Set<string>();
    for (const profile of marinaProfiles ?? []) {
      const userId = profile.user_id as string | null | undefined;
      if (userId) {
        recipientIds.add(userId);
      }
    }

    if (boat.primary_owner_id) {
      recipientIds.add(String(boat.primary_owner_id));
    }

    if (Array.isArray(boat.co_owner_ids)) {
      for (const ownerId of boat.co_owner_ids) {
        if (ownerId) {
          recipientIds.add(String(ownerId));
        }
      }
    }

    if (recipientIds.size === 0) {
      return new Response(
        JSON.stringify({
          message: 'Nenhum usuário elegível encontrado para receber o push.',
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const { data: tokens, error: tokensError } = await supabase
        .from('user_push_tokens')
        .select('token')
        .in('user_id', Array.from(recipientIds));

    if (tokensError) {
      console.error('Erro ao carregar tokens de push', tokensError);
      return new Response(
        JSON.stringify({ error: 'Falha ao carregar tokens de push.' }),
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
          message: 'Nenhum token de push encontrado para os destinatários.',
          totalRecipients: recipientIds.size,
        }),
        { status: 200, headers: jsonHeaders },
      );
    }

    const serviceAccountRaw = Deno.env.get('FCM_SERVICE_ACCOUNT');
    if (!serviceAccountRaw) {
      console.error('FCM_SERVICE_ACCOUNT não configurada.');
      return new Response(
        JSON.stringify({
          error:
              'FCM_SERVICE_ACCOUNT não configurada. Configure a credencial da conta de serviço do Firebase.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    let serviceAccount: ServiceAccount;
    try {
      serviceAccount = parseServiceAccount(serviceAccountRaw);
    } catch (error) {
      console.error('Erro ao interpretar FCM_SERVICE_ACCOUNT', error);
      return new Response(
        JSON.stringify({
          error:
              'Não foi possível interpretar a credencial configurada em FCM_SERVICE_ACCOUNT.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const projectId =
        Deno.env.get('FCM_PROJECT_ID') ?? serviceAccount.project_id ?? '';

    if (!projectId) {
      console.error(
        'Projeto Firebase não identificado. Configure FCM_PROJECT_ID ou inclua project_id na credencial.',
      );
      return new Response(
        JSON.stringify({
          error:
              'Projeto Firebase não identificado. Defina a variável FCM_PROJECT_ID.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    const accessToken = await getAccessToken(serviceAccount);

    const notificationTitle = 'Solicitação de descida';
    const notificationBody =
        `A embarcação ${boat.name} solicitou descida na ${boat.marina_name ?? 'marina'}.`;
    const dataPayload: Record<string, string> = {
      event: 'boat_launch_request',
      marina_id: marinaId,
      boat_id: boatId,
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
      Array.from(recipientIds).map((userId) => ({
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
        totalRecipients: recipientIds.size,
        targetedDevices: validTokens.length,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    console.error('Erro inesperado no envio de notificações', error);
    return new Response(
      JSON.stringify({
        error: 'Erro inesperado ao processar a notificação.',
        details: error?.message ?? String(error),
      }),
      { status: 500, headers: jsonHeaders },
    );
  }
});

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
      console.error('Falha ao enviar push para token', token, errorText);
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
        `Não foi possível decodificar a credencial da conta de serviço: ${error}`,
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
    throw new Error(
      'Credencial inválida: client_email ou private_key ausentes.',
    );
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
    console.error('Erro ao obter access token FCM', errorText);
    throw new Error('Falha ao obter token de acesso para FCM.');
  }

  const json = (await response.json()) as {
    access_token?: string;
    expires_in?: number;
  };

  if (!json.access_token) {
    throw new Error('Resposta do Google sem access_token.');
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
