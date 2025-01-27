import { Card } from "@/components/ui/card";
import { Bell } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useNotifications } from "@/services/NotificationService";
import { useToast } from "@/hooks/use-toast";

export default function NotificationsCard() {
  const navigate = useNavigate();
  const { toast } = useToast();
  const { data: notifications, error, isLoading } = useNotifications();

  if (error) {
    toast({
      title: "Error",
      description: "Failed to fetch notifications",
      variant: "destructive",
    });
  }

  return (
    <Card 
      className="bg-dashboard-card p-4 flex flex-col items-center justify-center cursor-pointer hover:bg-opacity-80 transition-colors"
      onClick={() => navigate("/notifications")}
    >
      <Bell className="w-6 h-6 text-dashboard-accent mb-2" />
      <span className="text-base md:text-2xl font-bold text-white">
        {isLoading ? "..." : notifications?.length || 0}
      </span>
      <span className="text-sm text-gray-400">Notifications</span>
    </Card>
  );
}