import { ChevronLeft, Home, ChevronRight } from "lucide-react";
import { Link, useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { HostnameDialog } from "@/components/settings/HostnameDialog";
import { OpenwallaDialog } from "@/components/settings/OpenwallaDialog";
import { OpenWRTDialog } from "@/components/settings/OpenWRTDialog";
import { ServicesSection } from "@/components/settings/ServicesSection";
import { getConfig, updateConfig } from "@/config/openwalla.config";
import { fetchExternalIP } from "@/utils/network";

const Settings = () => {
  const navigate = useNavigate();
  const [isHostnameDialogOpen, setIsHostnameDialogOpen] = useState(false);
  const [isOpenwallaDialogOpen, setIsOpenwallaDialogOpen] = useState(false);
  const [isOpenWRTDialogOpen, setIsOpenWRTDialogOpen] = useState(false);
  const [hostname, setHostname] = useState(getConfig('hostname') || "Openwalla");
  const [externalIP, setExternalIP] = useState<string>('Loading...');
  
  useEffect(() => {
    const getExternalIP = async () => {
      const ip = await fetchExternalIP();
      setExternalIP(ip);
    };
    getExternalIP();
  }, []);

  const handleSaveHostname = (newHostname: string) => {
    setHostname(newHostname);
    updateConfig('hostname', newHostname);
    console.log("Hostname updated in config:", newHostname);
  };

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
                <span className="mr-2">{hostname}</span>
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
        currentHostname={hostname}
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