import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { getConfig, updateConfig } from "@/services/ConfigService";
import { toast } from "sonner";
import { CheckCircle, AlertCircle, Loader2 } from "lucide-react";
import axios from "axios";

interface OpenWRTDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface ConnectionTestResult {
  success: boolean;
  message?: string;
  details?: {
    reachable: boolean;
    authenticated: boolean;
    error?: string;
  };
}

export function OpenWRTDialog({ open, onOpenChange }: OpenWRTDialogProps) {
  const queryClient = useQueryClient();
  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig,
  });

  const [routerIP, setRouterIP] = useState(config?.router_ip || '');
  const [routerUser, setRouterUser] = useState(config?.openwrt_user || '');
  const [routerPassword, setRouterPassword] = useState(config?.openwrt_pass || '');
  const [luciPort, setLuciPort] = useState(config?.luci_port || '');
  const [showPortField, setShowPortField] = useState(Boolean(config?.luci_port));
  const [testingConnection, setTestingConnection] = useState(false);
  const [connectionResult, setConnectionResult] = useState<ConnectionTestResult | null>(null);

  // Update local state when config is loaded
  useState(() => {
    if (config) {
      setRouterIP(config.router_ip);
      setRouterUser(config.openwrt_user);
      setRouterPassword(config.openwrt_pass);
      setLuciPort(config.luci_port);
      setShowPortField(Boolean(config.luci_port));
    }
  });

  const handleSave = async () => {
    try {
      await updateConfig({
        router_ip: routerIP,
        openwrt_user: routerUser,
        openwrt_pass: routerPassword,
        luci_port: showPortField ? luciPort : ''
      });
      
      // Restart services that depend on router_ip
      const servicesToRestart = ['devices', 'vnstat', 'netify', 'openwrt'];
      const restartPromises = servicesToRestart.map(service => 
        axios.post(`/api/service-restart/${service}`).catch(err => 
          console.error(`Failed to restart ${service}:`, err)
        )
      );
      await Promise.all(restartPromises);
      
      await queryClient.invalidateQueries({ queryKey: ['config'] });
      toast.success('Settings saved and services restarted');
      onOpenChange(false);
    } catch (error) {
      console.error('Error saving settings:', error);
      toast.error('Failed to save settings');
    }
  };

  const testConnection = async () => {
    setTestingConnection(true);
    setConnectionResult(null);
    
    try {
      // First save current settings
      await updateConfig({
        router_ip: routerIP,
        openwrt_user: routerUser,
        openwrt_pass: routerPassword,
        luci_port: showPortField ? luciPort : ''
      });
      
      // Restart OpenWrt service to apply new settings
      await axios.post('/api/service-restart/openwrt');
      
      // Test connection with new settings
      const response = await axios.get<ConnectionTestResult>('/api/openwrt/test-connection');
      
      setConnectionResult(response.data);
      
      if (response.data.success) {
        toast.success(response.data.message || 'Connection successful!');
      } else {
        toast.error(response.data.message || 'Connection failed');
      }
    } catch (error) {
      console.error('Error testing OpenWrt connection:', error);
      const errorResult: ConnectionTestResult = {
        success: false,
        message: 'Connection test failed',
        details: {
          reachable: false,
          authenticated: false,
          error: error instanceof Error ? error.message : 'Unknown error'
        }
      };
      setConnectionResult(errorResult);
      toast.error('Connection test failed. Please check your settings.');
    } finally {
      setTestingConnection(false);
    }
  };

  const handlePortCheckboxChange = (checked: boolean) => {
    setShowPortField(checked);
    if (!checked) {
      setLuciPort('');
    }
  };

  const getConnectionStatus = () => {
    if (testingConnection) {
      return {
        icon: <Loader2 className="h-4 w-4 animate-spin" />,
        text: "Testing Connection...",
        className: "bg-blue-500 hover:bg-blue-600 border-blue-600"
      };
    }
    
    if (connectionResult?.success) {
      return {
        icon: <CheckCircle className="h-4 w-4" />,
        text: "Connection Successful",
        className: "bg-green-500 hover:bg-green-600 border-green-600"
      };
    }
    
    if (connectionResult && !connectionResult.success) {
      return {
        icon: <AlertCircle className="h-4 w-4" />,
        text: "Connection Failed",
        className: "bg-red-500 hover:bg-red-600 border-red-600"
      };
    }
    
    return {
      icon: null,
      text: "Test Connection",
      className: ""
    };
  };

  const status = getConnectionStatus();

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
            <div className="flex items-center justify-between mb-2">
              <label htmlFor="router-ip" className="text-gray-400 text-sm">
                ROUTER IP
              </label>
              <div className="flex items-center gap-1">
                <Checkbox
                  id="port-checkbox"
                  checked={showPortField}
                  onCheckedChange={handlePortCheckboxChange}
                  className="h-3 w-3"
                />
                <label htmlFor="port-checkbox" className="text-gray-400 text-xs cursor-pointer">
                  Luci Port
                </label>
              </div>
            </div>
            <Input
              id="router-ip"
              value={routerIP}
              onChange={(e) => setRouterIP(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              placeholder="192.168.1.1"
            />
          </div>
          
          {showPortField && (
            <div>
              <label htmlFor="luci-port" className="text-gray-400 text-sm block mb-2">
                LUCI PORT
              </label>
              <Input
                id="luci-port"
                value={luciPort}
                onChange={(e) => setLuciPort(e.target.value)}
                className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
                placeholder="8080"
              />
            </div>
          )}
          
          <div>
            <label htmlFor="router-user" className="text-gray-400 text-sm block mb-2">
              ROUTER USER
            </label>
            <Input
              id="router-user"
              value={routerUser}
              onChange={(e) => setRouterUser(e.target.value)}
              className="bg-[#222632] border border-gray-700 text-white focus:border-blue-500 focus:ring-1 focus:ring-blue-500"
              placeholder="root"
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
          
          <Button
            onClick={testConnection}
            disabled={testingConnection}
            variant="outline"
            className={`w-full ${status.className}`}
          >
            <div className="flex items-center justify-center gap-2">
              {status.icon}
              {status.text}
            </div>
          </Button>
          
          {connectionResult && (
            <div className="text-sm text-gray-400 space-y-1">
              <div>Status: {connectionResult.message}</div>
              {connectionResult.details && (
                <div className="space-y-1 text-xs">
                  <div>Reachable: {connectionResult.details.reachable ? '✓' : '✗'}</div>
                  <div>Authenticated: {connectionResult.details.authenticated ? '✓' : '✗'}</div>
                  {connectionResult.details.error && (
                    <div className="text-red-400">Error: {connectionResult.details.error}</div>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
