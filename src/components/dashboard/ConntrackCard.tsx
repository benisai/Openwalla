import { Card } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";

interface ConntrackCardProps {
  connections: number;
}

export function ConntrackCard({ connections }: ConntrackCardProps) {
  // Dynamic max connections based on current usage
  const getMaxConnections = (current: number) => {
    if (current >= 750 && current < 2800) {
      return 2000;
    } else if (current >= 2800) {
      return 16384;
    }
    return 1000;
  };

  const maxConnections = getMaxConnections(connections);
  const percentage = Math.min((connections / maxConnections) * 100, 100);

  return (
    <Card className="bg-dashboard-card p-4 my-4" data-testid="conntrack-card">
      <div className="conntrack-content">
        <h3 className="text-gray-400 text-sm mb-2">Conntrack</h3>
        <div className="flex items-baseline gap-2">
          <span className="text-base md:text-2xl font-bold text-white">{connections}</span>
          <span className="text-sm text-gray-400">connections</span>
        </div>
        <Progress 
          value={percentage} 
          className="mt-4 bg-gray-700" 
          indicatorClassName="bg-dashboard-chart"
        />
        <div className="mt-2 text-xs text-gray-400">
          {percentage.toFixed(1)}% of maximum capacity ({maxConnections.toLocaleString()} max)
        </div>
      </div>
    </Card>
  );
}