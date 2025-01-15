import { Bell, ChevronLeft, Home, X } from "lucide-react";
import { Card } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useNavigate } from "react-router-dom";
import { useNotifications, useArchiveNotification } from "@/services/NotificationService";
import { format } from "date-fns";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";

export default function NotificationsPage() {
  const navigate = useNavigate();
  const { toast } = useToast();
  const { data: notifications = [], error, isLoading } = useNotifications();
  const archiveMutation = useArchiveNotification();

  if (error) {
    toast({
      title: "Error",
      description: "Failed to fetch notifications",
      variant: "destructive",
    });
  }

  const getSeverityColor = (sev: string) => {
    switch (sev) {
      case 'error':
        return 'text-red-500';
      case 'warning':
        return 'text-yellow-500';
      default:
        return 'text-green-500';
    }
  };

  const formatTime = (timestamp: number) => {
    const date = new Date(timestamp);
    return format(date, 'MMM dd, yyyy HH:mm');
  };

  const handleArchive = async (uuid: string) => {
    try {
      await archiveMutation.mutateAsync(uuid);
      toast({
        title: "Success",
        description: "Notification archived",
      });
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to archive notification",
        variant: "destructive",
      });
    }
  };
  
  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4">
      <div className="max-w-4xl mx-auto">
        <header className="flex items-center justify-between mb-6">
          <button
            onClick={() => navigate(-1)}
            className="text-dashboard-accent hover:opacity-80"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <h1 className="text-xl font-bold">Notifications</h1>
          <button
            onClick={() => navigate("/")}
            className="text-dashboard-accent hover:opacity-80"
          >
            <Home className="w-6 h-6" />
          </button>
        </header>

        <ScrollArea className="h-[calc(100vh-120px)]">
          {isLoading ? (
            <div className="text-center text-gray-400">Loading notifications...</div>
          ) : notifications.length === 0 ? (
            <div className="text-center text-gray-400">No notifications</div>
          ) : (
            <div className="space-y-4">
              {notifications.map((notification) => (
                <Card
                  key={notification.uuid}
                  className="bg-dashboard-card p-4 hover:brightness-110 transition-all"
                >
                  <div className="flex items-start gap-4">
                    <div className="mt-1">
                      <Bell className={`w-5 h-5 ${getSeverityColor(notification.sev)}`} />
                    </div>
                    <div className="flex-1">
                      <div className="flex justify-between items-start">
                        <h3 className="font-semibold text-white mb-1">
                          {notification.type}
                        </h3>
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-6 w-6"
                          onClick={() => handleArchive(notification.uuid)}
                        >
                          <X className="h-4 w-4" />
                        </Button>
                      </div>
                      <p className="text-gray-400 text-sm">
                        {notification.msg}
                      </p>
                      <span className="text-xs text-gray-500 mt-2 block">
                        {formatTime(notification.detect_time)}
                      </span>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </ScrollArea>
      </div>
    </div>
  );
}