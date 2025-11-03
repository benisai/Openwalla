
import { useMemo } from "react";
import { TopApplicationsChart } from "@/pages/application-usage/components/TopApplicationsChart";
import { UsageTimelineChart } from "@/pages/application-usage/components/UsageTimelineChart";
import { ApplicationUsageStats } from "@/pages/application-usage/components/ApplicationUsageStats";
import { useDeviceApplicationUsage } from "@/services/applicationUsage/ApplicationUsageService";
import { Card } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { formatBytes } from "@/misc/utils/networkFormatting";

interface DeviceApplicationUsageProps {
  deviceMac: string;
}

export function DeviceApplicationUsage({ deviceMac }: DeviceApplicationUsageProps) {
  const { data: deviceUsage, isLoading, error } = useDeviceApplicationUsage(deviceMac);

  const topApplications = useMemo(() => {
    if (!deviceUsage) return [];
    return deviceUsage.applications;
  }, [deviceUsage]);

  if (error) {
    return (
      <Card className="bg-dashboard-card p-4 my-4">
        <div className="text-center py-4 text-red-400">
          Failed to load application usage data
        </div>
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <UsageTimelineChart 
          deviceMac={deviceMac} 
          data={deviceUsage?.timelineData || []} 
          isLoading={isLoading} 
        />
        <TopApplicationsChart 
          data={topApplications} 
          isLoading={isLoading} 
        />
      </div>
      
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">Application Breakdown</h3>
        {isLoading ? (
          <div className="space-y-4">
            {[1, 2, 3, 4, 5].map((i) => (
              <div key={i} className="animate-pulse space-y-2">
                <div className="flex justify-between items-center">
                  <div className="h-4 bg-gray-700 rounded w-24"></div>
                  <div className="h-4 bg-gray-700 rounded w-16"></div>
                </div>
                <Progress value={0} className="h-2 bg-gray-700" />
              </div>
            ))}
          </div>
        ) : !deviceUsage || !deviceUsage.applications.length ? (
          <div className="text-center py-4 text-gray-400">
            No application usage data available
          </div>
        ) : (
          <div className="space-y-4">
            {deviceUsage.applications.map((app, index) => (
              <div key={index} className="space-y-1">
                <div className="flex justify-between items-center">
                  <span className="text-sm">{app.name}</span>
                  <span className="text-sm text-gray-400">
                    {formatBytes(app.bytesUsed)}
                  </span>
                </div>
                <Progress 
                  value={app.percentage} 
                  className="h-2 bg-gray-700" 
                  indicatorClassName="bg-blue-500" 
                />
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
