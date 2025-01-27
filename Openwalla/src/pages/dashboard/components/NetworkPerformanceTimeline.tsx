import { useQuery } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";

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

interface LatencyInfo {
  color: string;
  message: string;
}

const getLatencyInfo = (latency: number, hasError: boolean, hasWarning: boolean): LatencyInfo => {
  if (hasError) return { color: "bg-red-500", message: "Internet Outage" };
  if (hasWarning || latency >= 125) return { color: "bg-yellow-500", message: "High Latency" };
  if (latency >= 75) return { color: "bg-green-700", message: "Good" };
  return { color: "bg-green-500", message: "Excellent" };
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
    queryKey: ['notifications', 'timeline'],
    queryFn: async () => {
      const response = await fetch('/api/notifications/timeline');
      if (!response.ok) throw new Error('Failed to fetch timeline notifications');
      return response.json();
    },
    refetchInterval: 60000,
  });

  useEffect(() => {
    if (pingStats && notifications) {
      const last12Hours: PingSegment[] = [];
      const now = new Date();

      const latestStat = pingStats[0];
      setCurrentLatency(latestStat?.median_latency || 0);

      for (let i = 11; i >= 0; i--) {
        const hourStart = new Date(now.getTime() - i * 60 * 60 * 1000);
        const hourEnd = new Date(now.getTime() - (i - 1) * 60 * 60 * 1000);

        const hourData = pingStats.filter((stat: any) => {
          const statTime = new Date(stat.date + ' ' + stat.time);
          return statTime >= hourStart && statTime < hourEnd;
        });

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
          <TooltipProvider>
            {segments.map((segment, index) => {
              const latencyInfo = getLatencyInfo(segment.latency, segment.hasError, segment.hasWarning);
              return (
                <Tooltip key={index}>
                  <TooltipTrigger asChild>
                    <div
                      className={`segment h-full ${latencyInfo.color}`}
                      style={{ flex: '1' }}
                    />
                  </TooltipTrigger>
                  <TooltipContent>
                    <p>{latencyInfo.message}</p>
                    <p>Time: {segment.time}</p>
                    <p>Latency: {segment.latency.toFixed(1)}ms</p>
                  </TooltipContent>
                </Tooltip>
              );
            })}
          </TooltipProvider>
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