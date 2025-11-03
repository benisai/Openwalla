
import { Card } from "@/components/ui/card";
import { formatBytes } from "@/misc/utils/networkFormatting";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from "recharts";

interface TopApplicationsChartProps {
  data: {
    name: string;
    bytesUsed: number;
    percentage: number;
  }[];
  isLoading?: boolean;
}

const COLORS = ["#3b82f6", "#60a5fa", "#93c5fd", "#bfdbfe", "#dbeafe"];

export function TopApplicationsChart({ data, isLoading = false }: TopApplicationsChartProps) {
  if (isLoading) {
    return (
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">Top Applications</h3>
        <div className="h-64">
          <Skeleton className="w-full h-full rounded-full" />
        </div>
      </Card>
    );
  }

  // Take only top 5 applications for pie chart, excluding "Unknown"
  const topApps = data.filter(app => app.name.toLowerCase() !== 'unknown').slice(0, 5);

  return (
    <Card className="bg-dashboard-card p-4">
      <h3 className="text-gray-400 text-sm mb-4">Top Applications</h3>
      <div className="h-64">
        {topApps.length === 0 ? (
          <div className="h-full flex items-center justify-center">
            <p className="text-sm text-gray-400">No application data available</p>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={topApps}
                cx="50%"
                cy="50%"
                labelLine={false}
                outerRadius={80}
                fill="#8884d8"
                dataKey="bytesUsed"
              >
                {topApps.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip
                formatter={(value: number) => formatBytes(value)}
                contentStyle={{
                  backgroundColor: "#1f2937",
                  borderColor: "#374151",
                  color: "#ffffff",
                }}
              />
              <Legend
                formatter={(value) => <span style={{ color: "#9ca3af" }}>{value}</span>}
              />
            </PieChart>
          </ResponsiveContainer>
        )}
      </div>
    </Card>
  );
}
