import { Card } from "@/components/ui/card";
import { Smartphone } from "lucide-react";
import { Link } from "react-router-dom";
import { useDevices } from "@/services/DeviceService";

export function DevicesCard() {
  const { data: devices } = useDevices();
  const deviceCount = devices?.length ?? 0;

  return (
    <Link to="/devices">
      <Card className="bg-dashboard-card p-4 flex flex-col items-center justify-center hover:bg-dashboard-card/80 transition-colors">
        <Smartphone className="w-6 h-6 text-dashboard-accent mb-2" />
        <span className="text-base md:text-2xl font-bold text-white">{deviceCount}</span>
        <span className="text-sm text-gray-400">Devices</span>
      </Card>
    </Link>
  );
}