import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useState } from "react";

interface HostnameDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  currentHostname: string;
  onSave: (hostname: string) => void;
}

export function HostnameDialog({ 
  open, 
  onOpenChange,
  currentHostname,
  onSave
}: HostnameDialogProps) {
  const [hostname, setHostname] = useState(currentHostname);

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
            <DialogTitle className="text-white">Hostname</DialogTitle>
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={() => {
                onSave(hostname);
                onOpenChange(false);
              }}
            >
              Save
            </Button>
          </div>
        </DialogHeader>

        <div className="mt-8 space-y-4">
          <div>
            <label htmlFor="hostname" className="text-gray-400 text-sm block mb-2">
              HOSTNAME
            </label>
            <Input
              id="hostname"
              value={hostname}
              onChange={(e) => setHostname(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
            />
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
