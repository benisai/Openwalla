import { toast } from "@/hooks/use-toast";
import { getConfig, updateConfig } from "@/config/openwalla.config";

export const fetchExternalIP = async (): Promise<string> => {
  try {
    const response = await fetch('https://api.ipify.org');
    if (!response.ok) {
      throw new Error('Failed to fetch IP address');
    }
    const newIP = await response.text();
    const currentIP = getConfig('wan_ip');
    
    if (currentIP !== newIP) {
      updateConfig('wan_ip', newIP);
      if (currentIP) { // Only show notification if it's not the first fetch
        toast({
          title: "WAN IP Changed",
          description: `Your external IP address has changed from ${currentIP} to ${newIP}`,
          duration: 5000,
        });
      }
    }
    
    return newIP;
  } catch (error) {
    console.error('Error fetching IP:', error);
    toast({
      variant: "destructive",
      title: "Error Fetching IP",
      description: "Could not retrieve your external IP address",
      duration: 5000,
    });
    return '0.0.0.0';
  }
};