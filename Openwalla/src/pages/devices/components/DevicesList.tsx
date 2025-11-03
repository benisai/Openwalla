import { 
  Network, 
  Bluetooth, 
  BluetoothConnected, 
  Wifi, 
  WifiHigh, 
  WifiLow, 
  EthernetPort, 
  Monitor, 
  Smartphone, 
  Laptop, 
  Router,
  Server,
  Gamepad,
  HardDrive,
  Cctv,
  Tv
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { useNavigate } from "react-router-dom";
import { Device, useDeviceActivity, useDeviceType } from "@/services/DeviceService";
import { formatBytes } from "@/misc/utils/networkFormatting";

interface DevicesListProps {
  devices: Device[];
}

const getDeviceIcon = (type: string) => {
  switch (type?.toLowerCase()) {
    case 'laptop':
      return <Laptop className="w-6 h-6 text-blue-500" />;
    case 'smartphone':
      return <Smartphone className="w-6 h-6 text-blue-500" />;
    case 'router':
      return <Router className="w-6 h-6 text-blue-500" />;
    case 'switch':
      return <Network className="w-6 h-6 text-blue-500" />;
    case 'server':
      return <Server className="w-6 h-6 text-blue-500" />;
    case 'nas':
      return <HardDrive className="w-6 h-6 text-blue-500" />;
    case 'gaming':
      return <Gamepad className="w-6 h-6 text-blue-500" />;
    case 'network':
      return <Network className="w-6 h-6 text-blue-500" />;
    case 'bluetooth':
      return <Bluetooth className="w-6 h-6 text-blue-500" />;
    case 'bluetooth_connected':
      return <BluetoothConnected className="w-6 h-6 text-blue-500" />;
    case 'wifi':
      return <Wifi className="w-6 h-6 text-blue-500" />;
    case 'access-point':
      return <Wifi className="w-6 h-6 text-blue-500" />;
    case 'wifi_high':
      return <WifiHigh className="w-6 h-6 text-blue-500" />;
    case 'wifi_low':
      return <WifiLow className="w-6 h-6 text-blue-500" />;
    case 'ethernet':
      return <EthernetPort className="w-6 h-6 text-blue-500" />;
    case 'cctv':
      return <Cctv className="w-6 h-6 text-blue-500" />;
    case 'tv':
      return <Tv className="w-6 h-6 text-blue-500" />;
    default:
      return <Monitor className="w-6 h-6 text-blue-500" />;
  }
};

const DeviceItem = ({ device }: { device: Device }) => {
  const navigate = useNavigate();
  const { data: isActive, isLoading } = useDeviceActivity(device.mac);
  const { data: deviceType } = useDeviceType(device.mac);
  
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
          <p className="text-sm text-gray-400">
            {device.ip} | {device.mac}
          </p>
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
