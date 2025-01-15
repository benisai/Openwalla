import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export interface Notification {
  uuid: string;
  sev: 'error' | 'warning' | 'info';
  type: string;
  msg: string;
  detect_time: number;
  action: string | null;
}

export async function fetchNotifications(): Promise<Notification[]> {
  const response = await fetch('/api/notifications');
  if (!response.ok) {
    throw new Error('Failed to fetch notifications');
  }
  return response.json();
}

export async function archiveNotification(uuid: string): Promise<void> {
  const response = await fetch(`/api/notifications/${uuid}/archive`, {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error('Failed to archive notification');
  }
}

export function useNotifications() {
  return useQuery({
    queryKey: ['notifications'],
    queryFn: fetchNotifications,
    refetchInterval: 30000, // Refetch every 30 seconds
  });
}

export function useArchiveNotification() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: archiveNotification,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
    },
  });
}