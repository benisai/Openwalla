import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";

interface PingSegment {
  time: string;
  latency: number;
  hasError: boolean;
  hasWarning: boolean;
}

interface NetworkPerformanceTimelineProps {
  showHeader?: boolean;
  className?: string;
}

const getLatencyColor = (latency: number, hasError: boolean, hasWarning: boolean) => {
  if (hasError) return "bg-red-500";
  if (hasWarning || latency >= 125) return "bg-yellow-500";
  if (latency >= 75) return "bg-green-700";
  return "bg-green-500";
};

const formatAMPM = (date: Date) => {
  let hours = date.getHours();
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12;
  return `${hours} ${ampm}`;
};

export function NetworkPerformanceTimeline({ showHeader = true, className = "" }: NetworkPerformanceTimelineProps) {
  const navigate = useNavigate();
  const [segments, setSegments] = useState<PingSegment[]>([]);
  const [currentLatency, setCurrentLatency] = useState<number>(0);

  const { data: pingStats } = useQuery({
    queryKey: ['ping-stats', 'last12hours'],
    queryFn: async () => {
      const response = await fetch('/api/ping-stats/last24hours');
      if (!response.ok) throw new Error('Failed to fetch ping stats');
      return response.json();
    },
    refetchInterval: 60000,
  });

  const { data: notifications } = useQuery({
    queryKey: ['notifications', 'internet-monitor'],
    queryFn: async () => {
      const response = await fetch('/api/notifications?type=internet_monitor&last24h=true');
      if (!response.ok) throw new Error('Failed to fetch notifications');
      return response.json();
    },
    refetchInterval: 60000,
  });

  useEffect(() => {
    if (pingStats && notifications) {
      const last12Hours: PingSegment[] = [];
      const now = new Date();

      // Get the latest median latency
      const latestStat = pingStats[0];
      setCurrentLatency(latestStat?.median_latency || 0);

      // Group data by hour and get the max latency for each hour
      for (let i = 11; i >= 0; i--) {
        const hourStart = new Date(now.getTime() - i * 60 * 60 * 1000);
        const hourEnd = new Date(now.getTime() - (i - 1) * 60 * 60 * 1000);

        const hourData = pingStats.filter((stat: any) => {
          const statTime = new Date(stat.date + ' ' + stat.time);
          return statTime >= hourStart && statTime < hourEnd;
        });

        // Check for notifications in this hour
        const hourNotifications = notifications.filter((notif: any) => {
          const notifTime = new Date(notif.detect_time);
          return notifTime >= hourStart && notifTime < hourEnd;
        });

        const hasError = hourNotifications.some((notif: any) => notif.sev === 'error');
        const hasWarning = hourNotifications.some((notif: any) => notif.sev === 'warning');
        const maxHourLatency = Math.max(...hourData.map((stat: any) => stat.median_latency || 0));

        last12Hours.push({
          time: formatAMPM(hourStart),
          latency: maxHourLatency,
          hasError,
          hasWarning
        });
      }

      setSegments(last12Hours);
    }
  }, [pingStats, notifications]);

  return (
    <div className={`bg-dashboard-card p-6 rounded-lg mb-4 cursor-pointer ${className}`} onClick={() => navigate('/network-performance')}>
      {showHeader && (
        <>
          <div className="text-gray-400 text-sm mb-2">Network Performance</div>
          <div className="text-xl md:text-2xl font-bold text-white mb-4">
            {currentLatency.toFixed(1)}ms <span className="text-sm text-gray-400">Latency</span>
          </div>
        </>
      )}
      <div className="timeline relative mb-2">
        <div className="bar bg-gray-700 rounded-full h-2 overflow-hidden flex">
          {segments.map((segment, index) => (
            <div
              key={index}
              className={`segment h-full ${getLatencyColor(segment.latency, segment.hasError, segment.hasWarning)}`}
              style={{ flex: '1' }}
              title={`Time: ${segment.time}
Latency: ${segment.latency.toFixed(1)}ms
${segment.hasError ? '⚠️ Network Error' : ''}
${segment.hasWarning ? '⚠️ Performance Warning' : ''}`}
            />
          ))}
        </div>
        <div className="timestamps flex justify-between mt-1 text-xs text-gray-400">
          {segments.map((segment, index) => (
            <span key={index}>{segment.time}</span>
          ))}
          <span>Now</span>
        </div>
      </div>
    </div>
  );
}