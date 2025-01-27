import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useState } from "react";
import { Computer, Laptop, Printer, Router, Smartphone, Tablet, Tv, Usb } from "lucide-react";

const deviceIcons = [
  { type: 'computer', icon: Computer },
  { type: 'laptop', icon: Laptop },
  { type: 'smartphone', icon: Smartphone },
  { type: 'tablet', icon: Tablet },
  { type: 'router', icon: Router },
  { type: 'tv', icon: Tv },
  { type: 'printer', icon: Printer },
  { type: 'usb', icon: Usb },
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
          {deviceIcons.map(({ type, icon: Icon }) => (
            <Button
              key={type}
              variant="ghost"
              className={`flex flex-col items-center p-4 hover:bg-gray-800 ${
                selectedType === type ? 'bg-gray-800 ring-2 ring-blue-500' : ''
              }`}
              onClick={() => setSelectedType(type)}
            >
              <Icon className="w-8 h-8 mb-2" />
              <span className="text-xs capitalize">{type}</span>
            </Button>
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}