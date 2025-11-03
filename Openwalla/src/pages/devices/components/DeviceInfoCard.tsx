
import { ChevronRight, Monitor, Smartphone, Computer, Laptop, Printer, Router, Tablet, Tv, Usb, Server, Network, Gamepad, HardDrive, Cctv, EthernetPort, Wifi } from "lucide-react";
import { Device } from "@/misc/types/device";
import { useDeviceActivity } from "@/services/DeviceService";
import { DeviceTypeDialog } from "./DeviceTypeDialog";
import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "@/components/ui/use-toast";

interface DeviceInfoCardProps {
  device: Device;
  onNameClick: () => void;
  onIpClick: () => void;
}

interface InfoItemProps {
  label: string;
  value: string;
  icon?: React.ReactNode;
  hasChevron?: boolean;
  onClick?: () => void;
}

const deviceIcons: Record<string, any> = {
  computer: Computer,
  laptop: Laptop,
  smartphone: Smartphone,
  tablet: Tablet,
  router: Router,
  tv: Tv,
  printer: Printer,
  usb: Usb,
  server: Server,
  switch: Network,
  gaming: Gamepad,
  nas: HardDrive,
  cctv: Cctv,
  ethernet: EthernetPort,
  wifi: Wifi,
  'access-point': Wifi
};

const InfoItem = ({ label, value, icon, hasChevron, onClick }: InfoItemProps) => (
  <div 
    className={`flex items-center justify-between p-4 ${onClick ? 'cursor-pointer hover:bg-gray-800' : ''}`}
    onClick={onClick}
  >
    <span className="text-gray-300">{label}</span>
    <div className="flex items-center gap-2">
      {icon}
      <span className="text-white">{value}</span>
      {hasChevron && <ChevronRight className="w-5 h-5 text-gray-600" />}
    </div>
  </div>
);

export function DeviceInfoCard({ device, onNameClick, onIpClick }: DeviceInfoCardProps) {
  const { data: isActive, isLoading: isLoadingActivity } = useDeviceActivity(device.mac);
  const [isTypeDialogOpen, setIsTypeDialogOpen] = useState(false);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const { data: deviceType } = useQuery({
    queryKey: ['deviceType', device.mac],
    queryFn: async () => {
      const response = await fetch(`/api/devices/${device.mac}/type`);
      if (!response.ok) throw new Error('Failed to fetch device type');
      const data = await response.json();
      return data.type;
    }
  });

  const updateDeviceType = useMutation({
    mutationFn: async (type: string) => {
      const response = await fetch(`/api/devices/${device.mac}/type`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type })
      });
      if (!response.ok) throw new Error('Failed to update device type');
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['deviceType', device.mac] });
      toast({
        title: "Success",
        description: "Device type updated successfully",
      });
    },
    onError: () => {
      toast({
        variant: "destructive",
        title: "Error",
        description: "Failed to update device type",
      });
    }
  });

  const IconComponent = deviceIcons[deviceType || 'computer'];

  return (
    <div className="bg-dashboard-card rounded-lg divide-y divide-gray-800">
      <InfoItem 
        label="Device Name" 
        value={device.hostname} 
        hasChevron 
        onClick={onNameClick}
      />
      <InfoItem 
        label="Device Type" 
        value={deviceType || 'computer'}
        icon={<IconComponent className="w-5 h-5 text-blue-500" />}
        hasChevron 
        onClick={() => setIsTypeDialogOpen(true)}
      />
      <InfoItem 
        label="IP Address" 
        value={device.ip} 
        hasChevron 
        onClick={onIpClick}
      />
      <InfoItem 
        label="MAC Address" 
        value={device.mac}
      />
      <InfoItem 
        label="Status" 
        value={isLoadingActivity ? "Checking..." : (isActive ? "Active" : "Idle")}
      />

      <DeviceTypeDialog
        open={isTypeDialogOpen}
        onOpenChange={setIsTypeDialogOpen}
        currentType={deviceType}
        onSave={(type) => updateDeviceType.mutate(type)}
      />
    </div>
  );
}
