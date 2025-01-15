import { Menu } from "lucide-react";
import { NetworkPerformanceCard } from "@/components/dashboard/NetworkPerformanceCard";
import { FlowStatistics } from "@/components/dashboard/FlowStatistics";
import { NetworkUsageChart } from "@/components/dashboard/NetworkUsageChart";
import { MonthlyUsageCard } from "@/components/dashboard/MonthlyUsageCard";
import { DevicesCard } from "@/components/dashboard/DevicesCard";
import NotificationsCard from "@/components/dashboard/NotificationsCard";
import { RulesCard } from "@/components/dashboard/RulesCard";
import { ConntrackCard } from "@/components/dashboard/ConntrackCard";
import { SystemStatsCard } from "@/components/dashboard/SystemStatsCard";
import { LiveWanTraffic } from "@/components/dashboard/LiveWanTraffic";
import BottomNav from "@/components/dashboard/BottomNav";
import { getConfig } from "@/config/openwalla.config";
import { useQuery } from "@tanstack/react-query";
import { fetchSystemMetrics } from "@/services/NetdataService";
import { useToast } from "@/hooks/use-toast";

const Index = () => {
  const hostname = getConfig('hostname') || "Openwalla";
  const { toast } = useToast();

  const { data: metrics } = useQuery({
    queryKey: ['system-metrics'],
    queryFn: fetchSystemMetrics,
    refetchInterval: 5000, // Refresh every 5 seconds
    retry: 5, // Retry 5 times
    retryDelay: 1000, // Wait 1 second between retries
    initialData: {
      cpu: 0,
      memory: 0,
      load: 0,
      received: 0,
      sent: 0,
      connections: 0
    },
    meta: {
      onError: () => {
        toast({
          title: "Connection Error",
          description: "Failed to connect to Netdata. Please check your Netdata URL in settings.",
          variant: "destructive",
        });
      }
    }
  });

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        {/* Header */}
        <header className="flex justify-between items-center mb-6">
          <Menu className="w-6 h-6 text-dashboard-accent" />
          <div className="flex items-center gap-2">
            <span className="text-xl font-bold">{hostname}</span>
          </div>
          <div className="w-6 h-6" /> {/* Spacer for alignment */}
        </header>

        {/* Status Cards */}
        <div className="grid grid-cols-3 gap-4 mb-4">
          <DevicesCard />
          <NotificationsCard />
          <RulesCard />
        </div>

        {/* Network Performance */}
        <NetworkPerformanceCard />

        {/* System Stats */}
        <SystemStatsCard metrics={metrics} />

        {/* Live WAN Traffic */}
        <LiveWanTraffic metrics={metrics} />

        {/* Flow Statistics */}
        <FlowStatistics />

        {/* Network Chart */}
        <NetworkUsageChart />

        {/* Monthly Usage */}
        <MonthlyUsageCard />

        {/* Conntrack Card */}
        <ConntrackCard connections={metrics.connections} />
      </div>

      {/* Navigation */}
      <BottomNav />
    </div>
  );
};

export default Index;