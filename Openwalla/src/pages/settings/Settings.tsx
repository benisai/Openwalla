import { ChevronLeft, Home, ChevronRight } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { HostnameDialog } from "@/pages/settings/components/HostnameDialog";
import { OpenwallaDialog } from "@/pages/settings/components/OpenwallaDialog";
import { OpenWRTDialog } from "@/pages/settings/components/OpenWRTDialog";
import { ServicesSection } from "@/pages/settings/components/ServicesSection";
import { getConfig, updateConfig } from "@/services/ConfigService";
import { fetchExternalIP } from "@/misc/utils/fetch_wan_ip";
import { useQuery } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";

const Settings = () => {
  const navigate = useNavigate();
  const [isHostnameDialogOpen, setIsHostnameDialogOpen] = useState(false);
  const [isOpenwallaDialogOpen, setIsOpenwallaDialogOpen] = useState(false);
  const [isOpenWRTDialogOpen, setIsOpenWRTDialogOpen] = useState(false);
  const [externalIP, setExternalIP] = useState<string>('Loading...');
  const { toast } = useToast();

  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig
  });

  const handleSaveHostname = async (newHostname: string) => {
    try {
      await updateConfig({ hostname: newHostname });
      toast({
        title: "Success",
        description: "Hostname updated successfully",
      });
    } catch (error) {
      toast({
        variant: "destructive",
        title: "Error",
        description: "Failed to update hostname",
      });
    }
  };

  useEffect(() => {
    const getExternalIP = async () => {
      const ip = await fetchExternalIP();
      setExternalIP(ip);
    };
    getExternalIP();
  }, []);

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4">
      <div className="max-w-4xl mx-auto">
        <header className="flex items-center justify-between mb-6">
          <button
            onClick={() => navigate(-1)}
            className="text-dashboard-accent hover:opacity-80"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <h1 className="text-xl font-bold">Settings</h1>
          <button
            onClick={() => navigate("/")}
            className="text-dashboard-accent hover:opacity-80"
          >
            <Home className="w-6 h-6" />
          </button>
        </header>

        <div className="space-y-4">
          <div className="bg-dashboard-card rounded-lg overflow-hidden">
            <div 
              className="flex items-center justify-between p-4 border-b border-gray-800 cursor-pointer"
              onClick={() => setIsHostnameDialogOpen(true)}
            >
              <span className="text-lg">Hostname</span>
              <div className="flex items-center text-gray-400">
                <span className="mr-2">{config?.hostname || 'Loading...'}</span>
                <ChevronRight className="w-5 h-5" />
              </div>
            </div>

            <div className="flex items-center justify-between p-4 border-b border-gray-800">
              <span className="text-lg">WAN IP</span>
              <span className="text-gray-400">{externalIP}</span>
            </div>

            <div 
              className="flex items-center justify-between p-4 border-b border-gray-800 cursor-pointer"
              onClick={() => setIsOpenwallaDialogOpen(true)}
            >
              <span className="text-lg">Openwalla Settings</span>
              <ChevronRight className="w-5 h-5 text-gray-400" />
            </div>

            <div 
              className="flex items-center justify-between p-4 border-b border-gray-800 cursor-pointer"
              onClick={() => setIsOpenWRTDialogOpen(true)}
            >
              <span className="text-lg">OpenWRT Settings</span>
              <ChevronRight className="w-5 h-5 text-gray-400" />
            </div>

            <div className="p-4 border-b border-gray-800">
              <ServicesSection />
            </div>

            <Link to="/settings/more-info" className="flex items-center justify-between p-4">
              <span className="text-lg">More Info</span>
              <ChevronRight className="w-5 h-5 text-gray-400" />
            </Link>
          </div>
        </div>
      </div>

      <HostnameDialog
        open={isHostnameDialogOpen}
        onOpenChange={setIsHostnameDialogOpen}
        currentHostname={config?.hostname || ''}
        onSave={handleSaveHostname}
      />

      <OpenwallaDialog
        open={isOpenwallaDialogOpen}
        onOpenChange={setIsOpenwallaDialogOpen}
      />

      <OpenWRTDialog
        open={isOpenWRTDialogOpen}
        onOpenChange={setIsOpenWRTDialogOpen}
      />
    </div>
  );
};

export default Settings;
