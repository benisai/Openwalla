import { useEffect, useRef } from 'react';
import { useNotifications } from '@/services/NotificationService';
import { toast } from '@/hooks/use-toast';
import { AlertCircle, AlertTriangle, Info } from 'lucide-react';

const STORAGE_KEY = 'dismissed-notification-toasts';

export function NotificationToastManager() {
  const { data: notifications } = useNotifications();
  const previousNotificationsRef = useRef<Set<string>>(new Set());

  // Load previously dismissed notifications from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored) {
        previousNotificationsRef.current = new Set(JSON.parse(stored));
      }
    } catch (error) {
      console.error('Failed to load dismissed notifications:', error);
    }
  }, []);

  useEffect(() => {
    if (!notifications || notifications.length === 0) {
      return;
    }

    const currentNotificationIds = new Set(notifications.map(n => n.uuid));
    const newNotifications = notifications.filter(
      n => !previousNotificationsRef.current.has(n.uuid)
    );

    // Show toast for each new notification
    newNotifications.forEach(notification => {
      const Icon = 
        notification.sev === 'error' ? AlertCircle :
        notification.sev === 'warning' ? AlertTriangle :
        Info;

      toast({
        title: notification.type.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase()),
        description: notification.msg,
        variant: notification.sev === 'error' ? 'destructive' : 'default',
        action: <Icon className="h-4 w-4" />,
      });
    });

    previousNotificationsRef.current = currentNotificationIds;
    
    // Persist to localStorage
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(currentNotificationIds)));
    } catch (error) {
      console.error('Failed to save dismissed notifications:', error);
    }
  }, [notifications]);

  return null;
}
