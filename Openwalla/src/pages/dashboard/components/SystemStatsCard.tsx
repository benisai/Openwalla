import { Card } from "@/components/ui/card";
import type { SystemMetrics } from "@/services/NetdataService";
import { useQuery } from "@tanstack/react-query";
import { getConfig } from "@/services/ConfigService";

interface CircularProgressProps {
  value: number;
  label: string;
  className?: string;
}

function CircularProgress({ value, label, className = "" }: CircularProgressProps) {
  const radius = 35;
  const circumference = 2 * Math.PI * radius;
  const strokeDashoffset = circumference - (value / 100) * circumference;

  return (
    <div className="flex flex-col items-center">
      <div className="relative">
        <svg width="100" height="100" className="-rotate-90">
          <circle
            cx="50"
            cy="50"
            r={radius}
            stroke="currentColor"
            strokeWidth="6"
            fill="none"
            className="text-gray-700"
          />
          <circle
            cx="50"
            cy="50"
            r={radius}
            stroke="currentColor"
            strokeWidth="6"
            fill="none"
            strokeDasharray={circumference}
            strokeDashoffset={strokeDashoffset}
            className={`${className} transition-all duration-300`}
          />
        </svg>
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="text-xl font-bold text-white">{value}%</span>
          <span className="text-sm text-gray-400">{label}</span>
        </div>
      </div>
    </div>
  );
}

interface SystemStatsCardProps {
  metrics: SystemMetrics;
}

export function SystemStatsCard({ metrics }: SystemStatsCardProps) {
  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig
  });

  const { data: loadData } = useQuery({
    queryKey: ['system-load'],
    queryFn: async () => {
      const response = await fetch('/api/config');
      if (!response.ok) {
        throw new Error('Failed to fetch config');
      }
      const config = await response.json();
      const netdataUrl = `http://${config.router_ip || '192.168.1.1'}:19999`;
      
      const loadResponse = await fetch(`${netdataUrl}/api/v1/data?chart=system.load&after=-5&before=0&format=json`);
      if (!loadResponse.ok) {
        throw new Error('Failed to fetch system load');
      }
      const data = await loadResponse.json();
      const cpuCores = parseInt(config.cpu_cores) || 4;
      // Convert load average to percentage based on number of cores
      const loadPercentage = (data.data[0][1] / cpuCores) * 100;
      return Math.min(loadPercentage, 100); // Cap at 100%
    },
    refetchInterval: 5000, // Refresh every 5 seconds
    initialData: 0,
  });

  return (
    <Card className="bg-dashboard-card p-4 mb-4" data-testid="system-stats-card">
      <h3 className="text-gray-400 text-sm mb-2">System Resources</h3>
      <div className="grid grid-cols-3 gap-2">
        <CircularProgress 
          value={Math.round(metrics.cpu)} 
          label="CPU" 
          className="text-dashboard-success"
        />
        <CircularProgress 
          value={Math.round(metrics.memory)} 
          label="Mem" 
          className="text-dashboard-chart"
        />
        <CircularProgress 
          value={Math.round(loadData)} 
          label="Load" 
          className="text-dashboard-accent"
        />
      </div>
    </Card>
  );
}