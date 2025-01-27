import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ChevronRight } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { useNavigate } from "react-router-dom";

export function RecentEventsCard() {
  const navigate = useNavigate();
  const { data: events } = useQuery({
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

  // Get only the 5 most recent events
  const recentEvents = events?.slice(0, 5) || [];

  return (
    <Card 
      className="bg-dashboard-card text-white cursor-pointer hover:bg-opacity-90 transition-colors"
      onClick={() => navigate('/recent-events')}
    >
      <CardHeader className="flex flex-row items-center justify-between">
        <CardTitle className="text-xl">Recent Events</CardTitle>
        <ChevronRight className="h-5 w-5 text-gray-400" />
      </CardHeader>
      <CardContent>
        {recentEvents.length > 0 ? (
          <div className="space-y-4">
            {recentEvents.map((event: any) => (
              <div key={event.uuid} className="border-b border-gray-700 pb-2 last:border-0">
                <p className="text-sm">
                  <span className={`inline-block w-2 h-2 rounded-full mr-2 ${
                    event.sev === 'error' ? 'bg-red-500' : 
                    event.sev === 'warning' ? 'bg-yellow-500' : 
                    'bg-green-500'
                  }`} />
                  {event.msg}
                </p>
                <p className="text-xs text-gray-400 mt-1">
                  {formatTime(event.detect_time)}
                </p>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-gray-400">No network events in last 24 hours</p>
        )}
      </CardContent>
    </Card>
  );
}