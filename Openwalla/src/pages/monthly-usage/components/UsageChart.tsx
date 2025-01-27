import { Card } from "@/components/ui/card";
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  ReferenceLine,
} from "recharts";
import { useQuery } from "@tanstack/react-query";
import { formatBytes } from "@/misc/utils/networkFormatting";
import { getConfig } from "@/services/ConfigService";

interface DailyData {
  year: number;
  month: number;
  day: number;
  rx: number;
  tx: number;
  interface_name: string;
}

export function UsageChart() {
  const { data: dailyData = [] } = useQuery({
    queryKey: ['vnstat-daily'],
    queryFn: async () => {
      const response = await fetch('/api/vnstat/daily');
      if (!response.ok) {
        throw new Error('Network response was not ok');
      }
      return response.json();
    },
    refetchInterval: 60 * 60 * 1000,
  });

  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig,
  });

  const limitGB = parseFloat(config?.data_plan_limit || "500");
  const dataPlanLimit = limitGB * 1000 * 1000 * 1000;
  console.log('Data plan limit:', `${limitGB}GB (${formatBytes(dataPlanLimit)})`);

  const chartData = dailyData.map((day: DailyData) => {
    const totalBytes = day.rx + day.tx;
    const percentage = (totalBytes / dataPlanLimit) * 100;
    console.log(`Day ${day.day}: ${formatBytes(totalBytes)} / ${formatBytes(dataPlanLimit)} = ${percentage.toFixed(2)}%`);
    return {
      date: `${day.month}/${day.day}`,
      total: totalBytes,
      percentage
    };
  });

  const interfaceName = dailyData[0]?.interface_name || 'Unknown';

  return (
    <Card className="bg-dashboard-card p-4 mb-8">
      <h3 className="text-gray-400 text-sm mb-4">{interfaceName} Daily Usage</h3>
      <div className="h-[300px]">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={chartData}>
            <CartesianGrid strokeDasharray="3 3" stroke="#333" />
            <XAxis dataKey="date" stroke="#666" />
            <YAxis 
              stroke="#666" 
              tickFormatter={(value) => formatBytes(value)}
              yAxisId="bytes"
            />
            <YAxis 
              yAxisId="percentage"
              orientation="right"
              stroke="#666"
              tickFormatter={(value) => `${Math.round(value)}%`}
            />
            <Tooltip 
              contentStyle={{ 
                backgroundColor: '#222632',
                border: 'none',
                borderRadius: '8px',
              }}
              labelStyle={{ color: '#666' }}
              formatter={(value: number, name: string) => {
                if (name === 'total') return [formatBytes(value), 'Usage'];
                if (name === 'percentage') return [`${Math.round(value)}%`, 'Of Plan'];
                return [value, name];
              }}
            />
            <ReferenceLine 
              y={dataPlanLimit} 
              yAxisId="bytes"
              stroke="#ff4444" 
              strokeDasharray="3 3"
              label={{ 
                value: 'Data Plan Limit',
                position: 'right',
                fill: '#ff4444'
              }}
            />
            <Bar 
              dataKey="total" 
              fill="#0EA5E9"
              radius={[4, 4, 0, 0]}
              yAxisId="bytes"
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}
