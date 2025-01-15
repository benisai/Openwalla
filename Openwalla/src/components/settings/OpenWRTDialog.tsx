import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useState } from "react";
import { getConfig, updateConfig } from "@/config/openwalla.config";

interface OpenWRTDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function OpenWRTDialog({ open, onOpenChange }: OpenWRTDialogProps) {
  const [routerIP, setRouterIP] = useState(getConfig('openwrt_ip'));
  const [routerUser, setRouterUser] = useState(getConfig('openwrt_user'));
  const [routerPassword, setRouterPassword] = useState(getConfig('openwrt_pass'));

  const handleSave = () => {
    updateConfig('openwrt_ip', routerIP);
    updateConfig('openwrt_user', routerUser);
    updateConfig('openwrt_pass', routerPassword);
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
            <DialogTitle className="text-white">OpenWRT Settings</DialogTitle>
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={handleSave}
            >
              Save
            </Button>
          </div>
        </DialogHeader>

        <div className="mt-8 space-y-4">
          <div>
            <label htmlFor="router-ip" className="text-gray-400 text-sm block mb-2">
              ROUTER IP
            </label>
            <Input
              id="router-ip"
              value={routerIP}
              onChange={(e) => setRouterIP(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
            />
          </div>
          <div>
            <label htmlFor="router-user" className="text-gray-400 text-sm block mb-2">
              ROUTER USER
            </label>
            <Input
              id="router-user"
              value={routerUser}
              onChange={(e) => setRouterUser(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
            />
          </div>
          <div>
            <label htmlFor="router-password" className="text-gray-400 text-sm block mb-2">
              ROUTER PASSWORD
            </label>
            <Input
              id="router-password"
              type="password"
              value={routerPassword}
              onChange={(e) => setRouterPassword(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
            />
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}