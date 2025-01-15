import { Card } from "@/components/ui/card";
import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { useIsMobile } from "@/hooks/use-mobile";
import { useQuery } from "@tanstack/react-query";
import { formatBytes } from "@/utils/networkFormatting";

interface HourlyData {
  year: number;
  month: number;
  day: number;
  hour: number;
  rx: number;
  tx: number;
  interface_name: string;
}

async function fetchHourlyData(): Promise<HourlyData[]> {
  const response = await fetch('/api/vnstat/hourly');
  if (!response.ok) {
    throw new Error('Network response was not ok');
  }
  const data = await response.json();
  return data;
}

export function WanGraph24hrs() {
  const isMobile = useIsMobile();

  const { data: hourlyData = [], isLoading, error } = useQuery({
    queryKey: ['vnstat-hourly'],
    queryFn: fetchHourlyData,
    refetchInterval: 60 * 1000, // Refetch every minute
    meta: {
      onError: (error: Error) => {
        console.error('Error fetching hourly data:', error);
      }
    }
  });

  const interfaceName = hourlyData[0]?.interface_name || 'Unknown';

  // Format data for the chart
  const chartData = hourlyData.map(hour => ({
    hour: `${hour.hour}:00`,
    rx: hour.rx,
    tx: hour.tx
  }));

  return (
    <Card className="bg-dashboard-card p-4 h-[300px]">
      <h3 className="text-gray-400 text-sm mb-4">{`${interfaceName} Usage - 12 Hours`}</h3>
      <div className="h-[230px]">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData} margin={{ top: 10, right: 30, left: 0, bottom: 0 }}>
            <XAxis 
              dataKey="hour" 
              stroke="#6B7280" 
              fontSize={12} 
              tickLine={false} 
              axisLine={false} 
            />
            <YAxis 
              stroke="#6B7280" 
              fontSize={12} 
              tickLine={false} 
              axisLine={false}
              tickFormatter={(value) => formatBytes(value)}
            />
            <Tooltip
              contentStyle={{ 
                background: "#1F2937", 
                border: "none", 
                borderRadius: "8px" 
              }}
              itemStyle={{ color: "#fff" }}
              formatter={(value: number) => formatBytes(value)}
            />
            <Bar 
              dataKey="tx" 
              name="Download"
              fill="#0EA5E9"
              radius={[4, 4, 0, 0]}
            />
            <Bar 
              dataKey="rx" 
              name="Upload"
              fill="#F97316"
              radius={[4, 4, 0, 0]}
              opacity={0.7}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}