
import { ApplicationUsage } from "@/services/ApplicationUsageService";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { formatBytes } from "@/misc/utils/networkFormatting";
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { useEffect, useState } from "react";

interface UsageTimelineChartProps {
  data: ApplicationUsage['timelineData'];
  isLoading: boolean;
  deviceMac?: string; // Optional device MAC to fetch data directly
}

const formatXAxis = (hour: number) => {
  // Format 24-hour to 12-hour with AM/PM
  if (hour === 0) return '12 AM';
  if (hour === 12) return '12 PM';
  if (hour < 12) return `${hour} AM`;
  return `${hour - 12} PM`;
};

const CustomTooltip = ({ active, payload }: any) => {
  if (active && payload && payload.length) {
    return (
      <div className="bg-dashboard-card p-2 border border-gray-700 rounded text-sm">
        <p className="label">
          {formatXAxis(payload[0].payload.hour)}
        </p>
        <p className="text-blue-400">
          {formatBytes(payload[0].value)}
        </p>
      </div>
    );
  }

  return null;
};

export function UsageTimelineChart({ data, isLoading, deviceMac }: UsageTimelineChartProps) {
  const [hourlyData, setHourlyData] = useState<any[]>([]);
  const [loading, setLoading] = useState<boolean>(isLoading);
  
  // Fetch hourly data directly if deviceMac is provided
  useEffect(() => {
    if (deviceMac) {
      setLoading(true);
      fetch(`/api/application-usage/device/${deviceMac}/hourly`)
        .then(response => {
          if (!response.ok) {
            throw new Error('Failed to fetch hourly data');
          }
          return response.json();
        })
        .then(data => {
          // Ensure data is an array before setting
          setHourlyData(Array.isArray(data) ? data : []);
          setLoading(false);
        })
        .catch(error => {
          console.error('Error fetching hourly data:', error);
          setLoading(false);
        });
    } else {
      // Use the data provided via props, ensure it's an array
      setHourlyData(Array.isArray(data) ? data : []);
      setLoading(isLoading);
    }
  }, [deviceMac, data, isLoading]);

  if (loading) {
    return (
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">24-Hour Usage Timeline</h3>
        <div className="h-64">
          <Skeleton className="w-full h-full rounded-md" />
        </div>
      </Card>
    );
  }

  if (!hourlyData || hourlyData.length === 0) {
    return (
      <Card className="bg-dashboard-card p-4">
        <h3 className="text-gray-400 text-sm mb-4">24-Hour Usage Timeline</h3>
        <div className="h-64 flex items-center justify-center">
          <p className="text-gray-500">No timeline data available</p>
        </div>
      </Card>
    );
  }

  // Ensure the data is sorted by hour
  const sortedData = [...hourlyData].sort((a, b) => a.hour - b.hour);
  
  // Fill in missing hours with zero usage
  const filledData = [];
  for (let hour = 0; hour < 24; hour++) {
    const existingData = sortedData.find(item => item.hour === hour);
    if (existingData) {
      filledData.push(existingData);
    } else {
      filledData.push({ hour, usage: 0 });
    }
  }

  return (
    <Card className="bg-dashboard-card p-4">
      <h3 className="text-gray-400 text-sm mb-4">24-Hour Usage Timeline</h3>
      <div className="h-64">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart
            data={filledData}
            margin={{ top: 0, right: 0, left: 0, bottom: 0 }}
          >
            <defs>
              <linearGradient id="colorUsage" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.8} />
                <stop offset="95%" stopColor="#3b82f6" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="#444" />
            <XAxis 
              dataKey="hour" 
              tick={{ fill: '#9ca3af' }} 
              tickFormatter={formatXAxis} 
            />
            <YAxis 
              tick={{ fill: '#9ca3af' }} 
              tickFormatter={formatBytes} 
              width={80}
            />
            <Tooltip content={<CustomTooltip />} />
            <Area
              type="monotone"
              dataKey="usage"
              stroke="#3b82f6"
              fillOpacity={1}
              fill="url(#colorUsage)"
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}
