
import { Menu } from "lucide-react";
import { NetworkPerformanceCard } from "@/pages/dashboard/components/NetworkPerformanceCard";
import { FlowStatistics } from "@/pages/dashboard/components/FlowStatistics";
import { NetworkUsageChart } from "@/pages/dashboard/components/NetworkUsageChart";
import { MonthlyUsageCard } from "@/pages/dashboard/components/MonthlyUsageCard";
import { DevicesCard } from "@/pages/dashboard/components/DevicesCard";
import NotificationsCard from "@/pages/dashboard/components/NotificationsCard";
import { RulesCard } from "@/pages/dashboard/components/RulesCard";
import { ConntrackCard } from "@/pages/dashboard/components/ConntrackCard";
import { SystemStatsCard } from "@/pages/dashboard/components/SystemStatsCard";
import { LiveWanTraffic } from "@/pages/dashboard/components/LiveWanTraffic";
import BottomNav from "@/pages/shared/BottomNav";
import { getConfig } from "@/services/ConfigService";
import { useQuery } from "@tanstack/react-query";
import { fetchSystemMetrics } from "@/services/NetdataService";
import { useToast } from "@/hooks/use-toast";
import AuthService from "@/services/AuthService";
import { useNavigate } from "react-router-dom";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

const Index = () => {
  const navigate = useNavigate();
  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig,
  });

  const hostname = config?.hostname || "Openwalla";
  const { toast } = useToast();

  const { data: metrics } = useQuery({
    queryKey: ['system-metrics'],
    queryFn: fetchSystemMetrics,
    refetchInterval: 5000,
    retry: 5,
    retryDelay: 1000,
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

  const handleLogout = () => {
    AuthService.logout();
    navigate("/login");
    toast({
      title: "Logged out",
      description: "You have been successfully logged out.",
    });
  };

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-4xl mx-auto pb-20">
        {/* Header */}
        <header className="flex justify-between items-center mb-6">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button className="text-dashboard-accent hover:opacity-80">
                <Menu className="w-6 h-6" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start" className="bg-dashboard-card border-gray-800">
              <DropdownMenuItem 
                onClick={handleLogout}
                className="text-white hover:bg-gray-700 cursor-pointer"
              >
                Logout
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
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
