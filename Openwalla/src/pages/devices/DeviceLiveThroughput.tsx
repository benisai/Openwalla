import { ArrowLeft, Home } from "lucide-react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import axios from "axios";
import { formatNetworkSpeed } from "@/misc/utils/networkFormatting";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { useState } from "react";
import { Button } from "@/components/ui/button";

interface RxTxData {
  mac: string;
  hostname: string;
  rx_diff: number;
  tx_diff: number;
  timestamp: number;
}

type TimeRange = "realtime" | "5" | "15" | "60";

const fetchRxTxData = async (minutes: TimeRange): Promise<RxTxData[]> => {
  const response = await axios.get(`/api/devices/rx_tx/range/${minutes}`);
  return response.data;
};

const DeviceLiveThroughput = () => {
  const [timeRange, setTimeRange] = useState<TimeRange>("realtime");

  const { data, isLoading } = useQuery({
    queryKey: ['rxTxData', timeRange],
    queryFn: () => fetchRxTxData(timeRange),
    refetchInterval: timeRange === "realtime" ? 15000 : false,
  });

  // Process data for the chart
  const chartData = data?.reduce((acc: any[], curr: RxTxData) => {
    const existingPoint = acc.find(p => p.timestamp === curr.timestamp);
    if (existingPoint) {
      existingPoint[`${curr.hostname}_rx`] = curr.rx_diff;
      existingPoint[`${curr.hostname}_tx`] = curr.tx_diff;
    } else {
      const newPoint = {
        timestamp: curr.timestamp,
        [`${curr.hostname}_rx`]: curr.rx_diff,
        [`${curr.hostname}_tx`]: curr.tx_diff,
      };
      acc.push(newPoint);
    }
    return acc;
  }, []).sort((a: any, b: any) => a.timestamp - b.timestamp) || [];

  // Get unique devices for legend
  const devices = Array.from(new Set(data?.map((d: RxTxData) => d.hostname) || []));

  // Generate unique colors for each device
  const colors = [
    "#2563eb", // blue-600
    "#dc2626", // red-600
    "#16a34a", // green-600
    "#9333ea", // purple-600
    "#ea580c", // orange-600
    "#0891b2", // cyan-600
    "#4f46e5", // indigo-600
    "#c026d3", // fuchsia-600
  ];

  return (
    <div className="min-h-screen bg-dashboard-background p-4">
      <div className="max-w-[1400px] mx-auto">
        {/* Header */}
        <header className="flex justify-between items-center mb-6">
          <Link to="/" className="text-dashboard-accent hover:opacity-80">
            <ArrowLeft className="w-6 h-6" />
          </Link>
          <div className="flex items-center gap-2">
            <span className="text-xl font-bold text-white">Live Device Throughput</span>
          </div>
          <Link to="/" className="text-dashboard-accent hover:opacity-80">
            <Home className="w-6 h-6" />
          </Link>
        </header>

        {/* Time Range Selector */}
        <div className="flex justify-end gap-2 mb-4">
          <Button
            variant={timeRange === "realtime" ? "default" : "outline"}
            onClick={() => setTimeRange("realtime")}
            className="bg-dashboard-card hover:bg-dashboard-accent/20 border-dashboard-accent text-white"
          >
            Real-Time
          </Button>
          <Button
            variant={timeRange === "5" ? "default" : "outline"}
            onClick={() => setTimeRange("5")}
            className="bg-dashboard-card hover:bg-dashboard-accent/20 border-dashboard-accent text-white"
          >
            5-min
          </Button>
          <Button
            variant={timeRange === "15" ? "default" : "outline"}
            onClick={() => setTimeRange("15")}
            className="bg-dashboard-card hover:bg-dashboard-accent/20 border-dashboard-accent text-white"
          >
            15-min
          </Button>
          <Button
            variant={timeRange === "60" ? "default" : "outline"}
            onClick={() => setTimeRange("60")}
            className="bg-dashboard-card hover:bg-dashboard-accent/20 border-dashboard-accent text-white"
          >
            60-min
          </Button>
        </div>

        {/* Graph */}
        <div className="bg-dashboard-card rounded-lg p-6 shadow-lg">
          <div className="h-[600px]">
            {isLoading ? (
              <div className="flex items-center justify-center h-full">
                <span className="text-muted-foreground">Loading data...</span>
              </div>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.1)" />
                  <XAxis 
                    dataKey="timestamp"
                    tickFormatter={(timestamp) => new Date(timestamp).toLocaleTimeString()}
                    stroke="rgba(255,255,255,0.5)"
                  />
                  <YAxis 
                    tickFormatter={(value) => formatNetworkSpeed(value)}
                    stroke="rgba(255,255,255,0.5)"
                  />
                  <Tooltip 
                    formatter={(value: number) => formatNetworkSpeed(value)}
                    labelFormatter={(label) => new Date(label).toLocaleTimeString()}
                    contentStyle={{ 
                      backgroundColor: 'rgba(26, 31, 44, 0.9)', 
                      border: '1px solid rgba(255,255,255,0.2)',
                      borderRadius: '8px',
                      color: 'white'
                    }}
                  />
                  <Legend 
                    layout="horizontal"
                    verticalAlign="bottom"
                    align="center"
                    wrapperStyle={{ 
                      paddingTop: "20px",
                      color: "white"
                    }}
                  />
                  {devices.map((device, index) => (
                    <>
                      <Line
                        key={`${device}_rx`}
                        type="monotone"
                        dataKey={`${device}_rx`}
                        name={`${device} (Download)`}
                        stroke={colors[index % colors.length]}
                        strokeWidth={2}
                        dot={false}
                        connectNulls={true}
                      />
                      <Line
                        key={`${device}_tx`}
                        type="monotone"
                        dataKey={`${device}_tx`}
                        name={`${device} (Upload)`}
                        stroke={colors[index % colors.length]}
                        strokeWidth={2}
                        strokeDasharray="5 5"
                        dot={false}
                        connectNulls={true}
                      />
                    </>
                  ))}
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default DeviceLiveThroughput;