import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { useQuery } from "@tanstack/react-query";
import { NetworkPerformanceTimeline } from "@/components/dashboard/NetworkPerformanceTimeline";

export function SummaryCard() {
  const { data: notifications } = useQuery({
    queryKey: ['outage-notifications'],
    queryFn: async () => {
      const response = await fetch('/api/notifications?type=internet_monitor&last24h=true');
      if (!response.ok) {
        throw new Error('Failed to fetch notifications');
      }
      return response.json();
    },
    refetchInterval: 60000
  });

  const { data: pingStats } = useQuery({
    queryKey: ['ping-stats', 'summary'],
    queryFn: async () => {
      const response = await fetch('/api/ping-stats/summary');
      if (!response.ok) {
        throw new Error('Failed to fetch ping stats');
      }
      return response.json();
    },
    refetchInterval: 60000
  });

  const { data: latestPing } = useQuery({
    queryKey: ['ping-stats', 'latest'],
    queryFn: async () => {
      const response = await fetch('/api/ping-stats/last24hours');
      if (!response.ok) {
        throw new Error('Failed to fetch latest ping');
      }
      const data = await response.json();
      return data[0]; // Get the most recent entry
    },
    refetchInterval: 60000
  });

  const calculateTotalOutage = (notifications: any[] = []) => {
    const outages = notifications.filter(n => n.sev === 'error');
    if (outages.length === 0) return '0s';
    
    const totalSeconds = outages.length * 60;
    if (totalSeconds < 60) return `${totalSeconds}s`;
    if (totalSeconds < 3600) return `${Math.floor(totalSeconds / 60)}m`;
    return `${Math.floor(totalSeconds / 3600)}h ${Math.floor((totalSeconds % 3600) / 60)}m`;
  };

  return (
    <Card className="bg-dashboard-card text-white">
      <CardHeader>
        <CardTitle className="text-xl">Summary</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid grid-cols-3 gap-4">
          <div>
            <p className="text-sm text-gray-400">Total Outage</p>
            <p className="text-base md:text-2xl font-bold">
              {calculateTotalOutage(notifications)}
            </p>
          </div>
          <div>
            <p className="text-sm text-gray-400">Latency</p>
            <p className="text-base md:text-2xl font-bold">
              {latestPing?.median_latency ? `${Math.round(latestPing.median_latency)} ms` : '-- ms'}
            </p>
          </div>
          <div>
            <p className="text-sm text-gray-400">Packet Loss</p>
            <p className="text-base md:text-2xl font-bold">
              {`${pingStats?.maxPacketLoss || 0}%`}
            </p>
          </div>
        </div>
        <NetworkPerformanceTimeline showHeader={false} />
      </CardContent>
    </Card>
  );
}