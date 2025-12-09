import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.48.0';

type NotificationInsert = {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  status?: 'pending' | 'read';
};

export async function persistNotifications(
  supabase: SupabaseClient,
  notifications: NotificationInsert[],
): Promise<void> {
  if (!notifications || notifications.length === 0) return;

  const payload = notifications
      .filter((item) => item.userId && item.title && item.body)
      .map((item) => ({
        user_id: item.userId,
        title: item.title,
        body: item.body,
        data: item.data ?? null,
        status: item.status ?? 'pending',
      }));

  if (payload.length === 0) return;

  const { error } = await supabase.from('user_notifications').insert(payload);
  if (error) {
    console.error('Failed to persist user notifications', error);
  }
}
