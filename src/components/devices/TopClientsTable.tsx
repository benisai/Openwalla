import { useQuery } from "@tanstack/react-query";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Skeleton } from "@/components/ui/skeleton";

interface TopClient {
  local_mac: string;
  count: number;
  name: string;
}

async function getTopClients(): Promise<TopClient[]> {
  const response = await fetch('/api/flows/top-clients/24h');
  if (!response.ok) {
    throw new Error('Failed to fetch top clients');
  }
  return response.json();
}

export function TopClientsTable() {
  const { data: topClients = [], isLoading } = useQuery({
    queryKey: ['topClients'],
    queryFn: getTopClients,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  const renderSkeletonRows = () => (
    Array(5).fill(0).map((_, i) => (
      <TableRow key={i}>
        <TableCell><Skeleton className="h-4 w-48 bg-gray-700" /></TableCell>
        <TableCell><Skeleton className="h-4 w-32 bg-gray-700" /></TableCell>
        <TableCell className="text-right"><Skeleton className="h-4 w-12 bg-gray-700 ml-auto" /></TableCell>
      </TableRow>
    ))
  );

  return (
    <div className="bg-dashboard-card rounded-lg p-4">
      <h3 className="text-lg font-semibold mb-4">Top 10 Active Devices - HTTPS Traffic (24h)</h3>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Device Name</TableHead>
            <TableHead>MAC Address</TableHead>
            <TableHead className="text-right">HTTPS Flow Count</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {isLoading ? (
            renderSkeletonRows()
          ) : (
            topClients.map((client, index) => (
              <TableRow key={index}>
                <TableCell className="font-medium">{client.name}</TableCell>
                <TableCell className="font-mono">{client.local_mac}</TableCell>
                <TableCell className="text-right">{client.count}</TableCell>
              </TableRow>
            ))
          )}
        </TableBody>
      </Table>
    </div>
  );
}