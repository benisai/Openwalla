
import { ArrowLeft, Home, RefreshCcw } from "lucide-react";
import { Link } from "react-router-dom";
import { Card } from "@/components/ui/card";
import { Area, AreaChart, ResponsiveContainer, XAxis, YAxis, Tooltip, Legend } from "recharts";
import { useState, useEffect } from "react";
import { useDevicesRxTx } from "@/services/RxTxService";
import { useDevices } from "@/services/DeviceService";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { formatNetworkSpeed } from "@/misc/utils/networkFormatting";

const deviceColors = [
  "#8B5CF6", // Vivid Purple
  "#D946EF", // Magenta Pink
  "#F97316", // Bright Orange
  "#0EA5E9", // Ocean Blue
  "#10B981", // Emerald
  "#6366F1", // Indigo
  "#EC4899", // Pink
  "#14B8A6", // Teal
  "#F59E0B", // Amber
  "#84CC16", // Lime
];

const DeviceLiveThroughput = () => {
  const [selectedTimeframe, setSelectedTimeframe] = useState("real-time");
  const [chartData, setChartData] = useState<any[]>([]);
  const [hiddenDevices, setHiddenDevices] = useState<Set<string>>(new Set());
  
  const { data: devices = [] } = useDevices();
  const { data: rxTxData = [], isLoading } = useDevicesRxTx(selectedTimeframe);

  const timeframeOptions = [
    { value: "real-time", label: "Real-time" },
    { value: "5-min", label: "5 Minutes" },
    { value: "15-min", label: "15 Minutes" },
    { value: "60-min", label: "60 Minutes" },
  ];

  useEffect(() => {
    if (rxTxData.length > 0) {
      const deviceMap = new Map(devices.map(d => [d.mac, d.hostname || d.mac]));
      
      const newDataPoint = {
        timestamp: new Date().getTime(),
      };

      rxTxData.forEach(data => {
        const deviceName = deviceMap.get(data.mac) || data.mac;
        newDataPoint[`${deviceName}_rx`] = data.rx_diff;
        newDataPoint[`${deviceName}_tx`] = data.tx_diff;
      });

      setChartData(prev => {
        const newData = [...prev, newDataPoint];
        const maxPoints = selectedTimeframe === 'real-time' ? 60 : 
                        selectedTimeframe === '5-min' ? 300 :
                        selectedTimeframe === '15-min' ? 900 : 3600;
        return newData.slice(-maxPoints);
      });
    }
  }, [rxTxData, devices]);

  const toggleDeviceVisibility = (deviceMac: string) => {
    setHiddenDevices(prev => {
      const newSet = new Set(prev);
      if (newSet.has(deviceMac)) {
        newSet.delete(deviceMac);
      } else {
        newSet.add(deviceMac);
      }
      return newSet;
    });
  };

  const getDeviceColor = (index: number) => {
    return deviceColors[index % deviceColors.length];
  };

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4 md:px-0">
      <div className="md:max-w-7xl mx-auto">
        <header className="flex justify-between items-center mb-6">
          <Link to="/">
            <ArrowLeft className="w-6 h-6 text-dashboard-accent" />
          </Link>
          <div className="flex items-center gap-4">
            <Select
              value={selectedTimeframe}
              onValueChange={setSelectedTimeframe}
            >
              <SelectTrigger className="w-[180px] bg-dashboard-card text-white border-none">
                <SelectValue placeholder="Select timeframe" />
              </SelectTrigger>
              <SelectContent className="bg-dashboard-card text-white border-none">
                {timeframeOptions.map(option => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <span className="text-xl font-bold">Live Device Throughput</span>
            <RefreshCcw 
              className={`w-5 h-5 text-dashboard-accent cursor-pointer ${isLoading ? 'animate-spin' : ''}`}
            />
          </div>
          <Link to="/">
            <Home className="w-6 h-6 text-dashboard-accent" />
          </Link>
        </header>

        <Card className="bg-dashboard-card p-4 mb-6">
          <div className="flex gap-4 mb-4 flex-wrap">
            {devices.map((device, index) => (
              <button
                key={device.mac}
                onClick={() => toggleDeviceVisibility(device.mac)}
                className={`px-3 py-1 rounded-full text-sm transition-opacity ${
                  hiddenDevices.has(device.mac) ? 'opacity-50' : 'opacity-100'
                }`}
                style={{ backgroundColor: getDeviceColor(index) }}
              >
                {device.hostname || device.mac}
              </button>
            ))}
          </div>
          <div className="h-[600px]">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartData}>
                <defs>
                  {devices.map((device, index) => (
                    <>
                      <linearGradient
                        key={`${device.mac}_rx_gradient`}
                        id={`${device.mac}_rx_gradient`}
                        x1="0" y1="0" x2="0" y2="1"
                      >
                        <stop offset="5%" stopColor={getDeviceColor(index)} stopOpacity={0.1}/>
                        <stop offset="95%" stopColor={getDeviceColor(index)} stopOpacity={0}/>
                      </linearGradient>
                      <linearGradient
                        key={`${device.mac}_tx_gradient`}
                        id={`${device.mac}_tx_gradient`}
                        x1="0" y1="0" x2="0" y2="1"
                      >
                        <stop offset="5%" stopColor={getDeviceColor(index)} stopOpacity={0.1}/>
                        <stop offset="95%" stopColor={getDeviceColor(index)} stopOpacity={0}/>
                      </linearGradient>
                    </>
                  ))}
                </defs>
                <XAxis 
                  dataKey="timestamp" 
                  tickFormatter={(value) => new Date(value).toLocaleTimeString()}
                  stroke="#6B7280"
                />
                <YAxis 
                  tickFormatter={(value) => formatNetworkSpeed(value)}
                  stroke="#6B7280"
                />
                <Tooltip
                  contentStyle={{ 
                    backgroundColor: "#1F2937",
                    border: "none",
                    borderRadius: "8px"
                  }}
                  labelFormatter={(value) => new Date(value).toLocaleTimeString()}
                  formatter={(value: number) => [formatNetworkSpeed(value), ""]}
                />
                <Legend />
                {devices.map((device, index) => (
                  !hiddenDevices.has(device.mac) && (
                    <>
                      <Area
                        key={`${device.mac}_rx`}
                        type="monotone"
                        dataKey={`${device.hostname || device.mac}_rx`}
                        name={`${device.hostname || device.mac} ↓`}
                        stroke={getDeviceColor(index)}
                        fill={`url(#${device.mac}_rx_gradient)`}
                        strokeWidth={2}
                      />
                      <Area
                        key={`${device.mac}_tx`}
                        type="monotone"
                        dataKey={`${device.hostname || device.mac}_tx`}
                        name={`${device.hostname || device.mac} ↑`}
                        stroke={getDeviceColor(index)}
                        fill={`url(#${device.mac}_tx_gradient)`}
                        strokeWidth={2}
                      />
                    </>
                  )
                ))}
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Card>
      </div>
    </div>
  );
};

export default DeviceLiveThroughput;
