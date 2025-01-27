import { Card } from "@/components/ui/card";
import { ArrowDown, ArrowUp, ChevronRight } from "lucide-react";
import { Area, AreaChart, ResponsiveContainer } from "recharts";
import { useNavigate } from "react-router-dom";
import type { SystemMetrics } from "@/services/NetdataService";
import { useEffect, useState } from "react";
import { formatNetworkSpeed } from "@/misc/utils/networkFormatting";

interface DataPoint {
  time: number;
  download: number;
  upload: number;
}

interface LiveWanTrafficProps {
  metrics: SystemMetrics;
}

export function LiveWanTraffic({ metrics }: LiveWanTrafficProps) {
  const navigate = useNavigate();
  const [trafficHistory, setTrafficHistory] = useState<DataPoint[]>([]);
  
  useEffect(() => {
    // Add new data point
    setTrafficHistory(prev => {
      const newPoint = {
        time: Date.now(),
        download: metrics.sent, // Swapped from received to sent
        upload: metrics.received // Swapped from sent to received
      };
      
      // Keep last 60 data points instead of 30
      const updatedHistory = [...prev, newPoint].slice(-60);
      return updatedHistory;
    });
  }, [metrics]);

  return (
    <Card 
      className="bg-dashboard-card p-4 mb-4 cursor-pointer hover:bg-dashboard-card/90 transition-colors"
      onClick={() => navigate('/device-live-throughput')}
    >
      <div className="flex items-center justify-between mb-2">
        <h3 className="text-gray-400 text-sm flex items-center gap-2">
          Live Throughput - WAN
          <ChevronRight className="h-4 w-4" />
        </h3>
      </div>
      
      <div className="h-[100px] mb-4">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={trafficHistory}>
            <defs>
              <linearGradient id="colorDownload" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#0EA5E9" stopOpacity={0.1}/>
                <stop offset="95%" stopColor="#0EA5E9" stopOpacity={0}/>
              </linearGradient>
              <linearGradient id="colorUpload" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#F97316" stopOpacity={0.1}/>
                <stop offset="95%" stopColor="#F97316" stopOpacity={0}/>
              </linearGradient>
            </defs>
            <Area
              type="monotone"
              dataKey="download"
              stroke="#0EA5E9"
              fill="url(#colorDownload)"
              strokeWidth={2}
            />
            <Area
              type="monotone"
              dataKey="upload"
              stroke="#F97316"
              fill="url(#colorUpload)"
              strokeWidth={2}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      <div className="flex justify-between text-sm">
        <div className="flex items-center gap-2">
          <ArrowUp className="h-4 w-4 text-[#F97316]" />
          <span className="font-bold text-white">{formatNetworkSpeed(metrics.received)}</span>
          <span className="text-gray-400">Upload</span>
        </div>
        <div className="flex items-center gap-2">
          <ArrowDown className="h-4 w-4 text-[#0EA5E9]" />
          <span className="font-bold text-white">{formatNetworkSpeed(metrics.sent)}</span>
          <span className="text-gray-400">Download</span>
        </div>
      </div>
    </Card>
  );
}
