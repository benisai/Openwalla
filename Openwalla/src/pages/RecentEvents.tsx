import { useNavigate } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { ChevronLeft, Home } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { ScrollArea } from "@/components/ui/scroll-area";

interface NetworkEvent {
  uuid: string;
  sev: 'error' | 'warning' | 'info';
  msg: string;
  detect_time: number;
  action: string | null;
}

export default function RecentEvents() {
  const navigate = useNavigate();

  const { data: events = [], isLoading } = useQuery({
    queryKey: ['network-timeline-events'],
    queryFn: async () => {
      const response = await fetch('/api/notifications/timeline');
      if (!response.ok) {
        throw new Error('Failed to fetch network events');
      }
      return response.json();
    },
    refetchInterval: 60000 // Refetch every minute
  });

  const formatTime = (timestamp: number) => {
    return new Date(timestamp).toLocaleTimeString();
  };

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

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto">
        <header className="flex items-center justify-between mb-8">
          <button
            onClick={() => navigate(-1)}
            className="text-dashboard-accent hover:opacity-80"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <h1 className="text-xl font-bold">Recent Network Events</h1>
          <button
            onClick={() => navigate("/")}
            className="text-dashboard-accent hover:opacity-80"
          >
            <Home className="w-6 h-6" />
          </button>
        </header>

        <ScrollArea className="h-[calc(100vh-120px)]">
          {isLoading ? (
            <div className="text-center text-gray-400">Loading events...</div>
          ) : events.length === 0 ? (
            <div className="text-center text-gray-400">No network events found</div>
          ) : (
            <div className="space-y-4">
              {events.map((event: NetworkEvent) => (
                <Card
                  key={event.uuid}
                  className="bg-dashboard-card p-4"
                >
                  <div className="flex items-start gap-4">
                    <div className="flex-1">
                      <div className="flex justify-between items-start">
                        <h3 className={`font-semibold ${getSeverityColor(event.sev)}`}>
                          {event.sev.toUpperCase()}
                        </h3>
                        <span className="text-xs text-gray-500">
                          {formatTime(event.detect_time)}
                        </span>
                      </div>
                      <p className="text-gray-300 mt-2">
                        {event.msg}
                      </p>
                      {event.action === 'archived' && (
                        <span className="text-xs text-gray-500 mt-2 block">
                          (Archived)
                        </span>
                      )}
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