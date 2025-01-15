import { Network } from "lucide-react";

interface NetworkItemProps {
  name: string;
  deviceCount: number;
}

const NetworkItem = ({ name, deviceCount }: NetworkItemProps) => {
  return (
    <div className="flex items-center justify-between p-4 bg-dashboard-card rounded-lg mb-2">
      <div className="flex items-center gap-4">
        <Network className="w-6 h-6 text-blue-500" />
        <div>
          <h3 className="font-medium text-white">{name}</h3>
          <p className="text-sm text-gray-400">{deviceCount} Devices</p>
        </div>
      </div>
    </div>
  );
};

export default NetworkItem;