import { Card } from "@/components/ui/card";
import { Area, AreaChart, ResponsiveContainer } from "recharts";
import { useEffect, useState } from "react";
import { Device } from "@/services/DeviceService";
import { formatNetworkSpeed } from "@/misc/utils/networkFormatting";
import { ArrowDown, ArrowUp } from "lucide-react";
import { useQuery } from "@tanstack/react-query";

interface DataPoint {
  time: number;
  download: number;
  upload: number;
}

interface DeviceThroughputGraphProps {
  device: Device;
}

async function fetchDeviceRxTx(mac: string) {
  const response = await fetch(`/api/devices/${mac}/rx_tx`);
  if (!response.ok) {
    throw new Error('Failed to fetch RX/TX data');
  }
  return response.json();
}

export function DeviceThroughputGraph({ device }: DeviceThroughputGraphProps) {
  const [trafficHistory, setTrafficHistory] = useState<DataPoint[]>([]);
  
  const { data: rxTxData } = useQuery({
    queryKey: ['device-rx-tx', device.mac],
    queryFn: () => fetchDeviceRxTx(device.mac),
    refetchInterval: 5000, // Refresh every 5 seconds
  });
  
  useEffect(() => {
    if (rxTxData) {
      setTrafficHistory(prev => {
        const newPoint = {
          time: Date.now(),
          download: rxTxData.rx_diff || 0,
          upload: rxTxData.tx_diff || 0
        };
        
        const updatedHistory = [...prev, newPoint].slice(-60);
        return updatedHistory;
      });
    }
  }, [rxTxData]);

  const currentDownload = rxTxData?.rx_diff || 0;
  const currentUpload = rxTxData?.tx_diff || 0;

  return (
    <Card className="bg-dashboard-card p-4 mb-4">
      <div className="h-[200px] mb-4">
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
          <span className="font-bold text-white">{formatNetworkSpeed(currentUpload)}</span>
          <span className="text-gray-400">Upload</span>
        </div>
        <div className="flex items-center gap-2">
          <ArrowDown className="h-4 w-4 text-[#0EA5E9]" />
          <span className="font-bold text-white">{formatNetworkSpeed(currentDownload)}</span>
          <span className="text-gray-400">Download</span>
        </div>
      </div>
    </Card>
  );
}