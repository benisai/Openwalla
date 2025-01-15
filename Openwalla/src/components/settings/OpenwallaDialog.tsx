import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { useState, useEffect } from "react";
import { useToast } from "@/hooks/use-toast";

interface OpenwallaDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function OpenwallaDialog({ open, onOpenChange }: OpenwallaDialogProps) {
  const [netdataUrl, setNetdataUrl] = useState('');
  const [netifyIp, setNetifyIp] = useState('');
  const [netifyPort, setNetifyPort] = useState('7150');
  const [pingAddress, setPingAddress] = useState('1.1.1.1');
  const { toast } = useToast();

  useEffect(() => {
    const loadConfig = async () => {
      try {
        const response = await fetch('/api/config');
        if (!response.ok) {
          throw new Error('Failed to load config');
        }
        const config = await response.json();
        console.log('Loaded server config:', config);
        
        setNetdataUrl(config.netdata_url || '');
        setNetifyIp(config.netify_ip || '');
        setNetifyPort(config.netify_port || '7150');
        setPingAddress(config.ping_address || '1.1.1.1');
      } catch (error) {
        console.error('Error loading config:', error);
        toast({
          variant: "destructive",
          title: "Error loading settings",
          description: "Could not load settings from server.",
        });
      }
    };

    if (open) {
      loadConfig();
    }
  }, [open, toast]);

  const handleSave = async () => {
    try {
      const config = {
        netdata_url: netdataUrl,
        netify_ip: netifyIp,
        netify_port: netifyPort,
        ping_address: pingAddress
      };
      
      const response = await fetch('/api/config', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(config),
      });

      if (!response.ok) {
        throw new Error('Failed to save config');
      }

      // Restart services after config update
      await Promise.all([
        fetch('/api/ping/restart', { method: 'POST' }),
        fetch('/api/netify/restart', { method: 'POST' })
      ]);

      const savedConfig = await response.json();
      console.log('Config saved successfully:', savedConfig);
      
      toast({
        title: "Settings saved",
        description: "Configuration updated successfully.",
      });

      onOpenChange(false);
    } catch (error) {
      console.error('Error saving config:', error);
      toast({
        variant: "destructive",
        title: "Error saving settings",
        description: "Could not save settings to server.",
      });
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md max-h-[80vh]">
        <DialogHeader className="space-y-4">
          <div className="flex justify-between items-center">
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <DialogTitle className="text-white">Openwalla Settings</DialogTitle>
            <Button 
              variant="ghost" 
              className="text-dashboard-accent hover:text-dashboard-accent/80 p-0"
              onClick={handleSave}
            >
              Save
            </Button>
          </div>
        </DialogHeader>

        <ScrollArea className="h-[calc(80vh-100px)] pr-4">
          <div className="space-y-8">
            <div>
              <h3 className="text-lg font-medium mb-2">Netdata Url</h3>
              <Input
                value={netdataUrl}
                onChange={(e) => setNetdataUrl(e.target.value)}
                className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                placeholder="http://localhost:19999"
              />
            </div>

            <div className="pt-4 border-t border-gray-800">
              <div className="space-y-4">
                <h3 className="text-lg font-medium">Netify Settings</h3>

                <div>
                  <label className="text-gray-400 text-sm block mb-2">
                    NETIFY IP
                  </label>
                  <Input
                    value={netifyIp}
                    onChange={(e) => setNetifyIp(e.target.value)}
                    className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                    placeholder="192.168.1.1"
                  />
                </div>

                <div>
                  <label className="text-gray-400 text-sm block mb-2">
                    NETIFY PORT
                  </label>
                  <Input
                    value={netifyPort}
                    onChange={(e) => setNetifyPort(e.target.value)}
                    className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                    placeholder="7150"
                  />
                </div>
              </div>
            </div>

            <div className="pt-4 border-t border-gray-800">
              <div className="space-y-4">
                <h3 className="text-lg font-medium">Internet Quality Test Settings</h3>
                
                <div>
                  <label className="text-gray-400 text-sm block mb-2">
                    PING ADDRESS
                  </label>
                  <Input
                    value={pingAddress}
                    onChange={(e) => setPingAddress(e.target.value)}
                    className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                    placeholder="1.1.1.1"
                  />
                </div>
              </div>
            </div>
          </div>
        </ScrollArea>
      </DialogContent>
    </Dialog>
  );
}
