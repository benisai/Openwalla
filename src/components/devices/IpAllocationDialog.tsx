import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { useState } from "react";

interface IpAllocationDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentIp: string;
  currentAllocation: "dynamic" | "reserved" | "none";
  onSave: (allocation: "dynamic" | "reserved" | "none", newIp?: string) => void;
}

export function IpAllocationDialog({
  open,
  onOpenChange,
  currentIp,
  currentAllocation,
  onSave,
}: IpAllocationDialogProps) {
  const [selectedAllocation, setSelectedAllocation] = useState<"dynamic" | "reserved">(
    currentAllocation === "none" ? "dynamic" : currentAllocation
  );
  const [ipAddress, setIpAddress] = useState(currentIp);

  const handleAllocationChange = (value: "dynamic" | "reserved") => {
    setSelectedAllocation(value);
  };

  const handleSave = () => {
    onSave(selectedAllocation, selectedAllocation === "reserved" ? ipAddress : undefined);
    onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader className="px-6 pt-6">
          <DialogTitle className="text-white">IP Address</DialogTitle>
        </DialogHeader>

        <div className="flex-1 overflow-y-auto px-6 pb-6">
          <div className="space-y-6">
            <div>
              <h3 className="text-gray-400 mb-4">IP ALLOCATION</h3>
              <RadioGroup
                defaultValue={currentAllocation}
                onValueChange={handleAllocationChange}
                className="space-y-4"
              >
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="dynamic" id="dynamic" className="border-gray-600" />
                  <Label htmlFor="dynamic" className="text-white">Dynamic</Label>
                </div>
                <div className="flex items-center space-x-2">
                  <RadioGroupItem value="reserved" id="reserved" className="border-gray-600" />
                  <Label htmlFor="reserved" className="text-white">Reserved</Label>
                </div>
              </RadioGroup>
            </div>

            {selectedAllocation === "reserved" && (
              <div className="space-y-2">
                <Label htmlFor="ip-address" className="text-gray-400">Reserved IP Address</Label>
                <Input
                  id="ip-address"
                  value={ipAddress}
                  onChange={(e) => setIpAddress(e.target.value)}
                  className="bg-[#222632] border-gray-700 text-white"
                  placeholder="Enter IP address"
                />
              </div>
            )}

            <div className="space-y-2">
              <p className="text-gray-400 text-sm">
                Dynamic is the default option. Your device will receive a dynamic IP address. If you want your device to always have the same IP address, select Reserved.
              </p>
              <p className="text-gray-400 text-sm">
                Reserved - If you want your device to always have the same IP address, select Reserved.
              </p>
            </div>

            <div className="bg-[#222632] p-4 rounded">
              <div className="flex justify-between items-center">
                <span className="text-white">Current IP Address</span>
                <span className="text-white">{currentIp}</span>
              </div>
            </div>

            {selectedAllocation === "reserved" && (
              <Button 
                onClick={handleSave}
                className="w-full bg-dashboard-accent hover:bg-dashboard-accent/90"
              >
                Save Changes
              </Button>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}