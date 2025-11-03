import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { 
  Computer, 
  Laptop, 
  Printer, 
  Router, 
  Smartphone, 
  Tablet, 
  Tv, 
  Usb,
  Server,
  Network,
  Gamepad,
  HardDrive,
  Cctv,
  EthernetPort,
  Wifi,
} from "lucide-react";

const deviceIcons = [
  { type: 'computer', icon: Computer, label: 'Computer' },
  { type: 'laptop', icon: Laptop, label: 'Laptop' },
  { type: 'smartphone', icon: Smartphone, label: 'Smartphone' },
  { type: 'tablet', icon: Tablet, label: 'Tablet' },
  { type: 'router', icon: Router, label: 'Router' },
  { type: 'access-point', icon: Wifi, label: 'Access Point' },
  { type: 'wifi', icon: Wifi, label: 'WiFi' },
  { type: 'switch', icon: Network, label: 'Switch' },
  { type: 'server', icon: Server, label: 'Server' },
  { type: 'nas', icon: HardDrive, label: 'NAS' },
  { type: 'tv', icon: Tv, label: 'TV' },
  { type: 'printer', icon: Printer, label: 'Printer' },
  { type: 'gaming', icon: Gamepad, label: 'Gaming' },
  { type: 'cctv', icon: Cctv, label: 'Camera' },
  { type: 'ethernet', icon: EthernetPort, label: 'Ethernet' },
  { type: 'usb', icon: Usb, label: 'USB' },
];

interface DeviceTypeDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentType?: string;
  onSave: (type: string) => void;
}

export function DeviceTypeDialog({
  open,
  onOpenChange,
  currentType = 'computer',
  onSave,
}: DeviceTypeDialogProps) {
  const [selectedType, setSelectedType] = useState(currentType);

  const handleSave = () => {
    onSave(selectedType);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md">
        <DialogHeader className="space-y-4">
          <div className="flex justify-between items-center">
            <Button
              variant="ghost"
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <DialogTitle className="text-white">Device Type</DialogTitle>
            <Button
              variant="ghost"
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={handleSave}
            >
              Save
            </Button>
          </div>
        </DialogHeader>

        <div className="grid grid-cols-4 gap-4 mt-8">
          {deviceIcons.map(({ type, icon: Icon, label }) => (
            <Button
              key={type}
              variant="ghost"
              className={`relative flex flex-col items-center p-4 hover:bg-gray-800 transition-all ${
                selectedType === type 
                  ? 'bg-gray-800 ring-2 ring-blue-500 ring-offset-2 ring-offset-gray-900' 
                  : ''
              }`}
              onClick={() => setSelectedType(type)}
            >
              <Icon className="w-8 h-8 mb-2" />
              <span className="text-xs capitalize">{label}</span>
            </Button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}
