import { Card } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";

interface NetworkCardProps {
  title: string;
  value: string | number;
  subtitle?: string;
  progress?: number;
  className?: string;
}

export function NetworkCard({ title, value, subtitle, progress, className = "" }: NetworkCardProps) {
  // Function to determine progress bar color based on value
  const getProgressColor = (value: number) => {
    if (value >= 80) return "bg-dashboard-success";
    if (value >= 60) return "bg-[#D3E4FD]";
    return "bg-dashboard-accent";
  };

  return (
    <Card className={`bg-dashboard-card p-4 ${className}`} data-testid="network-card">
      <div className="network-card-content">
        <h3 className="text-gray-400 text-sm mb-2">{title}</h3>
        <div className="flex items-baseline gap-2">
          <span className="text-xl md:text-2xl font-bold text-white">{value}</span>
          {subtitle && <span className="text-sm text-gray-400">{subtitle}</span>}
        </div>
        {progress !== undefined && (
          <Progress 
            value={progress} 
            className="mt-4 bg-gray-700" 
            indicatorClassName={getProgressColor(progress)}
          />
        )}
      </div>
    </Card>
  );
}