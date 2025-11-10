import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts';

import { corsHeaders } from '../_shared/cors.ts';

type BroadcastPayload = {
  title?: string;
  body?: string;
  data?: Record<string, unknown>;
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

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Método não suportado. Utilize POST.' }),
      { status: 405, headers: jsonHeaders },
    );
  }

  try {
    const payload = (await req.json()) as BroadcastPayload;
    const title = (payload.title ?? '').trim();
    const body = (payload.body ?? '').trim();

    if (!title || !body) {
      return new Response(
        JSON.stringify({
          error: 'Informe título e mensagem para enviar a notificação.',
        }),
        { status: 400, headers: jsonHeaders },
      );
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      console.error(
        'Variáveis SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY ausentes.',
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

    const authHeader = req.headers.get('Authorization') ?? '';
    const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i);

    if (!tokenMatch) {
      return new Response(
        JSON.stringify({
          error: 'Cabeçalho Authorization ausente. Faça login novamente.',
        }),
        { status: 401, headers: jsonHeaders },
      );
    }

    const jwt = tokenMatch[1];
    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser(jwt);

    if (userError || !user) {
      console.error('Erro ao validar usuário solicitante', userError);
      return new Response(
        JSON.stringify({ error: 'Não foi possível validar o usuário.' }),
        { status: 401, headers: jsonHeaders },
      );
    }

    const { data: adminProfiles, error: profilesError } = await supabase
        .from('user_profiles_view')
        .select('id')
        .eq('user_id', user.id)
        .eq('profile_slug', 'administrador');

    if (profilesError) {
      console.error(
        'Erro ao verificar perfis do solicitante',
        profilesError,
      );
      return new Response(
        JSON.stringify({
          error: 'Falha ao verificar permissões do usuário.',
        }),
        { status: 500, headers: jsonHeaders },
      );
    }

    if (!adminProfiles || adminProfiles.length === 0) {
      return new Response(
        JSON.stringify({
          error: 'Apenas administradores podem enviar notificações.',
        }),
        { status: 403, headers: jsonHeaders },
      );
    }

    const { data: tokens, error: tokensError } = await supabase
        .from('user_push_tokens')
        .select('token');

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
          message: 'Nenhum token de push cadastrado no momento.',
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
    const dataPayload = sanitizeDataPayload(payload.data);

    const pushResult = await sendFcmNotifications({
      tokens: validTokens,
      title,
      body,
      data: dataPayload,
      accessToken,
      projectId,
    });

    return new Response(
      JSON.stringify({
        delivered: pushResult.successCount,
        failed: pushResult.failureCount,
        targetedDevices: validTokens.length,
        requestedBy: user.id,
      }),
      { status: 200, headers: jsonHeaders },
    );
  } catch (error) {
    console.error('Erro inesperado ao enviar notificações', error);
    return new Response(
      JSON.stringify({
        error: 'Erro inesperado ao processar a solicitação.',
        details: error?.message ?? String(error),
      }),
      { status: 500, headers: jsonHeaders },
    );
  }
});

function sanitizeDataPayload(
  input?: Record<string, unknown>,
): Record<string, string> {
  const payload: Record<string, string> = {};
  if (input) {
    for (const [key, value] of Object.entries(input)) {
      if (!key) continue;
      payload[key] = String(value);
    }
  }
  if (!payload.event) {
    payload.event = 'admin_broadcast';
  }
  return payload;
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
