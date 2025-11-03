
import { ApplicationUsage } from "@/services/ApplicationUsageService";
import { formatBytes } from "@/misc/utils/networkFormatting";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

interface ApplicationUsageStatsProps {
  deviceUsage: ApplicationUsage | undefined;
  isLoading: boolean;
}

export function ApplicationUsageStats({ deviceUsage, isLoading }: ApplicationUsageStatsProps) {
  if (isLoading) {
    return (
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">Application Breakdown</h3>
        <div className="space-y-4">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="flex justify-between items-center">
              <Skeleton className="h-4 w-24" />
              <div className="flex items-center gap-4">
                <Skeleton className="w-32 h-2 rounded-full" />
                <Skeleton className="h-4 w-16" />
              </div>
            </div>
          ))}
        </div>
      </Card>
    );
  }

  if (!deviceUsage || !deviceUsage.applications.length) {
    return (
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">Application Breakdown</h3>
        <p className="text-sm text-center py-4">No application usage data available for this device</p>
      </Card>
    );
  }

  // Filter out Unknown applications
  const filteredApps = deviceUsage.applications.filter(app => 
    app.name.toLowerCase() !== 'unknown'
  );

  return (
    <Card className="bg-dashboard-card p-4">
      <h3 className="text-gray-400 text-sm mb-4">Application Breakdown</h3>
      {filteredApps.length === 0 ? (
        <p className="text-sm text-center py-4">No known application usage data available</p>
      ) : (
        <div className="space-y-4">
          {filteredApps.map((app, index) => (
            <div key={index} className="flex justify-between items-center">
              <span className="text-sm">{app.name}</span>
              <div className="flex items-center gap-4">
                <div className="w-32 bg-gray-700 h-2 rounded-full overflow-hidden">
                  <div
                    className="h-full bg-blue-500"
                    style={{ width: `${app.percentage}%` }}
                  />
                </div>
                <span className="text-sm text-gray-400">
                  {formatBytes(app.bytesUsed)}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
