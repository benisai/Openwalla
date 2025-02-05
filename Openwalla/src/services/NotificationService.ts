import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

export interface Notification {
  uuid: string;
  sev: 'error' | 'warning' | 'info';
  type: string;
  msg: string;
  detect_time: number;
  action: string | null;
}

export async function fetchNotifications(includeArchived: boolean = false): Promise<Notification[]> {
  const url = includeArchived ? '/api/notifications?includeArchived=true' : '/api/notifications';
  const response = await fetch(url);
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

export async function archiveAllNotifications(): Promise<void> {
  const response = await fetch('/api/notifications/archive-all', {
    method: 'POST',
  });
  if (!response.ok) {
    throw new Error('Failed to archive all notifications');
  }
}

export function useNotifications(includeArchived: boolean = false) {
  return useQuery({
    queryKey: ['notifications', { includeArchived }],
    queryFn: () => fetchNotifications(includeArchived),
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

export function useArchiveAllNotifications() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: archiveAllNotifications,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
    },
  });
}