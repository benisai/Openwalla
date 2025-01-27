import { Card } from "@/components/ui/card";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { getLast24HoursFlowCount } from "@/services/FlowService";
import { Skeleton } from "@/components/ui/skeleton";

export function Flows24() {
  const navigate = useNavigate();

  const { data: flowCount, isLoading } = useQuery({
    queryKey: ['flows-24h'],
    queryFn: getLast24HoursFlowCount,
    refetchInterval: 30000, // Refresh every 30 seconds
  });

  return (
    <Card 
      className="bg-dashboard-card p-4 cursor-pointer hover:opacity-90 transition-opacity" 
      data-testid="network-card"
      onClick={() => navigate("/flows")}
    >
      <div className="network-card-content">
        <h3 className="text-gray-400 text-sm mb-2">Flows in last 24hrs</h3>
        <div className="flex items-baseline gap-2">
          {isLoading ? (
            <Skeleton className="h-8 w-24 bg-gray-700" />
          ) : (
            <span className="text-xl md:text-2xl font-bold text-white">
              {flowCount?.toLocaleString() || '0'}
            </span>
          )}
        </div>
      </div>
    </Card>
  );
}