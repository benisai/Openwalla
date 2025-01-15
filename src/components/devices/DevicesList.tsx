import { Network, Bluetooth, BluetoothConnected, Wifi, WifiHigh, WifiLow, EthernetPort, Monitor } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { useNavigate } from "react-router-dom";
import { Device, useDeviceActivity } from "@/services/DeviceService";
import { formatBytes } from "@/utils/networkFormatting";
import { useQuery } from "@tanstack/react-query";

interface DevicesListProps {
  devices: Device[];
}

const getDeviceIcon = (type: string) => {
  switch (type?.toLowerCase()) {
    case 'network':
      return <Network className="w-6 h-6 text-blue-500" />;
    case 'bluetooth':
      return <Bluetooth className="w-6 h-6 text-blue-500" />;
    case 'bluetooth_connected':
      return <BluetoothConnected className="w-6 h-6 text-blue-500" />;
    case 'wifi':
      return <Wifi className="w-6 h-6 text-blue-500" />;
    case 'wifi_high':
      return <WifiHigh className="w-6 h-6 text-blue-500" />;
    case 'wifi_low':
      return <WifiLow className="w-6 h-6 text-blue-500" />;
    case 'ethernet':
      return <EthernetPort className="w-6 h-6 text-blue-500" />;
    default:
      return <Monitor className="w-6 h-6 text-blue-500" />;
  }
};

const DeviceItem = ({ device }: { device: Device }) => {
  const navigate = useNavigate();
  const { data: isActive, isLoading } = useDeviceActivity(device.mac);
  
  const { data: deviceType } = useQuery({
    queryKey: ['deviceType', device.mac],
    queryFn: async () => {
      const response = await fetch(`/api/devices/${device.mac}/type`);
      if (!response.ok) throw new Error('Failed to fetch device type');
      const data = await response.json();
      return data.type;
    }
  });

  return (
    <div
      key={device.mac}
      className="bg-dashboard-card p-4 rounded-lg flex items-center justify-between cursor-pointer hover:opacity-90 transition-opacity"
      onClick={() => navigate(`/devices/${device.mac}`)}
    >
      <div className="flex items-center gap-4">
        {getDeviceIcon(deviceType)}
        <div>
          <h3 className="font-medium">{device.hostname}</h3>
          <p className="text-sm text-gray-400">{device.ip}</p>
          <p className="text-sm text-gray-400">
            ↓ {formatBytes(device.total_download)} ↑ {formatBytes(device.total_upload)}
          </p>
        </div>
      </div>
      <Badge variant="secondary" className="bg-gray-700 text-white">
        {isLoading ? '...' : isActive ? 'Active' : 'Idle'}
      </Badge>
    </div>
  );
};

const DevicesList = ({ devices }: DevicesListProps) => {
  return (
    <div className="space-y-4">
      {devices.map((device) => (
        <DeviceItem key={device.mac} device={device} />
      ))}
    </div>
  );
};

export default DevicesList;