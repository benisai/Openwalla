
import { useQuery } from "@tanstack/react-query";
import { getTopFQDNs, getTopApplications } from "@/services/FlowService";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { Skeleton } from "@/components/ui/skeleton";

interface DeviceTopTablesProps {
  deviceMac: string;
}

const truncateDomain = (domain: string, maxLength: number = 30) => {
  if (!domain) return '';
  if (domain.length <= maxLength) return domain;
  return '...' + domain.slice(-(maxLength - 3));
};

// Helper function to clean app names by removing "netify." prefix
const cleanAppName = (name: string): string => {
  if (!name) return 'Unknown';
  return name.replace(/^netify\./, '');
};

export function DeviceTopTables({ deviceMac }: DeviceTopTablesProps) {
  const { data: topFQDNs = [], isLoading: isLoadingFQDNs } = useQuery({
    queryKey: ['topFQDNs', deviceMac],
    queryFn: () => getTopFQDNs(deviceMac),
    enabled: !!deviceMac,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  const { data: topApplications = [], isLoading: isLoadingApps } = useQuery({
    queryKey: ['topApplications', deviceMac],
    queryFn: () => getTopApplications(deviceMac),
    enabled: !!deviceMac,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  const renderSkeletonRows = () => (
    Array(5).fill(0).map((_, i) => (
      <TableRow key={i}>
        <TableCell><Skeleton className="h-4 w-48 bg-gray-700" /></TableCell>
        <TableCell className="text-right"><Skeleton className="h-4 w-12 bg-gray-700" /></TableCell>
      </TableRow>
    ))
  );

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      <div className="bg-dashboard-card rounded-lg p-4">
        <h3 className="text-lg font-semibold mb-4">Top 10 HTTPS Domains (24h)</h3>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Domain</TableHead>
              <TableHead className="text-right">Count</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoadingFQDNs ? (
              renderSkeletonRows()
            ) : (
              topFQDNs.map((item, index) => (
                <TableRow key={index}>
                  <TableCell className="font-mono">
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger className="text-left">
                          {truncateDomain(item.fqdn)}
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>{item.fqdn}</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </TableCell>
                  <TableCell className="text-right">{item.count}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      <div className="bg-dashboard-card rounded-lg p-4">
        <h3 className="text-lg font-semibold mb-4">Top 10 Applications (24h)</h3>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Application</TableHead>
              <TableHead className="text-right">Count</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {isLoadingApps ? (
              renderSkeletonRows()
            ) : (
              topApplications.map((item, index) => (
                <TableRow key={index}>
                  <TableCell className="font-mono">{cleanAppName(item.detected_app_name)}</TableCell>
                  <TableCell className="text-right">{item.count}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
